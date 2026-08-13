//
//  ZHNAJSONFilter.m
//

#import "ZHNAJSONFilter.h"
#import "ZHNARules.h"
#import "ZHNAConfig.h"
#import "ZHNACommon.h"

static const NSInteger kZHNAMaxDepth = 24;

@implementation ZHNAFilterResult
- (BOOL)changed {
    return (self.removedKeys + self.removedItems + self.removedPaid) > 0;
}
@end

typedef struct {
    NSInteger removedKeys;
    NSInteger removedItems;
    NSInteger removedPaid;
    BOOL filterFeed;
    BOOL filterPaid;
    BOOL debug;
} ZHNAFilterCtx;

static id ZHNACleanValue(id value, NSInteger depth, ZHNAFilterCtx *ctx);

#pragma mark - 真实内容保护（v1.1.2 修复连续阅读误删）

/// 一组"真实内容"强特征键。只要一个条目/字段带有这些键，几乎可以肯定是真实的
/// 回答/文章（而不是广告），用于在"广告与正常内容混在同一份 JSON"的场景里保护它们，
/// 绝不误删真实内容——这正是连续阅读(下滑加载下一个回答)此前被一刀切搞断的根因。
static NSSet *ZHNAContentKeys(void) {
    static NSSet *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[
            @"content", @"excerpt", @"excerpt_content", @"excerpt_title",
            @"answer_id", @"article_id", @"question_id", @"voteup_count",
            @"author", @"author_info", @"created_time", @"updated_time",
            @"comment_count", @"voteup", @"thumbnail",
            @"body", @"target", @"relationship"
        ]];
    });
    return s;
}

/// 值是否像是"真实内容"：
///  - 数组一律视为潜在内容（交给条目级清洗去剔里面的广告条目，不要整段删掉）；
///  - 字典只有在带有内容特征键时才算内容；
///  - 标量(字符串/数字/null)永远不算。
static BOOL ZHNAValueLooksLikeRealContent(id value) {
    if ([value isKindOfClass:[NSArray class]]) return YES;
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)value;
        NSSet *ck = ZHNAContentKeys();
        for (id k in d) {
            if ([k isKindOfClass:[NSString class]] && [ck containsObject:k]) return YES;
        }
    }
    return NO;
}

/// 条目是否是真实内容对象（绝不应当被当成广告整条删除）。
static BOOL ZHNAItemLooksLikeRealContent(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;
    NSSet *ck = ZHNAContentKeys();
    for (id k in item) {
        if ([k isKindOfClass:[NSString class]] && [ck containsObject:k]) return YES;
    }
    return NO;
}

static NSDictionary *ZHNACleanDictionary(NSDictionary *dict, NSInteger depth, ZHNAFilterCtx *ctx) {
    NSMutableDictionary *out = nil;

    for (id rawKey in dict) {
        if (![rawKey isKindOfClass:[NSString class]]) continue;
        NSString *key = (NSString *)rawKey;
        id value = dict[key];

        // 1) 整个字段就是广告 -> 删掉（但值若是真实内容则放过，避免误伤连续阅读等）
        if (ctx->filterFeed && ZHNAIsAdKey(key) && !ZHNAValueLooksLikeRealContent(value)) {
            // 只有当值确实有内容时才算"删掉了东西"，避免把本来就是 null 的字段算进统计
            BOOL meaningful = !(value == nil
                                || value == (id)kCFNull
                                || ([value respondsToSelector:@selector(count)] && [value count] == 0));
            if (!out) out = [dict mutableCopy];
            [out removeObjectForKey:key];
            if (meaningful) {
                ctx->removedKeys++;
                if (ctx->debug) ZHNALog(@"删除广告字段: %@", key);
            }
            continue;
        }

        // 2) 递归清洗
        id cleaned = ZHNACleanValue(value, depth + 1, ctx);
        if (cleaned != value) {
            if (!out) out = [dict mutableCopy];
            out[key] = cleaned;
        }
    }

    return out ? [out copy] : dict;
}

static NSArray *ZHNACleanArray(NSArray *array, NSInteger depth, ZHNAFilterCtx *ctx) {
    NSMutableArray *out = nil;

    for (NSUInteger i = 0; i < array.count; i++) {
        id item = array[i];

        if ([item isKindOfClass:[NSDictionary class]]) {
            NSDictionary *d = (NSDictionary *)item;

            BOOL drop = NO;
            // 关键(v1.1.2)：整条删除前先确认它不是真实回答/文章，否则会连"下一个回答"一起删掉，
            // 导致连续阅读断掉。真实内容即使混入广告特征也一律保留。
            if (ctx->filterFeed && ZHNAIsAdItem(d) && !ZHNAItemLooksLikeRealContent(d)) {
                drop = YES;
                ctx->removedItems++;
                if (ctx->debug) ZHNALog(@"删除广告条目: type=%@", d[@"type"] ?: @"?");
            } else if (ctx->filterPaid && ZHNAIsPaidItem(d) && !ZHNAItemLooksLikeRealContent(d)) {
                drop = YES;
                ctx->removedPaid++;
                if (ctx->debug) ZHNALog(@"删除付费引流条目");
            }

            if (drop) {
                if (!out) out = [[array subarrayWithRange:NSMakeRange(0, i)] mutableCopy];
                continue;
            }
        }

        id cleaned = ZHNACleanValue(item, depth + 1, ctx);
        if (out) {
            [out addObject:cleaned];
        } else if (cleaned != item) {
            out = [[array subarrayWithRange:NSMakeRange(0, i)] mutableCopy];
            [out addObject:cleaned];
        }
    }

    return out ? [out copy] : array;
}

static id ZHNACleanValue(id value, NSInteger depth, ZHNAFilterCtx *ctx) {
    if (depth > kZHNAMaxDepth) return value;
    if ([value isKindOfClass:[NSDictionary class]]) {
        return ZHNACleanDictionary((NSDictionary *)value, depth, ctx);
    }
    if ([value isKindOfClass:[NSArray class]]) {
        return ZHNACleanArray((NSArray *)value, depth, ctx);
    }
    return value;
}

ZHNAFilterResult *ZHNAFilterJSONObject(id object) {
    ZHNAFilterResult *result = [ZHNAFilterResult new];
    result.object = object;
    if (object == nil) return result;
    if (![object isKindOfClass:[NSDictionary class]] && ![object isKindOfClass:[NSArray class]]) {
        return result;
    }

    ZHNAFilterCtx ctx = {0};
    ctx.filterFeed = ZHNAConfigBool(ZHNAKeyFeed) || ZHNAConfigBool(ZHNAKeyDetail);
    ctx.filterPaid = ZHNAConfigBool(ZHNAKeyPaid);
    ctx.debug      = ZHNAConfigBool(ZHNAKeyDebug);

    if (!ctx.filterFeed && !ctx.filterPaid) return result;

    result.object       = ZHNACleanValue(object, 0, &ctx);
    result.removedKeys  = ctx.removedKeys;
    result.removedItems = ctx.removedItems;
    result.removedPaid  = ctx.removedPaid;
    return result;
}
