//
//  ZHNATests.m
//  在 macOS 上跑的自测，用来验证规则正确、且不会误伤正常内容。
//  运行：bash tests/run_tests.sh
//

#import <Foundation/Foundation.h>
#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNARules.h"
#import "ZHNAJSONFilter.h"

static int gPass = 0;
static int gFail = 0;

static void CHECK(BOOL cond, NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *desc = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    if (cond) {
        gPass++;
        printf("  \033[32m✓\033[0m %s\n", desc.UTF8String);
    } else {
        gFail++;
        printf("  \033[31m✗ 失败\033[0m %s\n", desc.UTF8String);
    }
}

#pragma mark - 1. URL 规则

static void TestURLRules(void) {
    printf("\n[1] URL 拦截规则\n");

    NSArray *shouldBlock = @[
        @"https://api.zhihu.com/commercial_api/app_float_layer",
        @"https://api.zhihu.com/ad-style-service/request",
        @"https://www.zhihu.com/commercial_api/banners_v3/mobile_banner",
        @"https://api.zhihu.com/fringe/ad",
        @"https://api.zhihu.com/distribute/rhea/qa_ad_card/h5/recommendation?x=1",
        @"https://api.zhihu.com/comment_v5/answers/123456/list-headers",
        @"https://www.zhihu.com/api/v4/answers/98765/recommendations?limit=5",
        @"https://www.zhihu.com/api/v4/questions/12345/related-readings",
        @"https://api.zhihu.com/search/hot_search?limit=20",
        @"https://api.zhihu.com/search/preset_words",
        @"https://api.zhihu.com/root/window",
        @"https://api.zhihu.com/me/guides",
        @"https://api.zhihu.com/bazaar/float_window",
        @"https://zhuanlan.zhihu.com/api/articles/555/recommendation",
        @"https://crash2.zhihu.com/upload",
        @"https://sugar.zhihu.com/track",
        @"https://api.zhihu.com/v5.1/topics/answer/111/relation",
        @"https://appcloud2.zhihu.com/v3/resource?group_name=mp",
    ];
    for (NSString *u in shouldBlock) {
        ZHNAURLVerdict *v = ZHNAMatchURL([NSURL URLWithString:u]);
        CHECK(v != nil, @"拦截 %@ %@", u, v ? [NSString stringWithFormat:@"(%@)", v.ruleName] : @"");
    }

    // 正常接口绝对不能被拦
    NSArray *shouldPass = @[
        @"https://api.zhihu.com/topstory/recommend?action=down",
        @"https://api.zhihu.com/questions/12345/answers?limit=10",
        @"https://www.zhihu.com/api/v4/members/foo/answers",
        @"https://api.zhihu.com/people/self",
        @"https://pic1.zhimg.com/v2-abcdef.jpg",
        @"https://api.zhihu.com/notifications/v3/count",
        @"https://api.zhihu.com/messages",
        @"https://www.zhihu.com/api/v4/comment_v5/answers/1/root_comment",
        @"https://api.zhihu.com/upload/image",
        @"https://www.baidu.com/",
    ];
    for (NSString *u in shouldPass) {
        ZHNAURLVerdict *v = ZHNAMatchURL([NSURL URLWithString:u]);
        CHECK(v == nil, @"放行 %@ %@", u, v ? [NSString stringWithFormat:@"← 被 %@ 误伤!", v.ruleName] : @"");
    }
}

#pragma mark - 2. 类名匹配（防误伤是重点）

static void TestClassNames(void) {
    printf("\n[2] 类名识别（UI 兜底）\n");

    NSArray *adNames = @[ @"ZHAdView", @"ZHAdsManager", @"ZHFeedAdCell",
                          @"ZHAdvertisementView", @"ZHCommercialAdBanner",
                          @"ZHLaunchAdViewController", @"ZHSponsorCard",
                          @"ZHAD_Container", @"ZHMarketCardView" ];
    for (NSString *n in adNames) {
        CHECK(ZHNAClassNameLooksLikeAd(n), @"识别为广告: %@", n);
    }

    // 这些是最容易误伤的正常类名
    NSArray *normalNames = @[ @"ZHHeaderView", @"ZHDownloadManager", @"ZHUploadTask",
                              @"ZHBadgeView", @"ZHAddressCell", @"ZHAdapterProxy",
                              @"ZHShadowView", @"ZHThreadPool", @"ZHGradientLayer",
                              @"ZHReadingProgress", @"ZHImageLoader", @"ZHRadioButton",
                              @"ZHAdvanceSettings", @"ZHAdjustHelper", @"ZHSpreadSheet",
                              @"UITableViewCell", @"NSLayoutConstraint", @"WKWebView" ];
    for (NSString *n in normalNames) {
        CHECK(!ZHNAClassNameLooksLikeAd(n), @"未误伤: %@", n);
    }

    printf("\n[3] 开屏广告控制器识别\n");
    NSArray *splash = @[ @"ZHLaunchAdViewController", @"ZHSplashAdVC",
                         @"ZHOpenScreenAdView", @"ZHLaunchAdvertisementVC" ];
    for (NSString *n in splash) {
        CHECK(ZHNAClassNameLooksLikeSplashAd(n), @"识别为开屏广告: %@", n);
    }
    NSArray *notSplash = @[ @"ZHLaunchViewController", @"ZHSplashScreen", @"ZHHomeViewController" ];
    for (NSString *n in notSplash) {
        CHECK(!ZHNAClassNameLooksLikeSplashAd(n), @"未误伤: %@", n);
    }
}

#pragma mark - 4. JSON 清洗

static NSDictionary *SampleFeed(void) {
    return @{
        @"paging": @{ @"is_end": @NO, @"next": @"https://api.zhihu.com/topstory/recommend?after=20" },
        @"fresh_text": @"为你更新了 10 条内容",
        @"ad_info": @{ @"ad": @{ @"id": @"888" }, @"adjson": @"{}", @"position": @12 },
        @"data": @[
            @{ @"type": @"feed",
               @"target": @{ @"type": @"answer", @"id": @1001,
                             @"excerpt": @"这是一条正常回答",
                             @"author": @{ @"name": @"张三" } } },
            @{ @"type": @"feed_advert",
               @"ad_json": @"{...}",
               @"target": @{ @"type": @"advert", @"title": @"某某广告" } },
            @{ @"type": @"market_card",
               @"target": @{ @"type": @"market", @"title": @"课程带货" } },
            @{ @"type": @"feed",
               @"target": @{ @"type": @"article", @"id": @1002, @"title": @"正常文章" } },
            @{ @"type": @"feed",
               @"target": @{ @"type": @"answer", @"id": @1003,
                             @"answer_type": @"paid",
                             @"excerpt": @"盐选故事引流" } },
            @{ @"type": @"slot_event",
               @"is_advertisement": @YES,
               @"target": @{ @"title": @"活动位" } },
            @{ @"type": @"feed",
               @"target": @{ @"type": @"zvideo", @"id": @1004, @"title": @"正常视频" } },
        ],
    };
}

static void TestJSONFilter(void) {
    printf("\n[4] JSON 清洗\n");

    NSDictionary *input = SampleFeed();
    NSData *raw = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];

    CHECK(ZHNADataMayContainAd(raw), @"预检能识别出这段数据含广告");

    ZHNAFilterResult *r = ZHNAFilterJSONObject(input);
    NSDictionary *out = r.object;
    NSArray *data = out[@"data"];

    CHECK(out[@"ad_info"] == nil, @"顶层 ad_info 已删除");
    CHECK(out[@"paging"] != nil, @"paging 保留");
    CHECK([out[@"fresh_text"] isEqualToString:@"为你更新了 10 条内容"], @"fresh_text 保留");
    CHECK(data.count == 3, @"7 条内容过滤后剩 3 条正常内容（实际 %lu 条）", (unsigned long)data.count);

    BOOL hasAd = NO, hasPaid = NO, hasNormal = NO;
    for (NSDictionary *item in data) {
        NSString *t = item[@"type"];
        if (ZHNATypeStringIsAd(t)) hasAd = YES;
        if (ZHNAIsPaidItem(item)) hasPaid = YES;
        if ([t isEqualToString:@"feed"]) hasNormal = YES;
    }
    CHECK(!hasAd, @"广告条目全部清除");
    CHECK(!hasPaid, @"付费引流条目已清除");
    CHECK(hasNormal, @"正常内容仍在");
    CHECK(r.removedItems >= 3, @"统计到 %ld 条广告条目", (long)r.removedItems);
    CHECK(r.removedPaid == 1, @"统计到 %ld 条付费引流", (long)r.removedPaid);

    // 纯净数据不应被改动
    NSDictionary *clean = @{ @"data": @[ @{ @"type": @"feed", @"target": @{ @"id": @1 } } ],
                             @"paging": @{ @"is_end": @YES } };
    ZHNAFilterResult *r2 = ZHNAFilterJSONObject(clean);
    CHECK(!r2.changed, @"纯净数据不会被误改");

    NSData *cleanData = [NSJSONSerialization dataWithJSONObject:clean options:0 error:nil];
    CHECK(!ZHNADataMayContainAd(cleanData), @"纯净数据在预检阶段直接放行（零开销）");

    // 清洗结果必须仍是合法 JSON
    CHECK([NSJSONSerialization isValidJSONObject:out], @"清洗后仍是合法 JSON");
}

#pragma mark - 5. 开关

static void TestConfig(void) {
    printf("\n[5] 开关逻辑\n");

    ZHNAConfigResetToDefault();
    CHECK(ZHNAConfigBool(ZHNAKeyFeed), @"默认开启信息流过滤");

    ZHNAConfigSetBool(ZHNAKeyMaster, NO);
    CHECK(!ZHNAConfigBool(ZHNAKeyFeed), @"总开关关闭后，子项一律失效");
    CHECK(ZHNAMatchURL([NSURL URLWithString:@"https://api.zhihu.com/commercial_api/x"]) == nil,
          @"总开关关闭后不再拦截任何请求");

    ZHNAConfigSetBool(ZHNAKeyMaster, YES);
    ZHNAConfigSetBool(ZHNAKeySearch, NO);
    CHECK(ZHNAMatchURL([NSURL URLWithString:@"https://api.zhihu.com/search/hot_search"]) == nil,
          @"单独关闭搜索项后，热搜接口恢复正常");
    CHECK(ZHNAMatchURL([NSURL URLWithString:@"https://api.zhihu.com/commercial_api/x"]) != nil,
          @"其他项不受影响");

    ZHNAConfigResetToDefault();
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        printf("=== 知乎去广告 插件自测 ===\n");
        ZHNAConfigResetToDefault();
        TestURLRules();
        TestClassNames();
        TestJSONFilter();
        TestConfig();

        printf("\n=========================\n");
        printf("通过 %d 项，失败 %d 项\n", gPass, gFail);
        return gFail == 0 ? 0 : 1;
    }
}
