//
//  ZHNASettingsPanel.m
//
//  在知乎界面放一个可拖动的悬浮小圆钮，轻点即呼出设置面板。
//  全部用 runtime 调用 UIKit，不产生 UIKit 链接依赖。
//

#import "ZHNASettingsPanel.h"
#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNASwizzle.h"

#define ZHNA_ALERT_STYLE_ALERT 1   // UIAlertControllerStyleAlert
#define ZHNA_ACTION_DEFAULT 0
#define ZHNA_ACTION_CANCEL 1
#define ZHNA_ACTION_DESTRUCTIVE 2

static BOOL gPanelVisible = NO;
static const void *kZHNALongPressKey = &kZHNALongPressKey;  // 挂在 keyWindow 上：是否已装双指长按

#pragma mark - UIKit runtime 小工具

static id ZHNAMakeAlert(NSString *title, NSString *message) {
    Class cls = ZHNAClass("UIAlertController");
    if (cls == Nil) return nil;
    id (*fn)(id, SEL, id, id, NSInteger) = (id (*)(id, SEL, id, id, NSInteger))objc_msgSend;
    return fn(cls, sel_registerName("alertControllerWithTitle:message:preferredStyle:"),
              title, message, ZHNA_ALERT_STYLE_ALERT);
}

static id ZHNAMakeAction(NSString *title, NSInteger style, void (^handler)(id action)) {
    Class cls = ZHNAClass("UIAlertAction");
    if (cls == Nil) return nil;
    id (*fn)(id, SEL, id, NSInteger, id) = (id (*)(id, SEL, id, NSInteger, id))objc_msgSend;
    return fn(cls, sel_registerName("actionWithTitle:style:handler:"), title, style, handler);
}

static id ZHNATopViewControllerInWindow(id window) {
    id<ZHNAUIShim> w = (id<ZHNAUIShim>)window;
    id vc = w.rootViewController;
    NSInteger guard = 0;
    while (vc != nil && guard++ < 32) {
        id presented = ((id<ZHNAUIShim>)vc).presentedViewController;
        if (presented == nil) break;
        vc = presented;
    }
    return vc;
}

static void ZHNAPresent(id window, id alert) {
    if (alert == nil) return;
    id top = ZHNATopViewControllerInWindow(window);
    if (top == nil) return;
    gPanelVisible = YES;
    [(id<ZHNAUIShim>)top presentViewController:alert animated:YES completion:nil];
}

static void ZHNAShowMainPanel(id window);

/// 稍微延迟一下再弹下一层，等上一层的关闭动画结束
static void ZHNARepresent(id window, void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        block();
    });
}

#pragma mark - 各级面板

static void ZHNAShowToggles(id window) {
    NSString *msg = @"✅ = 已开启，点一下切换\n改完立即生效，个别项目需要重开知乎";
    id alert = ZHNAMakeAlert(@"功能开关", msg);
    if (alert == nil) return;

    for (NSString *key in ZHNAAllKeys()) {
        BOOL on = ZHNAConfigRawBool(key);
        NSString *title = [NSString stringWithFormat:@"%@ %@", on ? @"✅" : @"⬜️", ZHNATitleForKey(key)];
        id action = ZHNAMakeAction(title, ZHNA_ACTION_DEFAULT, ^(id a) {
            ZHNAConfigToggle(key);
            gPanelVisible = NO;
            ZHNARepresent(window, ^{ ZHNAShowToggles(window); });
        });
        if (action) [(id<ZHNAUIShim>)alert addAction:action];
    }

    id back = ZHNAMakeAction(@"‹ 返回", ZHNA_ACTION_CANCEL, ^(id a) {
        gPanelVisible = NO;
        ZHNARepresent(window, ^{ ZHNAShowMainPanel(window); });
    });
    if (back) [(id<ZHNAUIShim>)alert addAction:back];

    ZHNAPresent(window, alert);
}

static void ZHNAShowStats(id window) {
    NSDictionary<NSString *, NSNumber *> *stats = ZHNAStatsSnapshot();
    NSMutableString *msg = [NSMutableString string];

    if (stats.count == 0) {
        [msg appendString:@"本次启动后还没有拦截到任何内容。\n\n刷两下首页再看看。"];
    } else {
        NSArray *keys = [stats keysSortedByValueUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
            return [b compare:a];
        }];
        NSInteger shown = 0;
        for (NSString *k in keys) {
            if (shown++ >= 15) break;
            [msg appendFormat:@"%@  ×%@\n", k, stats[k]];
        }
        [msg appendFormat:@"\n合计 %ld 项", (long)ZHNAStatsTotal()];
    }

    id alert = ZHNAMakeAlert(@"拦截统计", msg);
    if (alert == nil) return;

    id reset = ZHNAMakeAction(@"清零", ZHNA_ACTION_DESTRUCTIVE, ^(id a) {
        ZHNAStatsReset();
        gPanelVisible = NO;
    });
    if (reset) [(id<ZHNAUIShim>)alert addAction:reset];

    id back = ZHNAMakeAction(@"‹ 返回", ZHNA_ACTION_CANCEL, ^(id a) {
        gPanelVisible = NO;
        ZHNARepresent(window, ^{ ZHNAShowMainPanel(window); });
    });
    if (back) [(id<ZHNAUIShim>)alert addAction:back];

    ZHNAPresent(window, alert);
}

static void ZHNAShowMainPanel(id window) {
    NSString *title = [NSString stringWithFormat:@"%@ v%@", ZHNA_DISPLAY_NAME, ZHNA_VERSION];
    NSString *msg = [NSString stringWithFormat:@"总开关：%@\n本次已拦截 %ld 项",
                     ZHNAConfigRawBool(ZHNAKeyMaster) ? @"开启" : @"关闭",
                     (long)ZHNAStatsTotal()];

    id alert = ZHNAMakeAlert(title, msg);
    if (alert == nil) return;

    id toggles = ZHNAMakeAction(@"功能开关…", ZHNA_ACTION_DEFAULT, ^(id a) {
        gPanelVisible = NO;
        ZHNARepresent(window, ^{ ZHNAShowToggles(window); });
    });
    if (toggles) [(id<ZHNAUIShim>)alert addAction:toggles];

    id stats = ZHNAMakeAction(@"拦截统计…", ZHNA_ACTION_DEFAULT, ^(id a) {
        gPanelVisible = NO;
        ZHNARepresent(window, ^{ ZHNAShowStats(window); });
    });
    if (stats) [(id<ZHNAUIShim>)alert addAction:stats];

    id exportLog = ZHNAMakeAction(@"导出诊断日志", ZHNA_ACTION_DEFAULT, ^(id a) {
        gPanelVisible = NO;
        NSString *path = ZHNALogExport();
        ZHNARepresent(window, ^{
            NSString *m = path ? [NSString stringWithFormat:@"已保存到：\n%@", path] : @"保存失败";
            id done = ZHNAMakeAlert(@"导出诊断日志", m);
            id ok = ZHNAMakeAction(@"好", ZHNA_ACTION_CANCEL, ^(id x) { gPanelVisible = NO; });
            if (ok) [(id<ZHNAUIShim>)done addAction:ok];
            ZHNAPresent(window, done);
        });
    });
    if (exportLog) [(id<ZHNAUIShim>)alert addAction:exportLog];

    id reset = ZHNAMakeAction(@"恢复默认设置", ZHNA_ACTION_DESTRUCTIVE, ^(id a) {
        ZHNAConfigResetToDefault();
        gPanelVisible = NO;
    });
    if (reset) [(id<ZHNAUIShim>)alert addAction:reset];

    id close = ZHNAMakeAction(@"关闭", ZHNA_ACTION_CANCEL, ^(id a) {
        gPanelVisible = NO;
    });
    if (close) [(id<ZHNAUIShim>)alert addAction:close];

    ZHNAPresent(window, alert);
}

#pragma mark - 触发方式

static void ZHNAInstallFloatingButton(void);

/// 在知乎界面放一个可拖动的小圆钮，轻点即呼出设置面板。
/// 比手势可靠：不依赖手势识别、不和知乎自身滑动/长按冲突。
void ZHNAInstallSettingsPanel(void) {
    ZHNAInstallFloatingButton();
}

#pragma mark - 对外公开入口

static id ZHNAKeyWindow(void) {
    Class appCls = ZHNAClass("UIApplication");
    if (appCls == Nil) return nil;
    id (*getApp)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id app = getApp(appCls, sel_registerName("sharedApplication"));
    if (app == nil) return nil;

    id (*getObj)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    id keyWindow = getObj(app, sel_registerName("keyWindow"));
    if (keyWindow != nil) return keyWindow;

    // iOS 13+ keyWindow 可能取不到，退回 windows 列表最后一个
    id windows = getObj(app, sel_registerName("windows"));
    if (windows != nil && [windows respondsToSelector:@selector(lastObject)]) {
        return [windows lastObject];
    }
    return nil;
}

void ZHNAOpenSettingsPanel(void) {
    if (gPanelVisible) return;
    id window = ZHNAKeyWindow();
    if (window == nil) {
        ZHNALog(@"呼出设置面板失败：取不到 keyWindow");
        return;
    }
    ZHNAShowMainPanel(window);
}

#pragma mark - 悬浮按钮（可拖动，轻点呼出设置面板）

// 新 SDK（Xcode16 / iOS18）要求 objc_msgSend 必须显式转型后才能带参数调用，
// 否则报 "too many arguments"。这里统一用一组小工具函数，避免逐处强转。
static inline id ZHNASend0(id o, SEL s) { return ((id (*)(id, SEL))objc_msgSend)(o, s); }
static inline id ZHNASend1(id o, SEL s, id a) { return ((id (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline id ZHNASend2(id o, SEL s, id a, id b) { return ((id (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b); }
static inline void ZHNAVoid1(id o, SEL s, id a) { ((void (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline void ZHNAVoid2(id o, SEL s, id a, id b) { ((void (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b); }
static inline void ZHNAVoidB(id o, SEL s, BOOL b) { ((void (*)(id, SEL, BOOL))objc_msgSend)(o, s, b); }
static inline void ZHNAVoidF(id o, SEL s, CGFloat f) { ((void (*)(id, SEL, CGFloat))objc_msgSend)(o, s, f); }
static inline CGPoint ZHNAGetPoint(id o, SEL s) { return ((CGPoint (*)(id, SEL))objc_msgSend)(o, s); }
static inline CGPoint ZHNAGetPoint1(id o, SEL s, id a) { return ((CGPoint (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline CGRect ZHNAGetRect(id o, SEL s) { return ((CGRect (*)(id, SEL))objc_msgSend)(o, s); }
static inline void ZHNASetPoint(id o, SEL s, CGPoint p) { ((void (*)(id, SEL, CGPoint))objc_msgSend)(o, s, p); }
static inline void ZHNASetRect(id o, SEL s, CGRect r) { ((void (*)(id, SEL, CGRect))objc_msgSend)(o, s, r); }
static inline NSInteger ZHNAInt0(id o, SEL s) { return ((NSInteger (*)(id, SEL))objc_msgSend)(o, s); }
static inline double ZHNADouble0(id o, SEL s) { return ((double (*)(id, SEL))objc_msgSend)(o, s); }

static BOOL gFloatingInstalled = NO;
static BOOL gFloatingRetryScheduled = NO;
static CGPoint gBtnStartCenter;

static id ZHNACString(const char *s) {
    Class cls = ZHNAClass("NSString");
    if (cls == Nil) return nil;
    return ((id (*)(id, SEL, const char *))objc_msgSend)(cls,
            sel_registerName("stringWithUTF8String:"), s);
}

static id ZHNAColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    Class cls = ZHNAClass("UIColor");
    if (cls == Nil) return nil;
    return ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        cls, sel_registerName("colorWithRed:green:blue:alpha:"), r, g, b, a);
}

static void ZHNASaveButtonCenter(CGPoint c) {
    Class cls = ZHNAClass("NSUserDefaults");
    if (cls == Nil) return;
    id ud = ZHNASend0(cls, sel_registerName("standardUserDefaults"));
    if (ud == nil) return;
    id str = ((id (*)(id, SEL, id, double, double))objc_msgSend)(
        ZHNAClass("NSString"), sel_registerName("stringWithFormat:"),
        ZHNACString("%f,%f"), (double)c.x, (double)c.y);
    ZHNAVoid2(ud, sel_registerName("setObject:forKey:"), str, ZHNACString("ZHNAFloatBtnCenter"));
    ZHNASend0(ud, sel_registerName("synchronize"));
}

static CGPoint ZHNALoadButtonCenter(void) {
    Class cls = ZHNAClass("NSUserDefaults");
    if (cls == Nil) return (CGPoint){0, 0};
    id ud = ZHNASend0(cls, sel_registerName("standardUserDefaults"));
    if (ud == nil) return (CGPoint){0, 0};
    id str = ZHNASend1(ud, sel_registerName("objectForKey:"), ZHNACString("ZHNAFloatBtnCenter"));
    if (str == nil) return (CGPoint){0, 0};
    id parts = ZHNASend1(str, sel_registerName("componentsSeparatedByString:"), ZHNACString(","));
    if (ZHNAInt0(parts, sel_registerName("count")) != 2) return (CGPoint){0, 0};
    id xstr = ZHNASend1(parts, sel_registerName("objectAtIndex:"), 0);
    id ystr = ZHNASend1(parts, sel_registerName("objectAtIndex:"), 1);
    CGFloat x = (CGFloat)ZHNADouble0(xstr, sel_registerName("doubleValue"));
    CGFloat y = (CGFloat)ZHNADouble0(ystr, sel_registerName("doubleValue"));
    return (CGPoint){x, y};
}

static void zhna_onPan(id self, SEL _cmd, id gesture);

static id ZHNAFloatingTarget(void) {
    static id target = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = ZHNAClass("NSObject");
        if (base == Nil) return;
        Class cls = objc_allocateClassPair(base, "ZHNAFloatTarget", 0);
        class_addMethod(cls, sel_registerName("zhna_onPan:"),
                        (IMP)zhna_onPan, "v@:@");
        objc_registerClassPair(cls);
        target = ZHNASend0(cls, sel_registerName("new"));
    });
    return target;
}

static void zhna_onPan(id self, SEL _cmd, id gesture) {
    NSInteger state = ZHNAInt0(gesture, sel_registerName("state"));
    id btn = ZHNASend0(gesture, sel_registerName("view"));
    if (btn == nil) return;
    id window = ZHNAKeyWindow();
    if (window == nil) window = ZHNASend0(btn, sel_registerName("superview"));
    if (window == nil) return;

    if (state == 1) {
        gBtnStartCenter = ZHNAGetPoint(btn, sel_registerName("center"));
    } else if (state == 2) {
        CGPoint t = ZHNAGetPoint1(gesture, sel_registerName("translationInView:"), window);
        CGPoint nc = (CGPoint){ gBtnStartCenter.x + t.x, gBtnStartCenter.y + t.y };
        CGRect b = ZHNAGetRect(window, sel_registerName("bounds"));
        CGFloat half = 22;
        if (nc.x < half) nc.x = half;
        if (nc.x > b.size.width - half) nc.x = b.size.width - half;
        if (nc.y < half) nc.y = half;
        if (nc.y > b.size.height - half) nc.y = b.size.height - half;
        ZHNASetPoint(btn, sel_registerName("setCenter:"), nc);
        ZHNAVoid1(window, sel_registerName("bringSubviewToFront:"), btn);
    } else if (state == 3 || state == 4) {
        CGPoint t = ZHNAGetPoint1(gesture, sel_registerName("translationInView:"), window);
        if (t.x * t.x + t.y * t.y < 100) ZHNAOpenSettingsPanel();
        CGPoint c = ZHNAGetPoint(btn, sel_registerName("center"));
        ZHNASaveButtonCenter(c);
    }
}

static void ZHNAInstallFloatingButton(void) {
    if (gFloatingInstalled) return;
    id window = ZHNAKeyWindow();
    if (window == nil) {
        if (!gFloatingRetryScheduled) {
            gFloatingRetryScheduled = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                gFloatingRetryScheduled = NO;
                ZHNAInstallFloatingButton();
            });
        }
        return;
    }
    @try {
        Class btnCls = ZHNAClass("UIButton");
        if (btnCls == Nil) return;
        id btn = ZHNASend0(btnCls, sel_registerName("new"));
        if (btn == nil) return;

        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(btn, sel_registerName("setTitle:forState:"), ZHNACString("去"), 0);
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(btn, sel_registerName("setTitleColor:forState:"), ZHNAColor(1, 1, 1, 1), 0);
        ZHNAVoid1(btn, sel_registerName("setBackgroundColor:"), ZHNAColor(0.08, 0.08, 0.08, 0.55));
        ZHNAVoidB(btn, sel_registerName("setUserInteractionEnabled:"), (BOOL)YES);
        ZHNAVoidB(btn, sel_registerName("setClipsToBounds:"), (BOOL)YES);

        CGFloat size = 44;
        ZHNASetRect(btn, sel_registerName("setFrame:"), (CGRect){{0, 0}, {size, size}});
        id layer = ZHNASend0(btn, sel_registerName("layer"));
        ZHNAVoidF(layer, sel_registerName("setCornerRadius:"), (CGFloat)(size / 2));
        ZHNAVoidB(layer, sel_registerName("setMasksToBounds:"), (BOOL)YES);

        CGPoint c = ZHNALoadButtonCenter();
        if (c.x <= 0 || c.y <= 0) {
            CGRect b = ZHNAGetRect(window, sel_registerName("bounds"));
            c = (CGPoint){ b.size.width - size / 2 - 8, b.size.height / 2 };
        }
        ZHNASetPoint(btn, sel_registerName("setCenter:"), c);

        Class panCls = ZHNAClass("UIPanGestureRecognizer");
        id pan = ZHNASend0(panCls, sel_registerName("new"));
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(pan, sel_registerName("addTarget:action:"),
                  ZHNAFloatingTarget(), sel_registerName("zhna_onPan:"));
        ZHNAVoid1(btn, sel_registerName("addGestureRecognizer:"), pan);

        ZHNAVoid1(window, sel_registerName("addSubview:"), btn);
        ZHNAVoid1(window, sel_registerName("bringSubviewToFront:"), btn);

        gFloatingInstalled = YES;
        ZHNALog(@"悬浮按钮已安装（轻点呼出设置，可拖动，位置已记忆）");
    } @catch (NSException *e) {
        ZHNALog(@"悬浮按钮安装失败: %@", e);
    }
}
