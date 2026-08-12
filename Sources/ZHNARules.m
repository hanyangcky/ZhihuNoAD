//
//  ZHNARules.m
//
//  规则来源：对知乎 iOS 客户端商业化接口的公开整理
//  （社区 Surge/Loon/AdGuard 去广告模块的规则集，转写为客户端内置规则）
//

#import "ZHNARules.h"
#import "ZHNAConfig.h"
#import "ZHNACommon.h"
#import <string.h>

@implementation ZHNAURLVerdict
@end

#pragma mark - URL 规则表

/// 编译好的规则
@interface ZHNACompiledRule : NSObject
@property (nonatomic, strong) NSRegularExpression *regex;
@property (nonatomic, assign) ZHNAAction action;
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *categoryKey;
@end
@implementation ZHNACompiledRule
@end

static NSArray<ZHNACompiledRule *> *ZHNACompiledRules(void) {
    static NSArray *rules;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 每一行：正则, 动作, 规则名, 所属开关
        NSArray *raw = @[
            // ===== 开屏广告 =====
            @[@"^https?://[^/]*\\.zhihu\\.com/ad-style-service/", @(ZHNAActionEmptyJSON), @"开屏广告素材下发", ZHNAKeySplash],
            @[@"^https?://[^/]*\\.zhihu\\.com/.*/launch[-_]?ad", @(ZHNAActionEmptyJSON), @"开屏广告接口", ZHNAKeySplash],
            @[@"^https?://[^/]*\\.zhihu\\.com/fringe/ad", @(ZHNAActionEmptyJSON), @"角标广告", ZHNAKeySplash],

            // ===== 通用商业化接口（覆盖面最大的一条）=====
            @[@"^https?://[^/]*\\.zhihu\\.com/commercial_api/", @(ZHNAActionEmptyJSON), @"商业化接口", ZHNAKeyFeed],
            @[@"^https?://[^/]*\\.zhihu\\.com/[^?]*/adx/", @(ZHNAActionEmptyJSON), @"广告交易接口", ZHNAKeyFeed],
            @[@"^https?://[^/]*\\.zhihu\\.com/ad/", @(ZHNAActionEmptyJSON), @"广告接口", ZHNAKeyFeed],

            // ===== 回答/文章详情页推广 =====
            @[@"^https?://[^/]*\\.zhihu\\.com/.*featured-comment-ad", @(ZHNAActionEmptyJSON), @"评论区精选广告", ZHNAKeyDetail],
            @[@"^https?://[^/]*\\.zhihu\\.com/distribute/rhea/qa_ad_card/", @(ZHNAActionEmptyJSON), @"问答广告卡片", ZHNAKeyDetail],
            @[@"^https?://[^/]*\\.zhihu\\.com/comment_v5/(articles|answers)/\\d+/list-headers", @(ZHNAActionEmptyJSON), @"评论区顶部推广", ZHNAKeyDetail],
            @[@"^https?://[^/]*\\.zhihu\\.com/prague/related_suggestion_native/feed", @(ZHNAActionEmptyJSON), @"相关推荐信息流", ZHNAKeyDetail],
            @[@"^https?://[^/]*\\.zhihu\\.com/v5\\.1/topics/answer/\\d+/relation", @(ZHNAActionEmptyJSON), @"回答话题关联推广", ZHNAKeyDetail],

            // ⚠️ 下面两个接口【故意不放行】——它们是知乎"连续阅读 / 下滑加载下一个回答"的数据源。
            // 之前用 EmptyJSON 一刀切会清空整条响应，导致点进某个回答后下滑就没有下一个回答。
            // 改为放行，让真实数据返回，由第二道防线(NSJSONSerialization 清洗)把其中的广告条目剔掉，
            // 既恢复连续阅读，又保留去广告效果。
            //   api/v4/(answers|questions)/\d+/related-readings
            //   api/v4/(articles|answers)/\d+/recommendations?
            @[@"^https?://zhuanlan\\.zhihu\\.com/api/articles/\\d+/recommendation", @(ZHNAActionEmptyJSON), @"专栏文章推荐位", ZHNAKeyDetail],
            @[@"^https?://[^/]*\\.zhihu\\.com/api/v4/mcn/v2/linkcards", @(ZHNAActionEmptyJSON), @"MCN 带货卡片", ZHNAKeyDetail],
            @[@"^https?://[^/]*\\.zhihu\\.com/appview/api/[^/]+/recommendations", @(ZHNAActionEmptyJSON), @"内嵌页推荐位", ZHNAKeyDetail],

            // ===== 搜索页 =====
            @[@"^https?://[^/]*\\.zhihu\\.com/search/(hot_search|preset_words)", @(ZHNAActionEmptyJSON), @"搜索热词/预置词", ZHNAKeySearch],
            @[@"^https?://[^/]*\\.zhihu\\.com/search/recommend_query", @(ZHNAActionEmptyJSON), @"搜索推荐词", ZHNAKeySearch],
            @[@"^https?://[^/]*\\.zhihu\\.com/api/v4/search/clicked_recommendation", @(ZHNAActionEmptyJSON), @"搜索点击推荐", ZHNAKeySearch],
            @[@"^https?://[^/]*\\.zhihu\\.com/api/v4/search/related_queries/", @(ZHNAActionEmptyJSON), @"相关搜索词", ZHNAKeySearch],

            // ===== 弹窗 / 浮层 / 引导 =====
            @[@"^https?://[^/]*\\.zhihu\\.com/root/window", @(ZHNAActionEmptyJSON), @"首页弹窗", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/(bazaar/float_window|market/popovers_v2)", @(ZHNAActionEmptyJSON), @"浮窗/气泡弹层", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/me/guides", @(ZHNAActionEmptyJSON), @"新手引导弹层", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/people/homepage_entry_v2", @(ZHNAActionEmptyJSON), @"个人页运营入口", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/content-distribution-core/bubble/", @(ZHNAActionEmptyJSON), @"气泡引导", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/(moments/lastread|drama/hot-drama-list)", @(ZHNAActionEmptyJSON), @"想法/剧集运营位", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/api/v4/hot_recommendation", @(ZHNAActionEmptyJSON), @"热门推荐位", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/unlimited/go/my_card", @(ZHNAActionEmptyJSON), @"会员卡推广", ZHNAKeyPopup],
            @[@"^https?://appcloud2\\.zhihu\\.com/v3/resource\\?group_name=mp", @(ZHNAActionEmptyJSON), @"运营资源下发", ZHNAKeyPopup],

            // ===== 来自用户 Shadowrocket 规则、上面未覆盖的几条（如不需要可自行删除）=====
            @[@"^https?://[^/]*\\.zhihu\\.com/ecom_data/config", @(ZHNAActionEmptyJSON), @"推荐页顶部广告位", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/feed/render/revisit/", @(ZHNAActionEmptyJSON), @"搜索栏红点/左侧图标", ZHNAKeyPopup],
            @[@"^https?://[^/]*\\.zhihu\\.com/v2/resolv", @(ZHNAActionDeny), @"广告解析请求", ZHNAKeyTracking],

            // ===== 埋点 / 崩溃上报 / 广告SDK =====
            @[@"^https?://(appcloud|appcloud2\\.in|crash2|sugar|mqtt)\\.zhihu\\.com/", @(ZHNAActionDeny), @"知乎埋点域名", ZHNAKeyTracking],
            @[@"^https?://zxid-m\\.mobileservice\\.cn/", @(ZHNAActionDeny), @"第三方标识服务", ZHNAKeyTracking],
            @[@"^https?://[^/]*\\.pangolin-sdk-toutiao(-b)?\\.com/", @(ZHNAActionDeny), @"穿山甲广告SDK", ZHNAKeyTracking],
            @[@"^https?://[^/]*gdt\\.qq\\.com/", @(ZHNAActionDeny), @"优量汇广告SDK", ZHNAKeyTracking],
            @[@"^https?://[^/]*\\.zhihu\\.com/(udid|monitor|apm)/", @(ZHNAActionDeny), @"性能与设备埋点", ZHNAKeyTracking],
        ];

        NSMutableArray *out = [NSMutableArray array];
        for (NSArray *row in raw) {
            NSError *err = nil;
            NSRegularExpression *re = [NSRegularExpression
                regularExpressionWithPattern:row[0]
                                     options:NSRegularExpressionCaseInsensitive
                                       error:&err];
            if (!re) {
                NSLog(@"[ZhihuNoAds] 规则编译失败: %@ (%@)", row[0], err);
                continue;
            }
            ZHNACompiledRule *r = [ZHNACompiledRule new];
            r.regex = re;
            r.action = (ZHNAAction)[row[1] integerValue];
            r.name = row[2];
            r.categoryKey = row[3];
            [out addObject:r];
        }
        rules = [out copy];
    });
    return rules;
}

/// 快速域名预筛：绝大多数请求在这一步就被放行，不用跑几十条正则
static BOOL ZHNAHostWorthChecking(NSString *host) {
    if (host.length == 0) return NO;
    if ([host containsString:@"zhihu.com"]) return YES;

    static NSArray *thirdParty;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        thirdParty = @[ @"pangolin-sdk-toutiao", @"gdt.qq.com", @"mobileservice.cn" ];
    });
    for (NSString *k in thirdParty) {
        if ([host containsString:k]) return YES;
    }
    return NO;
}

ZHNAURLVerdict *ZHNAMatchURL(NSURL *url) {
    if (!url) return nil;

    // 只处理 http(s)
    NSString *scheme = url.scheme.lowercaseString;
    if (![scheme isEqualToString:@"http"] && ![scheme isEqualToString:@"https"]) return nil;

    if (!ZHNAHostWorthChecking(url.host.lowercaseString)) return nil;

    NSString *s = url.absoluteString;
    if (s.length == 0) return nil;

    NSRange full = NSMakeRange(0, s.length);
    for (ZHNACompiledRule *r in ZHNACompiledRules()) {
        if (!ZHNAConfigBool(r.categoryKey)) continue;
        if ([r.regex firstMatchInString:s options:0 range:full]) {
            ZHNAURLVerdict *v = [ZHNAURLVerdict new];
            v.action = r.action;
            v.ruleName = r.name;
            v.category = r.categoryKey;
            return v;
        }
    }
    return nil;
}

#pragma mark - JSON 字段规则

BOOL ZHNAIsAdKey(NSString *key) {
    if (key.length == 0) return NO;
    static NSSet *adKeys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        adKeys = [NSSet setWithArray:@[
            @"ad", @"ads", @"ad_info", @"adinfo", @"ad_list", @"adlist",
            @"adjson", @"ad_json", @"advert", @"adverts", @"advertisement",
            @"ad_config", @"ad_data", @"ad_card", @"ad_extra", @"ad_slot",
            @"market_card", @"commercial", @"commercial_info", @"commercial_card",
            @"activity_banner", @"activity_window", @"vip_tip",
            @"float_window", @"app_float_layer", @"popovers", @"popover",
            @"recommend_queries", @"query_info", @"fringe", @"fringe_info",
            @"promotion", @"promotion_info", @"sponsored",
        ]];
    });
    return [adKeys containsObject:key.lowercaseString];
}

BOOL ZHNATypeStringIsAd(NSString *type) {
    if (type.length == 0) return NO;
    NSString *t = type.lowercaseString;

    // 精确白名单式匹配，尽量不误伤正常内容
    if ([t containsString:@"advert"]) return YES;         // feed_advert / advertisement
    if ([t containsString:@"market_card"]) return YES;    // 商品卡
    if ([t containsString:@"commercial"]) return YES;
    if ([t containsString:@"promotion"]) return YES;
    if ([t containsString:@"sponsor"]) return YES;
    if ([t isEqualToString:@"ad"] || [t isEqualToString:@"ads"]) return YES;
    if ([t hasPrefix:@"ad_"] || [t hasSuffix:@"_ad"]) return YES;
    if ([t hasSuffix:@"_ads"]) return YES;
    if ([t containsString:@"_ad_"]) return YES;

    return NO;
}

BOOL ZHNAIsAdItem(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;

    id type = item[@"type"];
    if ([type isKindOfClass:[NSString class]] && ZHNATypeStringIsAd(type)) return YES;

    id target = item[@"target"];
    if ([target isKindOfClass:[NSDictionary class]]) {
        id tType = ((NSDictionary *)target)[@"type"];
        if ([tType isKindOfClass:[NSString class]] && ZHNATypeStringIsAd(tType)) return YES;
    }

    // 带广告投放数据的条目
    if (item[@"adjson"] || item[@"ad_json"] || item[@"advert"]) return YES;

    id isAd = item[@"is_advertisement"];
    if ([isAd respondsToSelector:@selector(boolValue)] && [isAd boolValue]) return YES;

    id adInfo = item[@"ad_info"];
    if ([adInfo isKindOfClass:[NSDictionary class]] && ((NSDictionary *)adInfo).count > 0) return YES;

    return NO;
}

BOOL ZHNAIsPaidItem(NSDictionary *item) {
    if (![item isKindOfClass:[NSDictionary class]]) return NO;

    id (^answerType)(NSDictionary *) = ^id(NSDictionary *d) {
        id v = d[@"answer_type"];
        return [v isKindOfClass:[NSString class]] ? v : nil;
    };

    NSString *t = answerType(item);
    if (t && [t.lowercaseString containsString:@"paid"]) return YES;

    id target = item[@"target"];
    if ([target isKindOfClass:[NSDictionary class]]) {
        NSString *tt = answerType(target);
        if (tt && [tt.lowercaseString containsString:@"paid"]) return YES;
    }
    return NO;
}

#pragma mark - 类名规则（UI 兜底）

/// 判断类名里是否存在独立的 "Ad" / "Ads" 词元。
/// 关键：必须是大写 A 开头，且后面不能跟小写字母。
/// 这样 ZHAdView / ZHAdsManager 命中，而 Header / Download / Badge / Address /
/// Adapter / Shadow / Thread / Gradient 这些都不会误伤。
static BOOL ZHNAHasAdToken(NSString *name) {
    NSUInteger len = name.length;
    if (len < 2) return NO;
    unichar buf[256];
    NSUInteger n = MIN(len, (NSUInteger)256);
    [name getCharacters:buf range:NSMakeRange(0, n)];

    for (NSUInteger i = 0; i + 1 < n; i++) {
        if (buf[i] != 'A') continue;
        if (buf[i + 1] != 'd' && buf[i + 1] != 'D') continue;

        NSUInteger end = i + 2;
        // 允许 "Ads" / "ADS"
        if (end < n && (buf[end] == 's' || buf[end] == 'S')) end++;

        // 后面必须是：结尾 / 大写字母 / 数字 / 下划线
        if (end >= n) return YES;
        unichar next = buf[end];
        if ((next >= 'A' && next <= 'Z') || (next >= '0' && next <= '9') || next == '_') {
            return YES;
        }
    }
    return NO;
}

BOOL ZHNAClassNameLooksLikeAd(NSString *name) {
    if (name.length == 0) return NO;
    NSString *lower = name.lowercaseString;

    // 明确安全词，先排除
    static NSArray *safe;
    static dispatch_once_t onceSafe;
    dispatch_once(&onceSafe, ^{
        safe = @[ @"adapter", @"address", @"admin", @"advance", @"adjust",
                  @"adopt", @"adaptive", @"adadelta", @"radio", @"gradient",
                  @"shadow", @"thread", @"download", @"upload", @"loader",
                  @"header", @"badge", @"read", @"spread", @"cascade" ];
    });
    // 如果类名去掉安全词后再无广告特征，就放过
    NSString *stripped = lower;
    for (NSString *w in safe) {
        stripped = [stripped stringByReplacingOccurrencesOfString:w withString:@""];
    }

    // 强特征词
    static NSArray *strong;
    static dispatch_once_t onceStrong;
    dispatch_once(&onceStrong, ^{
        strong = @[ @"advert", @"commercialad", @"sponsor", @"promotion",
                    @"marketcard", @"adbanner", @"adcard", @"adcell", @"adview",
                    @"adslot", @"adcontainer", @"admodel", @"adwebview",
                    @"launchad", @"splashad", @"openscreenad", @"adfloat",
                    @"floatad", @"feedad", @"adfeed", @"bottomad", @"topad" ];
    });
    for (NSString *w in strong) {
        if ([stripped containsString:w]) return YES;
    }

    return ZHNAHasAdToken(name);
}

BOOL ZHNAClassNameLooksLikeSplashAd(NSString *name) {
    if (name.length == 0) return NO;
    NSString *lower = name.lowercaseString;

    static NSArray *pairs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        pairs = @[ @"launchad", @"adlaunch", @"splashad", @"adsplash",
                   @"startupad", @"openscreen", @"launchadvert",
                   @"launchscreenad", @"coldstartad" ];
    });
    for (NSString *w in pairs) {
        if ([lower containsString:w]) return YES;
    }

    // "Launch/Splash" + "Advert" 组合
    BOOL isLaunch = [lower containsString:@"launch"] || [lower containsString:@"splash"]
                 || [lower containsString:@"openscreen"];
    if (isLaunch && ([lower containsString:@"advert"] || ZHNAHasAdToken(name))) return YES;

    return NO;
}

#pragma mark - 数据快速预检

BOOL ZHNADataMayContainAd(NSData *data) {
    if (data.length < 8) return NO;
    // 太大的包（>8MB）跳过，避免影响性能
    if (data.length > 8 * 1024 * 1024) return NO;

    const void *bytes = data.bytes;
    NSUInteger len = data.length;

    static const char *markers[] = {
        "advert", "market_card", "ad_info", "adjson", "ad_json", "ad_list",
        "\"ad\"", "\"ads\"", "commercial", "promotion", "sponsor",
        "is_advertisement", "float_window", "activity_banner", "activity_window",
        "vip_tip", "recommend_queries", "query_info", "app_float_layer",
        NULL
    };

    for (int i = 0; markers[i] != NULL; i++) {
        size_t mlen = strlen(markers[i]);
        if (mlen > len) continue;
        if (memmem(bytes, len, markers[i], mlen) != NULL) return YES;
    }

    // 盐选付费内容需要单独探测
    if (ZHNAConfigBool(ZHNAKeyPaid)) {
        if (memmem(bytes, len, "answer_type", 11) != NULL) return YES;
    }

    return NO;
}
