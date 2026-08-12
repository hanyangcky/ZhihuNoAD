//
//  ZHNAConfig.m
//

#import "ZHNAConfig.h"

NSString *const ZHNAKeyMaster   = @"ZHNA_master";
NSString *const ZHNAKeySplash   = @"ZHNA_splash";
NSString *const ZHNAKeyFeed     = @"ZHNA_feed";
NSString *const ZHNAKeyDetail   = @"ZHNA_detail";
NSString *const ZHNAKeySearch   = @"ZHNA_search";
NSString *const ZHNAKeyPopup    = @"ZHNA_popup";
NSString *const ZHNAKeyPaid     = @"ZHNA_paid";
NSString *const ZHNAKeyTracking = @"ZHNA_tracking";
NSString *const ZHNAKeyUIGuard  = @"ZHNA_uiguard";
NSString *const ZHNAKeyDebug    = @"ZHNA_debug";

NSArray<NSString *> *ZHNAAllKeys(void) {
    static NSArray *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[ ZHNAKeyMaster, ZHNAKeySplash, ZHNAKeyFeed, ZHNAKeyDetail,
                  ZHNAKeySearch, ZHNAKeyPopup, ZHNAKeyPaid, ZHNAKeyTracking,
                  ZHNAKeyUIGuard, ZHNAKeyDebug ];
    });
    return keys;
}

static NSDictionary<NSString *, NSNumber *> *ZHNADefaults(void) {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{
            ZHNAKeyMaster:   @YES,
            ZHNAKeySplash:   @YES,
            ZHNAKeyFeed:     @YES,
            ZHNAKeyDetail:   @YES,
            ZHNAKeySearch:   @YES,
            ZHNAKeyPopup:    @YES,
            ZHNAKeyPaid:     @YES,
            ZHNAKeyTracking: @YES,
            ZHNAKeyUIGuard:  @YES,
            ZHNAKeyDebug:    @NO,
        };
    });
    return d;
}

NSString *ZHNATitleForKey(NSString *key) {
    static NSDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{
            ZHNAKeyMaster:   @"总开关",
            ZHNAKeySplash:   @"开屏广告",
            ZHNAKeyFeed:     @"信息流广告",
            ZHNAKeyDetail:   @"回答页推广卡片",
            ZHNAKeySearch:   @"搜索页推广",
            ZHNAKeyPopup:    @"弹窗 / 浮层 / 角标",
            ZHNAKeyPaid:     @"盐选故事推广",
            ZHNAKeyTracking: @"埋点与广告SDK",
            ZHNAKeyUIGuard:  @"界面兜底清理",
            ZHNAKeyDebug:    @"诊断模式",
        };
    });
    return m[key] ?: key;
}

NSString *ZHNADetailForKey(NSString *key) {
    static NSDictionary *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = @{
            ZHNAKeyMaster:   @"关掉后插件完全不工作，等于没装",
            ZHNAKeySplash:   @"启动时的全屏广告、倒计时跳过",
            ZHNAKeyFeed:     @"首页推荐、热榜、想法里夹带的推广条目",
            ZHNAKeyDetail:   @"回答底部卡片、评论区顶部推广、相关阅读",
            ZHNAKeySearch:   @"搜索框热搜词、预置推广词、相关搜索",
            ZHNAKeyPopup:    @"首页浮动图标、活动弹窗、会员引导",
            ZHNAKeyPaid:     @"问题页里的盐选付费故事引流回答",
            ZHNAKeyTracking: @"崩溃上报、行为埋点、第三方广告SDK域名",
            ZHNAKeyUIGuard:  @"漏网的广告视图按类名隐藏（保险措施）",
            ZHNAKeyDebug:    @"记录详细日志，用于排查问题，平时请关闭",
        };
    });
    return m[key] ?: @"";
}

static NSUserDefaults *ZHNADefaultsStore(void) {
    return [NSUserDefaults standardUserDefaults];
}

BOOL ZHNAConfigRawBool(NSString *key) {
    if (key.length == 0) return NO;
    id v = [ZHNADefaultsStore() objectForKey:key];
    if (v == nil) {
        return ZHNADefaults()[key].boolValue;
    }
    return [v boolValue];
}

BOOL ZHNAConfigBool(NSString *key) {
    if ([key isEqualToString:ZHNAKeyDebug] || [key isEqualToString:ZHNAKeyMaster]) {
        return ZHNAConfigRawBool(key);
    }
    if (!ZHNAConfigRawBool(ZHNAKeyMaster)) return NO;
    return ZHNAConfigRawBool(key);
}

void ZHNAConfigSetBool(NSString *key, BOOL value) {
    if (key.length == 0) return;
    [ZHNADefaultsStore() setBool:value forKey:key];
    [ZHNADefaultsStore() synchronize];
}

void ZHNAConfigToggle(NSString *key) {
    ZHNAConfigSetBool(key, !ZHNAConfigRawBool(key));
}

void ZHNAConfigResetToDefault(void) {
    for (NSString *k in ZHNAAllKeys()) {
        [ZHNADefaultsStore() removeObjectForKey:k];
    }
    [ZHNADefaultsStore() synchronize];
}
