//
//  ZHNASettingsPanel.m
//
//  在知乎里"摇一摇手机"即可呼出设置面板。
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

static void ZHNAInstallLongPress(void);

/// 用双指长按呼出设置面板（替代摇一摇，误触概率低很多）
void ZHNAInstallSettingsPanel(void) {
    ZHNAInstallLongPress();
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

#pragma mark - 双指长按实现（替换摇一摇）

// 仅响应手势开始那一刻（state == 1 == UIGestureRecognizerStateBegan），避免长按过程中重复触发
static void zhna_onLongPress(id self, SEL _cmd, id gesture) {
    NSInteger state = ((NSInteger (*)(id, SEL))objc_msgSend)(gesture, sel_registerName("state"));
    if (state != 1) return;
    ZHNAOpenSettingsPanel();
}

// 手势回调的目标对象：运行时动态建一个 NSObject 子类，避免链接 UIKit / 在头文件里写死方法
static id ZHNALongPressTarget(void) {
    static id target = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = ZHNAClass("NSObject");
        if (base == Nil) return;
        Class cls = objc_allocateClassPair(base, "ZHNALongPressTarget", 0);
        class_addMethod(cls, sel_registerName("zhna_onLongPress:"),
                        (IMP)zhna_onLongPress, "v@:@");
        objc_registerClassPair(cls);
        target = ((id (*)(id, SEL))objc_msgSend)(cls, sel_registerName("new"));
    });
    return target;
}

static void ZHNAInstallLongPress(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        @try {
            id window = ZHNAKeyWindow();
            if (window == nil) { ZHNALog(@"双指长按：取不到 keyWindow，跳过"); return; }
            if (objc_getAssociatedObject(window, kZHNALongPressKey)) return;  // 已装过，幂等

            id recogCls = ZHNAClass("UILongPressGestureRecognizer");
            if (recogCls == Nil) return;
            id recog = ((id (*)(id, SEL))objc_msgSend)(recogCls, sel_registerName("alloc"));
            recog = ((id (*)(id, SEL))objc_msgSend)(recog, sel_registerName("init"));
            if (recog == nil) return;

            // 必须两个手指同时长按，把单指滑动/点按的误触概率压到最低
            ((void (*)(id, SEL, NSInteger))objc_msgSend)(recog,
                sel_registerName("setNumberOfTouchesRequired:"), 2);
            // minimumPressDuration 默认 0.5s，足以区分正常操作

            id target = ZHNALongPressTarget();
            ((void (*)(id, SEL, id, SEL))objc_msgSend)(recog,
                sel_registerName("addTarget:action:"), target,
                sel_registerName("zhna_onLongPress:"));
            ((void (*)(id, SEL, id))objc_msgSend)(window,
                sel_registerName("addGestureRecognizer:"), recog);

            objc_setAssociatedObject(window, kZHNALongPressKey, @"1",
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            ZHNALog(@"设置面板已安装（双指长按呼出，替换摇一摇）");
        } @catch (NSException *e) {
            ZHNALog(@"双指长按安装失败: %@", e);
        }
    });
}
