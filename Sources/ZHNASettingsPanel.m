//
//  ZHNASettingsPanel.m
//
//  自定义圆角卡片式设置面板 + 可拖动悬浮按钮 + 摇一摇广告拦截。
//  全部用 runtime 调用 UIKit，不产生 UIKit 链接依赖。
//  视觉参考：AntForestTrollFools（分组圆角卡片、图标+开关行、浅灰底色）。
//

#import "ZHNASettingsPanel.h"
#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNASwizzle.h"

#pragma mark - 常量

static const CGFloat kCardW        = 340.0;
static const CGFloat kCardRadius   = 16.0;
static const CGFloat kRowH         = 52.0;
static const CGFloat kPadH         = 20.0;
static const CGFloat kPadV         = 12.0;
static const CGFloat kDividerH     = 0.5;

// UIControlEvent 枚举值（不能引 UIKit 头文件）
static const NSUInteger kUIControlEventTouchUpInside = (1 << 6);   // 64
static const NSUInteger kUIControlEventValueChanged   = (1 << 12); // 4096

// UIEventType / UIEventSubtype
static const NSInteger kUIEventTypeMotion     = 1;
static const NSInteger kUISubtypeMotionShake  = 1;

#pragma mark - 全局状态

static BOOL gPanelVisible       = NO;
static id   gOverlayView        = nil;    // 半透明遮罩
static id   gCardView           = nil;    // 白色卡片容器
static id   gToggleScrollView   = nil;    // 开关区域滚动视图

// 悬浮按钮状态
static BOOL gFloatingInstalled     = NO;
static BOOL gFloatingRetryScheduled = NO;
static BOOL gFloatObsInstalled     = NO;
static CGPoint gBtnStartCenter;
static id   gFloatButton        = nil;   // 悬浮钮专属浮层窗口（独立 windowLevel，永不被知乎界面覆盖/替换）

// Associated Object keys
static const void *kZHNAConfigKeyAssoc = &kZHNAConfigKeyAssoc;
static const void *kZHNABlockAssoc     = &kZHNABlockAssoc;
static const void *kZHNAOverlayTapAssoc = &kZHNAOverlayTapAssoc;

#pragma mark - UIKit runtime 小工具（显式转型封装）

static inline id   ZS0(id o, SEL s) { return ((id   (*)(id, SEL))objc_msgSend)(o, s); }
static inline id   ZS1(id o, SEL s, id a) { return ((id   (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline id   ZS2(id o, SEL s, id a, id b) { return ((id   (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b); }
static inline void ZV1(id o, SEL s, id a) { ((void (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline void ZV2(id o, SEL s, id a, id b) { ((void (*)(id, SEL, id, id))objc_msgSend)(o, s, a, b); }
static inline void ZVB(id o, SEL s, BOOL b) { ((void (*)(id, SEL, BOOL))objc_msgSend)(o, s, b); }
static inline void ZVF(id o, SEL s, CGFloat f) { ((void (*)(id, SEL, CGFloat))objc_msgSend)(o, s, f); }
static inline void ZVI(id o, SEL s, NSInteger i) { ((void (*)(id, SEL, NSInteger))objc_msgSend)(o, s, i); }
static inline void ZVP(id o, SEL s, CGPoint p) { ((void (*)(id, SEL, CGPoint))objc_msgSend)(o, s, p); }
static inline void ZVR(id o, SEL s, CGRect r) { ((void (*)(id, SEL, CGRect))objc_msgSend)(o, s, r); }
static inline id   ZSI(id o, SEL s, CGRect r) { return ((id (*)(id, SEL, CGRect))objc_msgSend)(o, s, r); }
static inline CGPoint ZGP(id o, SEL s) { return ((CGPoint (*)(id, SEL))objc_msgSend)(o, s); }
static inline CGPoint ZGP1(id o, SEL s, id a) { return ((CGPoint (*)(id, SEL, id))objc_msgSend)(o, s, a); }
static inline CGRect ZGR(id o, SEL s) { return ((CGRect (*)(id, SEL))objc_msgSend)(o, s); }
static inline NSInteger ZGI(id o, SEL s) { return ((NSInteger (*)(id, SEL))objc_msgSend)(o, s); }
static inline double  ZGD(id o, SEL s) { return ((double  (*)(id, SEL))objc_msgSend)(o, s); }
static inline BOOL    ZGB(id o, SEL s) { return ((BOOL    (*)(id, SEL))objc_msgSend)(o, s); }

static id ZStr(const char *s) {
    Class c = ZHNAClass("NSString"); if (c == Nil) return nil;
    return ((id (*)(id, SEL, const char *))objc_msgSend)(c, sel_registerName("stringWithUTF8String:"), s);
}

static id ZColor(CGFloat r, CGFloat g, CGFloat b, CGFloat a) {
    Class c = ZHNAClass("UIColor"); if (c == Nil) return nil;
    return ((id (*)(id, SEL, CGFloat, CGFloat, CGFloat, CGFloat))objc_msgSend)(
        c, sel_registerName("colorWithRed:green:blue:alpha:"), r, g, b, a);
}

static id ZFont(CGFloat size, BOOL bold) {
    Class c = ZHNAClass("UIFont"); if (c == Nil) return nil;
    if (bold)
        return ((id (*)(id, SEL, CGFloat))objc_msgSend)(c, sel_registerName("boldSystemFontOfSize:"), size);
    else
        return ((id (*)(id, SEL, CGFloat))objc_msgSend)(c, sel_registerName("systemFontOfSize:"), size);
}

/// 安全取 keyWindow（兼容 iOS 13+）
static id ZHNAKeyWindow(void) {
    Class appCls = ZHNAClass("UIApplication");
    if (appCls == Nil) return nil;
    id app = ZS0(appCls, sel_registerName("sharedApplication"));
    if (app == nil) return nil;
    id kw = ZS0(app, sel_registerName("keyWindow"));
    if (kw != nil) return kw;
    id wins = ZS0(app, sel_registerName("windows"));
    if (wins != nil && [wins respondsToSelector:@selector(lastObject)])
        return [wins lastObject];
    return nil;
}

static void zhna_dismissPanel(void);
static void ZHNAShowToast(id window, NSString *msg);
static void ZHNAShowStatsPanel(id window);
static void ZHNAInstallFloatingButton(void);
static void ZHNARepinFloatButton(void);
static void zhna_onWindowChange(id self, SEL _cmd, id note);

#pragma mark - 摇一摇广告拦截（MotionGuard）

static void (*gOrigSendEvent)(id, SEL, id);

static void zhna_sendEvent(id self, SEL _cmd, id event) {
    NSInteger type = ZGI(event, sel_registerName("type"));
    if (type == kUIEventTypeMotion) {
        NSInteger subtype = ZGI(event, sel_registerName("subtype"));
        if (subtype == kUISubtypeMotionShake) {
            return;  // 吞掉摇一摇事件 → 知乎无法触发"摇一摇跳转广告"
        }
    }
    gOrigSendEvent(self, _cmd, event);
}

static void ZHNAInstallMotionGuard(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class cls = ZHNAClass("UIApplication");
        if (cls == Nil) return;
        Method m = class_getInstanceMethod(cls, sel_registerName("sendEvent:"));
        if (!m) return;
        gOrigSendEvent = (void(*)(id, SEL, id))method_getImplementation(m);
        method_setImplementation(m, (IMP)zhna_sendEvent);
        ZHNALog(@"摇一摇事件拦截已安装（知乎原生摇一摇跳广告将被屏蔽）");
    });
}

#pragma mark - 动态 Handler 类（Switch + Button 共用）

static id gUICmdTarget = nil;  // 统一的 target 对象

/// Switch value changed → 更新对应 config key
static void zhna_onSwitchChanged(id self, SEL _cmd, id sw) {
    NSString *key = objc_getAssociatedObject(sw, kZHNAConfigKeyAssoc);
    if (key) {
        BOOL on = ZGB(sw, sel_registerName("isOn"));
        ZHNAConfigSetBool(key, on);
    }
}

/// Button tap → 执行关联的 block
static void zhna_onButtonTap(id self, SEL _cmd, id btn) {
    typedef void (^Block)(void);
    Block blk = objc_getAssociatedObject(btn, kZHNABlockAssoc);
    if (blk) blk();
}

/// Overlay background tap → 关闭面板
static void zhna_onOverlayTap(id self, SEL _cmd, id gest) {
    zhna_dismissPanel();
}

static void ZHNAEnsureCmdTarget(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class base = ZHNAClass("NSObject");
        if (base == Nil) return;
        Class cls = objc_allocateClassPair(base, "ZHNAUICmdTarget", 0);
        class_addMethod(cls, sel_registerName("zhna_onSwitchChanged:"),
                        (IMP)zhna_onSwitchChanged, "v@:@");
        class_addMethod(cls, sel_registerName("zhna_onButtonTap:"),
                        (IMP)zhna_onButtonTap, "v@:@");
        class_addMethod(cls, sel_registerName("zhna_onOverlayTap:"),
                        (IMP)zhna_onOverlayTap, "v@:@");
        objc_registerClassPair(cls);
        gUICmdTarget = ZS0(cls, sel_registerName("new"));
    });
}

#pragma mark - 面板关闭

static void zhna_dismissPanel(void) {
    if (!gPanelVisible) return;
    @try {
        // 简单的淡出动画
        id animCls = ZHNAClass("UIView");
        if (animCls != Nil && gCardView != nil) {
            typedef void (^AnimBlock)(void);
            AnimBlock fade = ^{ ZVF(gOverlayView, sel_registerName("setAlpha:"), 0); };
            AnimBlock done = ^{
                [gOverlayView removeFromSuperview];
                gOverlayView = nil;
                gCardView = nil;
                gToggleScrollView = nil;
                if (gFloatButton) ZVB(gFloatButton, sel_registerName("setHidden:"), NO);
                gPanelVisible = NO;
            };
            // UIView animateWithDuration:animations:completion:
            ((void (*)(id, SEL, double, id, id))objc_msgSend)(
                animCls, sel_registerName("animateWithDuration:animations:completion:"),
                0.20, fade, done);
        } else {
            [gOverlayView removeFromSuperview];
            gOverlayView = nil; gCardView = nil; gToggleScrollView = nil;
            if (gFloatButton) ZVB(gFloatButton, sel_registerName("setHidden:"), NO);
            gPanelVisible = NO;
        }
    } @catch (NSException *e) {
        ZHNALog(@"面板关闭异常: %@", e);
        gPanelVisible = NO;
    }
}

#pragma mark - UI 组件工厂

static id ZHNAMakeLabel(NSString *text, CGFloat fontSize, BOOL bold, id color) {
    Class cls = ZHNAClass("UILabel"); if (cls == Nil) return nil;
    id lbl = ZS0(cls, sel_registerName("new")); if (lbl == nil) return nil;
    ZV1(lbl, sel_registerName("setText:"), text);
    if (color) ZV1(lbl, sel_registerName("setTextColor:"), color);
    id font = ZFont(fontSize, bold);
    if (font) ZV1(lbl, sel_registerName("setFont:"), font);
    return lbl;
}

static id ZHNAMakeSwitch(NSString *configKey, BOOL isOn) {
    Class cls = ZHNAClass("UISwitch"); if (cls == Nil) return nil;
    id sw = ZS0(cls, sel_registerName("new")); if (sw == nil) return nil;
    // setOn:animated:
    ((void (*)(id, SEL, BOOL, BOOL))objc_msgSend)(sw, sel_registerName("setOn:animated:"), isOn, NO);
    // 关联 config key
    objc_setAssociatedObject(sw, kZHNAConfigKeyAssoc, configKey,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // addTarget
    ZHNAEnsureCmdTarget();
    ((void (*)(id, SEL, id, SEL, NSUInteger))objc_msgSend)(
        sw, sel_registerName("addTarget:action:forControlEvents:"),
        gUICmdTarget, sel_registerName("zhna_onSwitchChanged:"),
        kUIControlEventValueChanged);
    return sw;
}

static id ZHNAMakeButton(NSString *title, id bgColor, id titleColor,
                          CGFloat fontSize, void (^block)(void)) {
    Class cls = ZHNAClass("UIButton"); if (cls == Nil) return nil;
    id btn = ZS0(cls, sel_registerName("new")); if (btn == nil) return nil;
    // setTitle:forState:
    ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
        btn, sel_registerName("setTitle:forState:"), title, 0);
    // setTitleColor:forState:
    ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(
        btn, sel_registerName("setTitleColor:forState:"), titleColor, 0);
    // setBackgroundColor:
    if (bgColor) ZV1(btn, sel_registerName("setBackgroundColor:"), bgColor);
    // titleLabel font
    id titleLbl = ZS1(btn, sel_registerName("titleLabel"), nil);
    if (titleLbl) {
        id f = ZFont(fontSize, NO);
        if (f) ZV1(titleLbl, sel_registerName("setFont:"), f);
    }
    // cornerRadius
    id layer = ZS0(btn, sel_registerName("layer"));
    if (layer) ZVF(layer, sel_registerName("setCornerRadius:"), 8.0);
    // clipsToBounds
    ZVB(btn, sel_registerName("setClipsToBounds:"), YES);
    // block
    if (block) {
        objc_setAssociatedObject(btn, kZHNABlockAssoc, block,
                                 OBJC_ASSOCIATION_COPY_NONATOMIC);
        ZHNAEnsureCmdTarget();
        ((void (*)(id, SEL, id, SEL, NSUInteger))objc_msgSend)(
            btn, sel_registerName("addTarget:action:forControlEvents:"),
            gUICmdTarget, sel_registerName("zhna_onButtonTap:"),
            kUIControlEventTouchUpInside);
    }
    return btn;
}

static id ZHNAMakeDivider(void) {
    Class cls = ZHNAClass("UIView"); if (cls == Nil) return nil;
    id v = ZS0(cls, sel_registerName("new")); if (v == nil) return nil;
    ZVR(v, sel_registerName("setFrame:"), (CGRect){{0, 0}, {kCardW - kPadH * 2, kDividerH}});
    ZV1(v, sel_registerName("setBackgroundColor:"), ZColor(0.85, 0.85, 0.85, 1));
    return v;
}

static id ZHNAMakeIconLabel(NSString *emoji) {
    return ZHNAMakeLabel(emoji, 22, NO, nil);
}

#pragma mark - 面板构建

/// 各开关对应的 emoji 图标（与 AntForest 风格一致：左侧彩色图标）
static NSString *ZHNAEmojiForKey(NSString *key) {
    if ([key isEqualToString:ZHNAKeyMaster])   return @"\U0001f512";  // 🔒
    if ([key isEqualToString:ZHNAKeySplash])   return @"\U0001f3ac";  // 🎬
    if ([key isEqualToString:ZHNAKeyFeed])     return @"\U0001f4f0";  // 📰
    if ([key isEqualToString:ZHNAKeyDetail])   return @"\U0001f4c4";  // 📄
    if ([key isEqualToString:ZHNAKeySearch])   return @"\U0001f50d";  // 🔍
    if ([key isEqualToString:ZHNAKeyPopup])    return @"\U0001f4ac";  // 💬
    if ([key isEqualToString:ZHNAKeyPaid])     return @"\U0001f4b0";  // 💰
    if ([key isEqualToString:ZHNAKeyTracking]) return @"\U0001f4e1";  // 📡
    if ([key isEqualToString:ZHNAKeyUIGuard])  return @"\U0001f441";  // 👁️
    if ([key isEqualToString:ZHNAKeyDebug])    return @"\U0001f41e";  // 🐛
    return @"⚙️";
}

static void ZHNABuildAndShowPanel(id window) {
    if (gPanelVisible) return;
    gPanelVisible = YES;

    @try {
        CGRect screenBounds = ZGR(window, sel_registerName("bounds"));
        CGFloat screenW = screenBounds.size.width;
        CGFloat screenH = screenBounds.size.height;

        // ---- 1. 半透明遮罩 ----
        Class viewCls = ZHNAClass("UIView");
        id overlay = ZS0(viewCls, sel_registerName("new"));
        ZVR(overlay, sel_registerName("frame:"), screenBounds);
        ZV1(overlay, sel_registerName("setBackgroundColor:"), ZColor(0, 0, 0, 0.35));
        ZVB(overlay, sel_registerName("setUserInteractionEnabled:"), YES);

        // 遮罩点击手势 → 关闭
        Class tapGestCls = ZHNAClass("UITapGestureRecognizer");
        id overlayTap = ZS0(tapGestCls, sel_registerName("new"));
        ZHNAEnsureCmdTarget();
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(
            overlayTap, sel_registerName("addTarget:action:"),
            gUICmdTarget, sel_registerName("zhna_onOverlayTap:"));
        ZV1(overlay, sel_registerName("addGestureRecognizer:"), overlayTap);

        ZV1(window, sel_registerName("addSubview:"), overlay);
        gOverlayView = overlay;

        // ---- 2. 白色卡片容器 ----
        CGFloat cardW = (kCardW < screenW - 24) ? kCardW : screenW - 24;
        CGFloat cardMaxH = screenH * 0.85;
        id card = ZS0(viewCls, sel_registerName("new"));
        CGFloat cardX = (screenW - cardW) / 2.0;
        CGFloat cardY = (screenH - cardMaxH) / 2.0;
        ZVR(card, sel_registerName("frame:"), (CGRect){{cardX, cardY}, {cardW, cardMaxH}});
        ZV1(card, sel_registerName("setBackgroundColor:"), ZColor(1, 1, 1, 1));  // 白色
        id cardLayer = ZS0(card, sel_registerName("layer"));
        ZVF(cardLayer, sel_registerName("setCornerRadius:"), kCardRadius);
        ZVB(cardLayer, sel_registerName("setMasksToBounds:"), YES);
        ZV1(overlay, sel_registerName("addSubview:"), card);
        gCardView = card;

        // ---- 3. Header ----
        CGFloat yCursor = 18;
        id titleLbl = ZHNAMakeLabel(
            [NSString stringWithFormat:@"%@  v%@", ZHNA_DISPLAY_NAME, ZHNA_VERSION],
            19, YES, ZColor(0.1, 0.1, 0.1, 1));
        ZVR(titleLbl, sel_registerName("frame:"), (CGRect){{kPadH, yCursor}, {cardW - kPadH * 2, 28}});
        ZV1(card, sel_registerName("addSubview:"), titleLbl);
        yCursor += 32;

        id subLbl = ZHNAMakeLabel(
            [NSString stringWithFormat:@"已拦截 %ld 项 · 改完立即生效", (long)ZHNAStatsTotal()],
            13, NO, ZColor(0.55, 0.55, 0.55, 1));
        ZVR(subLbl, sel_registerName("frame:"), (CGRect){{kPadH, yCursor}, {cardW - kPadH * 2, 20}});
        ZV1(card, sel_registerName("addSubview:"), subLbl);
        yCursor += 28;

        // Header 底部分割线
        id headerDiv = ZHNAMakeDivider();
        ZVR(headerDiv, sel_registerName("frame:"), (CGRect){{kPadH, yCursor}, {cardW - kPadH * 2, kDividerH}});
        ZV1(card, sel_registerName("addSubview:"), headerDiv);
        yCursor += 10;

        // ---- 4. 开关区域（UIScrollView） ----
        NSArray *keys = ZHNAAllKeys();
        CGFloat toggleAreaH = keys.count * kRowH;
        // 限制最大高度，超出则滚动
        CGFloat maxToggleH = cardMaxH - yCursor - 140;  // 给底部操作区留空间
        if (toggleAreaH > maxToggleH) toggleAreaH = maxToggleH;

        Class scrollCls = ZHNAClass("UIScrollView");
        id scrollView = ZS0(scrollCls, sel_registerName("new"));
        ZVR(scrollView, sel_registerName("frame:"), (CGRect){{0, yCursor}, {cardW, toggleAreaH}});
        ZVB(scrollView, sel_registerName("setShowsVerticalScrollIndicator:"), (BOOL)YES);
        ZVB(scrollView, sel_registerName("setAlwaysBounceVertical:"), (BOOL)YES);
        ZV1(card, sel_registerName("addSubview:"), scrollView);
        gToggleScrollView = scrollView;

        CGFloat rowY = 0;
        for (NSUInteger idx = 0; idx < keys.count; idx++) {
            NSString *key = keys[idx];
            BOOL isOn = ZHNAConfigRawBool(key);
            NSString *title = ZHNATitleForKey(key);
            NSString *emoji = ZHNAEmojiForKey(key);

            // 图标
            id iconLbl = ZHNAMakeIconLabel(emoji);
            ZVR(iconLbl, sel_registerName("frame:"), (CGRect){{kPadH, rowY + (kRowH - 26) / 2}, {30, 26}});
            ZV1(scrollView, sel_registerName("addSubview:"), iconLbl);

            // 标题文字
            id lbl = ZHNAMakeLabel(title, 16, NO, ZColor(0.15, 0.15, 0.15, 1));
            ZVR(lbl, sel_registerName("frame:"), (CGRect){{kPadH + 34, rowY + (kRowH - 22) / 2}, {cardW - kPadH * 2 - 70, 22}});
            ZV1(scrollView, sel_registerName("addSubview:"), lbl);

            // UISwitch
            id sw = ZHNAMakeSwitch(key, isOn);
            CGFloat swW = 51, swH = 31;
            ZVR(sw, sel_registerName("frame:"),
               (CGRect){{cardW - kPadH - swW - 4, rowY + (kRowH - swH) / 2}, {swW, swH}});
            ZV1(scrollView, sel_registerName("addSubview:"), sw);

            // 分割线（最后一行不加）
            if (idx < keys.count - 1) {
                id div = ZHNAMakeDivider();
                ZVR(div, sel_registerName("frame:"),
                   (CGRect){{kPadH, rowY + kRowH - kDividerH}, {cardW - kPadH * 2, kDividerH}});
                ZV1(scrollView, sel_registerName("addSubview:"), div);
            }

            rowY += kRowH;
        }

        // 设置 contentSize
        ((void (*)(id, SEL, CGSize))objc_msgSend)(
            scrollView, sel_registerName("setContentSize:"),
            (CGSize){cardW, rowY});

        yCursor += toggleAreaH + 8;

        // ---- 5. 操作按钮区 ----
        CGFloat btnH = 38;
        CGFloat btnGap = 10;
        CGFloat btnW = (cardW - kPadH * 2 - btnGap) / 2.0;

        // 第一行：拦截统计 | 导出日志
        id statsBtn = ZHNAMakeButton(@"📊 拦截统计",
            ZColor(0.92, 0.94, 0.98, 1), ZColor(0.05, 0.25, 0.85, 1), 14, ^{
            zhna_dismissPanel();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ ZHNAShowStatsPanel(window); });
        });
        ZVR(statsBtn, sel_registerName("frame:"), (CGRect){{kPadH, yCursor}, {btnW, btnH}});
        ZV1(card, sel_registerName("addSubview:"), statsBtn);

        id exportBtn = ZHNAMakeButton(@"📋 导出日志",
            ZColor(0.92, 0.94, 0.98, 1), ZColor(0.05, 0.25, 0.85, 1), 14, ^{
            zhna_dismissPanel();
            NSString *path = ZHNALogExport();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ZHNAShowToast(window, path ?
                    [NSString stringWithFormat:@"已保存到\n%@", path] : @"保存失败");
            });
        });
        ZVR(exportBtn, sel_registerName("frame:"), (CGRect){{kPadH + btnW + btnGap, yCursor}, {btnW, btnH}});
        ZV1(card, sel_registerName("addSubview:"), exportBtn);
        yCursor += btnH + 10;

        // 第二行：恢复默认 | 关闭
        id resetBtn = ZHNAMakeButton(@"↩️ 恢复默认",
            ZColor(1, 0.93, 0.92, 1), ZColor(0.85, 0.15, 0.15, 1), 14, ^{
            ZHNAConfigResetToDefault();
            zhna_dismissPanel();
            ZHNALog(@"设置已恢复默认");
        });
        ZVR(resetBtn, sel_registerName("frame:"), (CGRect){{kPadH, yCursor}, {btnW, btnH}});
        ZV1(card, sel_registerName("addSubview:"), resetBtn);

        id closeBtn = ZHNAMakeButton(@"✕ 关闭",
            ZColor(0.90, 0.90, 0.92, 1), ZColor(0.40, 0.40, 0.42, 1), 14, ^{
            zhna_dismissPanel();
        });
        ZVR(closeBtn, sel_registerName("frame:"), (CGRect){{kPadH + btnW + btnGap, yCursor}, {btnW, btnH}});
        ZV1(card, sel_registerName("addSubview:"), closeBtn);
        yCursor += btnH + 16;

        // 调整卡片实际高度（不要留太多空白）
        CGFloat actualCardH = yCursor;
        if (actualCardH < cardMaxH) {
            ZVR(card, sel_registerName("frame:"), (CGRect){{cardX, (screenH - actualCardH) / 2}, {cardW, actualCardH}});
        }

        // 卡片入场小动画
        id animCls2 = ZHNAClass("UIView");
        ZVF(gCardView, sel_registerName("setAlpha:"), 0);
        ZVP(gCardView, sel_registerName("setCenter:"), (CGPoint){screenW/2, screenH/2 + 30});
        ((void (*)(id, SEL, double, id))objc_msgSend)(
            animCls2, sel_registerName("animateWithDuration:animations:"),
            0.22, ^{
                ZVF(gCardView, sel_registerName("setAlpha:"), 1);
                ZVP(gCardView, sel_registerName("setCenter:"), (CGPoint){screenW/2, screenH/2});
            });

    } @catch (NSException *e) {
        ZHNALog(@"构建设置面板失败: %@", e);
        gPanelVisible = NO;
        if (gOverlayView) { [gOverlayView removeFromSuperview]; gOverlayView = nil; gCardView = nil; }
    }
}

#pragma mark - Toast 提示

static void ZHNAShowToast(id window, NSString *msg) {
    @try {
        Class toastCls = ZHNAClass("UIView");
        if (toastCls == Nil) return;
        CGRect sb = ZGR(window, sel_registerName("bounds"));

        id toast = ZS0(toastCls, sel_registerName("new"));
        CGFloat tw = sb.size.width * 0.7;
        ZVR(toast, sel_registerName("frame:"), (CGRect){{(sb.size.width - tw)/2, sb.size.height * 0.65}, {tw, 44}});
        ZV1(toast, sel_registerName("setBackgroundColor:"), ZColor(0.15, 0.15, 0.15, 0.88));
        id tLayer = ZS0(toast, sel_registerName("layer"));
        ZVF(tLayer, sel_registerName("setCornerRadius:"), 10);
        ZVB(tLayer, sel_registerName("setMasksToBounds:"), YES);

        id tLbl = ZHNAMakeLabel(msg, 13, NO, ZColor(1, 1, 1, 1));
        // 先释放 ZS0 new 出来的空标签，再用 initWithFrame 重新创建
    [tLbl removeFromSuperview];
    Class lblCls2 = ZHNAClass("UILabel");
    tLbl = ((id (*)(id, SEL, CGRect))objc_msgSend)(lblCls2, sel_registerName("initWithFrame:"), (CGRect){{8, 0}, {tw - 16, 44}});  // re-create with frame
        // Actually let's just create fresh
        Class lblCls = ZHNAClass("UILabel");
        tLbl = ZS0(lblCls, sel_registerName("new"));
        ZVR(tLbl, sel_registerName("frame:"), (CGRect){{8, 0}, {tw - 16, 44}});
        ZV1(tLbl, sel_registerName("setText:"), msg);
        ZV1(tLbl, sel_registerName("setTextColor:"), ZColor(1, 1, 1, 1));
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(tLbl, sel_registerName("setTextAlignment:"), (NSInteger)1);  // NSTextAlignmentCenter
        id tf = ZFont(13, NO);
        if (tf) ZV1(tLbl, sel_registerName("setFont:"), tf);
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(tLbl, sel_registerName("numberOfLines:"), (NSInteger)0);
        ZV1(toast, sel_registerName("addSubview:"), tLbl);

        ZV1(window, sel_registerName("addSubview:"), toast);

        // 自动消失
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            ((void (*)(id, SEL, double, id))objc_msgSend)(
                toastCls, sel_registerName("animateWithDuration:animations:"),
                0.25, ^{ ZVF(toast, sel_registerName("setAlpha:"), 0); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [toast removeFromSuperview]; });
        });
    } @catch (NSException *e) {
        ZHNALog(@"Toast 显示失败: %@", e);
    }
}

#pragma mark - 统计面板（保留旧逻辑，改为 Toast 展示）

static void ZHNAShowStatsPanel(id window) {
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

    ZHNAShowToast(window, msg);
}

#pragma mark - 公开 API

/// 在任何时机呼出主设置面板
void ZHNAOpenSettingsPanel(void) {
    if (gPanelVisible) return;
    id window = ZHNAKeyWindow();
    if (window == nil) {
        ZHNALog(@"呼出设置面板失败：取不到 keyWindow");
        return;
    }
    if (gFloatButton) ZVB(gFloatButton, sel_registerName("setHidden:"), YES);
    ZHNABuildAndShowPanel(window);
}

/// 安装悬浮按钮 + 摇一摇拦截
void ZHNAInstallSettingsPanel(void) {
    ZHNAInstallMotionGuard();      // 拦截知乎原生摇一摇跳广告
    ZHNAInstallFloatingButton();   // 安装可拖动悬浮按钮
}

#pragma mark - 悬浮按钮（保留不变）

static void ZHNASaveButtonCenter(CGPoint c) {
    Class cls = ZHNAClass("NSUserDefaults");
    if (cls == Nil) return;
    id ud = ZS0(cls, sel_registerName("standardUserDefaults"));
    if (ud == nil) return;
    id str = ((id (*)(id, SEL, id, double, double))objc_msgSend)(
        ZHNAClass("NSString"), sel_registerName("stringWithFormat:"),
        ZStr("%f,%f"), (double)c.x, (double)c.y);
    ZV2(ud, sel_registerName("setObject:forKey:"), str, ZStr("ZHNAFloatBtnCenter"));
    ZS0(ud, sel_registerName("synchronize"));
}

static CGPoint ZHNALoadButtonCenter(void) {
    Class cls = ZHNAClass("NSUserDefaults");
    if (cls == Nil) return (CGPoint){0, 0};
    id ud = ZS0(cls, sel_registerName("standardUserDefaults"));
    if (ud == nil) return (CGPoint){0, 0};
    id str = ZS1(ud, sel_registerName("objectForKey:"), ZStr("ZHNAFloatBtnCenter"));
    if (str == nil) return (CGPoint){0, 0};
    id parts = ZS1(str, sel_registerName("componentsSeparatedByString:"), ZStr(","));
    if (ZGI(parts, sel_registerName("count")) != 2) return (CGPoint){0, 0};
    id xstr = ((id (*)(id, SEL, NSInteger))objc_msgSend)(parts, sel_registerName("objectAtIndex:"), 0);
    id ystr = ((id (*)(id, SEL, NSInteger))objc_msgSend)(parts, sel_registerName("objectAtIndex:"), 1);
    CGFloat x = (CGFloat)ZGD(xstr, sel_registerName("doubleValue"));
    CGFloat y = (CGFloat)ZGD(ystr, sel_registerName("doubleValue"));
    return (CGPoint){x, y};
}

static void zhna_onPan(id self, SEL _cmd, id gesture);
static void zhna_onTap(id self, SEL _cmd, id gesture);

static void zhna_onTap(id self, SEL _cmd, id gesture) {
    @try { ZHNAOpenSettingsPanel(); }
    @catch (NSException *e) { ZHNALog(@"悬浮按钮轻点失败: %@", e); }
}

static id ZHNAFloatingTarget(void) {
    static id target = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class base = ZHNAClass("NSObject");
        if (base == Nil) return;
        Class cls = objc_allocateClassPair(base, "ZHNAFloatTarget", 0);
        class_addMethod(cls, sel_registerName("zhna_onPan:"),
                        (IMP)zhna_onPan, "v@:@");
        class_addMethod(cls, sel_registerName("zhna_onTap:"),
                        (IMP)zhna_onTap, "v@:@");
        class_addMethod(cls, sel_registerName("zhna_onWindowChange:"),
                        (IMP)zhna_onWindowChange, "v@:@");
        objc_registerClassPair(cls);
        target = ZS0(cls, sel_registerName("new"));
    });
    return target;
}

static void zhna_onPan(id self, SEL _cmd, id gesture) {
    NSInteger state = ZGI(gesture, sel_registerName("state"));
    id btn = ZS0(gesture, sel_registerName("view"));
    if (btn == nil) return;
    id window = ZHNAKeyWindow();
    if (window == nil) window = ZS0(btn, sel_registerName("superview"));
    if (window == nil) return;

    if (state == 1) {
        gBtnStartCenter = ZGP(btn, sel_registerName("center"));
    } else if (state == 2) {
        CGPoint t = ZGP1(gesture, sel_registerName("translationInView:"), window);
        CGPoint nc = (CGPoint){ gBtnStartCenter.x + t.x, gBtnStartCenter.y + t.y };
        CGRect b = ZGR(window, sel_registerName("bounds"));
        CGFloat half = 24;
        if (nc.x < half) nc.x = half;
        if (nc.x > b.size.width - half) nc.x = b.size.width - half;
        if (nc.y < half) nc.y = half;
        if (nc.y > b.size.height - half) nc.y = b.size.height - half;
        ZVP(btn, sel_registerName("setCenter:"), nc);
        ZV1(window, sel_registerName("bringSubviewToFront:"), btn);
    } else if (state == 3 || state == 4) {
        CGPoint t = ZGP1(gesture, sel_registerName("translationInView:"), window);
        CGPoint c = ZGP(btn, sel_registerName("center"));
        if (t.x * t.x + t.y * t.y > 400) {
            ZHNASaveButtonCenter(c);
        } else {
            ZHNAOpenSettingsPanel();
        }
    }
}

static void ZHNARepinFloatButton(void) {
    if (gFloatButton == nil) return;
    id kw = ZHNAKeyWindow();
    if (kw == nil) return;
    id sup = ZS0(gFloatButton, sel_registerName("superview"));
    if (sup != kw) {
        [gFloatButton removeFromSuperview];
        ZV1(kw, sel_registerName("addSubview:"), gFloatButton);
    }
    ZV1(kw, sel_registerName("bringSubviewToFront:"), gFloatButton);
    ZVB(gFloatButton, sel_registerName("setHidden:"), gPanelVisible ? YES : NO);
}

static void zhna_onWindowChange(id self, SEL _cmd, id note) {
    @try { ZHNARepinFloatButton(); }
    @catch (NSException *e) { ZHNALog(@"悬浮按钮重新置顶失败: %@", e); }
}

static void ZHNAInstallFloatingButton(void) {
    if (gFloatingInstalled) return;

    id hostWindow = ZHNAKeyWindow();
    if (hostWindow == nil) {
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
        id btn = ZS0(btnCls, sel_registerName("new"));
        if (btn == nil) return;

        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(btn, sel_registerName("setTitle:forState:"), ZStr("去"), 0);
        ((void (*)(id, SEL, id, NSInteger))objc_msgSend)(btn, sel_registerName("setTitleColor:forState:"), ZColor(1, 1, 1, 1), 0);
        ZV1(btn, sel_registerName("setBackgroundColor:"), ZColor(0.08, 0.08, 0.08, 0.55));
        ZVB(btn, sel_registerName("setUserInteractionEnabled:"), YES);
        ZVB(btn, sel_registerName("setClipsToBounds:"), YES);

        CGFloat size = 48;
        ZVR(btn, sel_registerName("frame:"), (CGRect){{0, 0}, {size, size}});
        id layer = ZS0(btn, sel_registerName("layer"));
        ZVF(layer, sel_registerName("setCornerRadius:"), (CGFloat)(size / 2));
        ZVB(layer, sel_registerName("setMasksToBounds:"), YES);

        CGRect sb = ZGR(ZS0(ZHNAClass("UIScreen"), sel_registerName("mainScreen")), sel_registerName("bounds"));
        CGPoint c = ZHNALoadButtonCenter();
        if (c.x <= 0 || c.y <= 0) {
            c = (CGPoint){ sb.size.width - size / 2 - 8, sb.size.height / 2 };
        }
        ZVP(btn, sel_registerName("setCenter:"), c);

        Class panCls = ZHNAClass("UIPanGestureRecognizer");
        id pan = ZS0(panCls, sel_registerName("new"));
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(pan, sel_registerName("addTarget:action:"),
                  ZHNAFloatingTarget(), sel_registerName("zhna_onPan:"));
        ZV1(btn, sel_registerName("addGestureRecognizer:"), pan);

        Class tapCls = ZHNAClass("UITapGestureRecognizer");
        id tap = ZS0(tapCls, sel_registerName("new"));
        ((void (*)(id, SEL, id, SEL))objc_msgSend)(tap, sel_registerName("addTarget:action:"),
                  ZHNAFloatingTarget(), sel_registerName("zhna_onTap:"));
        ZV1(btn, sel_registerName("addGestureRecognizer:"), tap);

        ZV1(hostWindow, sel_registerName("addSubview:"), btn);
        ZV1(hostWindow, sel_registerName("bringSubviewToFront:"), btn);

        gFloatButton = btn;

        if (!gFloatObsInstalled) {
            gFloatObsInstalled = YES;
            ZHNAEnsureCmdTarget();
            [[NSNotificationCenter defaultCenter]
                addObserver:gUICmdTarget
                   selector:sel_registerName("zhna_onWindowChange:")
                       name:@"UIWindowDidBecomeKeyNotification"
                     object:nil];
            [[NSNotificationCenter defaultCenter]
                addObserver:gUICmdTarget
                   selector:sel_registerName("zhna_onWindowChange:")
                       name:@"UIWindowDidBecomeVisibleNotification"
                     object:nil];
        }

        gFloatingInstalled = YES;
        ZHNALog(@"悬浮按钮已安装（挂在 keyWindow，随窗口切换自动置顶；轻点呼出设置，可拖动）");
    } @catch (NSException *e) {
        ZHNALog(@"悬浮按钮安装失败: %@", e);
    }
}

