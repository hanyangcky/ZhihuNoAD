//
//  ZHNAUIGuard.m
//
//  这是"保险丝"，不是主力。主力是网络层。
//  这一层只做两件事：
//   1. 名字明显是广告的视图，加到界面上时直接隐藏
//   2. 名字明显是开屏广告的控制器，出现时直接关掉
//  为了不误伤，规则做得非常保守，并且跳过所有系统类。
//

#import "ZHNAUIGuard.h"
#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNARules.h"
#import "ZHNASwizzle.h"

static const void *kZHNAAdVerdictKey = &kZHNAAdVerdictKey;
static const void *kZHNASplashVerdictKey = &kZHNASplashVerdictKey;

/// 系统类前缀，一律跳过，避免把 App 自己的界面搞坏
static BOOL ZHNAIsSystemClassName(NSString *name) {
    static NSArray *prefixes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefixes = @[ @"UI", @"_UI", @"NS", @"_NS", @"CA", @"_CA", @"WK", @"_WK",
                      @"AV", @"SK", @"PK", @"MK", @"QL", @"TUI", @"RTI", @"SwiftUI" ];
    });
    for (NSString *p in prefixes) {
        if ([name hasPrefix:p]) return YES;
    }
    return NO;
}

/// 带缓存的类名判定（判定结果挂在 Class 对象上，只算一次）
static BOOL ZHNAClassIsAdCached(Class cls) {
    if (cls == Nil) return NO;
    id cached = objc_getAssociatedObject((id)cls, kZHNAAdVerdictKey);
    if (cached != nil) return [cached boolValue];

    NSString *name = NSStringFromClass(cls);
    BOOL isAd = NO;
    if (!ZHNAIsSystemClassName(name)) {
        isAd = ZHNAClassNameLooksLikeAd(name);
    }
    objc_setAssociatedObject((id)cls, kZHNAAdVerdictKey, @(isAd), OBJC_ASSOCIATION_RETAIN);

    if (isAd) {
        ZHNALog(@"识别到广告视图类: %@", name);
    }
    return isAd;
}

static BOOL ZHNAClassIsSplashCached(Class cls) {
    if (cls == Nil) return NO;
    id cached = objc_getAssociatedObject((id)cls, kZHNASplashVerdictKey);
    if (cached != nil) return [cached boolValue];

    NSString *name = NSStringFromClass(cls);
    BOOL isSplash = NO;
    if (!ZHNAIsSystemClassName(name)) {
        isSplash = ZHNAClassNameLooksLikeSplashAd(name);
    }
    objc_setAssociatedObject((id)cls, kZHNASplashVerdictKey, @(isSplash), OBJC_ASSOCIATION_RETAIN);

    if (isSplash) {
        ZHNALog(@"识别到开屏广告控制器: %@", name);
    }
    return isSplash;
}

static void ZHNAHideAdView(id view) {
    id<ZHNAUIShim> v = (id<ZHNAUIShim>)view;
    @try {
        v.hidden = YES;
        v.alpha = 0.0;
        v.userInteractionEnabled = NO;
    } @catch (__unused NSException *e) {
        // 某些视图可能没有这些属性，忽略即可
    }
}

#pragma mark - UIView 钩子

static void (*orig_didMoveToWindow)(id, SEL) = NULL;
static void new_didMoveToWindow(id self, SEL _cmd) {
    if (orig_didMoveToWindow) orig_didMoveToWindow(self, _cmd);
    if (!ZHNAConfigBool(ZHNAKeyUIGuard)) return;
    if (((id<ZHNAUIShim>)self).window == nil) return;

    if (ZHNAClassIsAdCached(object_getClass(self))) {
        ZHNAHideAdView(self);
        ZHNACount(@"隐藏·广告视图");
        if (ZHNAConfigBool(ZHNAKeyDebug)) {
            ZHNALog(@"隐藏广告视图: %@", NSStringFromClass(object_getClass(self)));
        }
    }
}

static void (*orig_didMoveToSuperview)(id, SEL) = NULL;
static void new_didMoveToSuperview(id self, SEL _cmd) {
    if (orig_didMoveToSuperview) orig_didMoveToSuperview(self, _cmd);
    if (!ZHNAConfigBool(ZHNAKeyUIGuard)) return;
    if (((id<ZHNAUIShim>)self).superview == nil) return;

    if (ZHNAClassIsAdCached(object_getClass(self))) {
        ZHNAHideAdView(self);
    }
}

#pragma mark - UIViewController 钩子（开屏广告）

static void (*orig_viewDidAppear)(id, SEL, BOOL) = NULL;
static void new_viewDidAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_viewDidAppear) orig_viewDidAppear(self, _cmd, animated);
    if (!ZHNAConfigBool(ZHNAKeySplash)) return;

    Class cls = object_getClass(self);
    if (!ZHNAClassIsSplashCached(cls)) return;

    ZHNACount(@"跳过·开屏广告");
    ZHNALog(@"跳过开屏广告: %@", NSStringFromClass(cls));

    id<ZHNAUIShim> vc = (id<ZHNAUIShim>)self;
    @try {
        [vc dismissViewControllerAnimated:NO completion:nil];
        id view = vc.view;
        if (view != nil) {
            [(id<ZHNAUIShim>)view removeFromSuperview];
        }
        if (vc.parentViewController != nil) {
            [vc removeFromParentViewController];
        }
    } @catch (__unused NSException *e) {
    }
}

#pragma mark - 安装

void ZHNAInstallUIGuard(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ZHNASwizzleInstanceMethodNamed("UIView", "didMoveToWindow",
                                       (IMP)new_didMoveToWindow,
                                       (IMP *)&orig_didMoveToWindow);
        ZHNASwizzleInstanceMethodNamed("UIView", "didMoveToSuperview",
                                       (IMP)new_didMoveToSuperview,
                                       (IMP *)&orig_didMoveToSuperview);
        ZHNASwizzleInstanceMethodNamed("UIViewController", "viewDidAppear:",
                                       (IMP)new_viewDidAppear,
                                       (IMP *)&orig_viewDidAppear);
        ZHNALog(@"界面兜底已安装");
    });
}
