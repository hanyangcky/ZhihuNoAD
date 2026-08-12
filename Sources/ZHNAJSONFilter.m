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

static NSDictionary *ZHNACleanDictionary(NSDictionary *dict, NSInteger depth, ZHNAFilterCtx *ctx) {
    NSMutableDictionary *out = nil;

    for (id rawKey in dict) {
        if (![rawKey isKindOfClass:[NSString class]]) continue;
        NSString *key = (NSString *)rawKey;
        id value = dict[key];

        // 1) 整个字段就是广告 -> 删掉
        if (ctx->filterFeed && ZHNAIsAdKey(key)) {
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
            if (ctx->filterFeed && ZHNAIsAdItem(d)) {
                drop = YES;
                ctx->removedItems++;
                if (ctx->debug) ZHNALog(@"删除广告条目: type=%@", d[@"type"] ?: @"?");
            } else if (ctx->filterPaid && ZHNAIsPaidItem(d)) {
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
