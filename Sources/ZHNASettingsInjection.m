//
//  ZHNASettingsInjection.m
//
//  在知乎 App 自带的"设置"页面里，插入一行本插件的设置入口，样式尽量贴合知乎原生设置。
//  做法：监听 UIViewController 的 viewDidAppear:，识别出"设置"页后找到它的 UITableView，
//  对其 dataSource 的三个方法做 runtime 替换，在末尾多出一个 section/一行；点击即呼出设置面板。
//
//  全程不链接 UIKit：UIKit 相关调用一律走 objc_msgSend + objc_getClass，
//  既能在 macOS 上编译，也兼容越狱/巨魔两种注入环境。
//

#import "ZHNASettingsInjection.h"
#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNASettingsPanel.h"
#import "ZHNASwizzle.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

static const void *kZHNAInjectedTableKey = &kZHNAInjectedTableKey; // 挂在 UITableView 上：@(我们的 section 索引)
static const void *kZHNAVCDoneKey        = &kZHNAVCDoneKey;        // 挂在 VC 上：本实例是否已处理过
static const void *kZHNADSwizzledKey     = &kZHNADSwizzledKey;     // 挂在 dataSource 类上：是否已 swizzle

#pragma mark - 原始实现存储（按 类+方法 存，支持多个 dataSource 类）

static NSMutableDictionary *gOrigMap;
static dispatch_once_t gOrigMapOnce;

static NSString *ZHNAOrigKey(Class cls, NSString *sel) {
    return [NSString stringWithFormat:@"%p_%@", (void *)cls, sel];
}
static IMP ZHNALookupOrig(Class cls, NSString *sel) {
    dispatch_once(&gOrigMapOnce, ^{ gOrigMap = [NSMutableDictionary new]; });
    NSValue *v = gOrigMap[ZHNAOrigKey(cls, sel)];
    return v ? (IMP)[v pointerValue] : NULL;
}
static void ZHNAStoreOrig(Class cls, NSString *sel, IMP imp) {
    dispatch_once(&gOrigMapOnce, ^{ gOrigMap = [NSMutableDictionary new]; });
    gOrigMap[ZHNAOrigKey(cls, sel)] = [NSValue valueWithPointer:imp];
}

#pragma mark - UIKit runtime 小工具

// 调用任意 UIKit 实例方法（返回 id）。必须走函数指针强转，不能直接 call objc_msgSend，
// 否则新 SDK 会报 "too many arguments / expected 0"。
#define ZHNA_CALL_ID(OBJ, SELSTR) ((id(*)(id, SEL))objc_msgSend)((OBJ), sel_registerName(SELSTR))
// 调用返回 NSInteger 的 UIKit 实例方法（无额外参数）
#define ZHNA_CALL_INT(OBJ, SELSTR) ((NSInteger(*)(id, SEL))objc_msgSend)((OBJ), sel_registerName(SELSTR))
// 调用返回 NSInteger、带一个 id 参数的 UIKit 实例方法
#define ZHNA_CALL_INT1(OBJ, SELSTR, A) ((NSInteger(*)(id, SEL, id))objc_msgSend)((OBJ), sel_registerName(SELSTR), (A))

static id ZHNAFindTableView(id view) {
    if (view == nil) return nil;
    Class tvCls = ZHNAClass("UITableView");
    if (tvCls != Nil && [view isKindOfClass:tvCls]) return view;

    // subviews 是 Foundation 对象，可以直接用
    id subviews = ZHNA_CALL_ID(view, "subviews");
    if (subviews == nil) return nil;
    NSInteger n = [subviews respondsToSelector:@selector(count)] ? [subviews count] : 0;
    for (NSInteger i = 0; i < n; i++) {
        id sv = [subviews objectAtIndex:i];
        id found = ZHNAFindTableView(sv);
        if (found) return found;
    }
    return nil;
}

static BOOL ZHNAIsSettingsVC(id vc) {
    if (vc == nil) return NO;

    // 1) 标题含"设置"
    id title = ZHNA_CALL_ID(vc, "title");
    if ([title isKindOfClass:[NSString class]] && [title containsString:@"设置"]) return YES;

    // 2) 类名含 Setting / Pref(erences)
    NSString *cls = NSStringFromClass(object_getClass(vc));
    if ([cls rangeOfString:@"Setting" options:NSCaseInsensitiveSearch].length > 0) return YES;
    if ([cls rangeOfString:@"Pref"    options:NSCaseInsensitiveSearch].length > 0) return YES;

    return NO;
}

#pragma mark - 单元格（仿知乎原生设置行样式）

static id ZHNAMakeSettingsCell(void) {
    Class cellCls = ZHNAClass("UITableViewCell");
    if (cellCls == Nil) return nil;

    id cell = ((id (*)(id, SEL))objc_msgSend)(cellCls, sel_registerName("alloc"));
    // initWithStyle:reuseIdentifier:  UITableViewCellStyleValue1 = 1
    cell = ((id (*)(id, SEL, NSInteger, id))objc_msgSend)(
        cell, sel_registerName("initWithStyle:reuseIdentifier:"), 1, nil);
    if (cell == nil) return nil;

    id textLabel = ZHNA_CALL_ID(cell, "textLabel");
    if (textLabel) {
        ((void (*)(id, SEL, id))objc_msgSend)(textLabel, sel_registerName("setText:"), @"知乎去广告");
    }

    id detail = ZHNA_CALL_ID(cell, "detailTextLabel");
    if (detail) {
        NSString *sub = [NSString stringWithFormat:@"v%@ · 点此设置", ZHNA_VERSION];
        ((void (*)(id, SEL, id))objc_msgSend)(detail, sel_registerName("setText:"), sub);
    }

    // accessoryType = UITableViewCellAccessoryDisclosureIndicator = 1
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(cell, sel_registerName("setAccessoryType:"), 1);
    return cell;
}

#pragma mark - dataSource 方法替换

// 我们的专属 section 索引存在 UITableView 的关联对象上（NSInteger 包成 NSNumber）。
static NSInteger ZHNAInjectedSection(id tableView) {
    NSNumber *n = objc_getAssociatedObject(tableView, kZHNAInjectedTableKey);
    return n ? [n integerValue] : -1;
}

static NSInteger new_numSections(id self, SEL _cmd, id tableView) {
    Class cls = object_getClass(self);
    IMP orig = ZHNALookupOrig(cls, @"numSections");
    NSInteger base = orig ? ZHNA_CALL_INT1(self, "numberOfSectionsInTableView:", tableView) : 1;
    if (ZHNAInjectedSection(tableView) >= 0) return base + 1;
    return base;
}

static NSInteger new_numRows(id self, SEL _cmd, id tableView, NSInteger section) {
    Class cls = object_getClass(self);
    IMP orig = ZHNALookupOrig(cls, @"numRows");
    NSInteger base = orig ? ((NSInteger(*)(id, SEL, id, NSInteger))orig)(self, _cmd, tableView, section) : 0;
    if (section == ZHNAInjectedSection(tableView)) return 1;  // 我们这一行
    return base;
}

static id new_cellForRow(id self, SEL _cmd, id tableView, id indexPath) {
    NSInteger sec = ZHNAInjectedSection(tableView);
    if (sec >= 0) {
        NSInteger ipSec = ZHNA_CALL_INT(indexPath, "section");
        NSInteger ipRow = ZHNA_CALL_INT(indexPath, "row");
        if (ipSec == sec && ipRow == 0) {
            return ZHNAMakeSettingsCell();
        }
    }
    IMP orig = ZHNALookupOrig(object_getClass(self), @"cell");
    if (orig) return ((id (*)(id, SEL, id, id))orig)(self, _cmd, tableView, indexPath);
    return nil;
}

static void new_didSelect(id self, SEL _cmd, id tableView, id indexPath) {
    NSInteger sec = ZHNAInjectedSection(tableView);
    if (sec >= 0) {
        NSInteger ipSec = ZHNA_CALL_INT(indexPath, "section");
        NSInteger ipRow = ZHNA_CALL_INT(indexPath, "row");
        if (ipSec == sec && ipRow == 0) {
            // 取消高亮，避免一直停在选中态
            ((void (*)(id, SEL, id, BOOL))objc_msgSend)(
                tableView, sel_registerName("deselectRowAtIndexPath:animated:"), indexPath, YES);
            ZHNAOpenSettingsPanel();
            return;
        }
    }
    IMP orig = ZHNALookupOrig(object_getClass(self), @"select");
    if (orig) ((void (*)(id, SEL, id, id))orig)(self, _cmd, tableView, indexPath);
}

#pragma mark - 注入装配

static void ZHNASwizzleClassForInjection(Class cls, BOOL includeDataSourceMethods) {
    if (cls == Nil) return;
    if (objc_getAssociatedObject(cls, kZHNADSwizzledKey)) return;  // 已处理
    objc_setAssociatedObject(cls, kZHNADSwizzledKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    IMP o;
    if (includeDataSourceMethods) {
        if (ZHNASwizzleInstanceMethod(cls, sel_registerName("numberOfSectionsInTableView:"),
                                      (IMP)new_numSections, &o) && o) ZHNAStoreOrig(cls, @"numSections", o);
        if (ZHNASwizzleInstanceMethod(cls, sel_registerName("tableView:numberOfRowsInSection:"),
                                      (IMP)new_numRows, &o) && o) ZHNAStoreOrig(cls, @"numRows", o);
        if (ZHNASwizzleInstanceMethod(cls, sel_registerName("tableView:cellForRowAtIndexPath:"),
                                      (IMP)new_cellForRow, &o) && o) ZHNAStoreOrig(cls, @"cell", o);
    }
    // didSelect 既是 delegate 方法也是数据源方法，两个类都要覆盖
    if (ZHNASwizzleInstanceMethod(cls, sel_registerName("tableView:didSelectRowAtIndexPath:"),
                                  (IMP)new_didSelect, &o) && o) ZHNAStoreOrig(cls, @"select", o);

    ZHNALog(@"已为设置页类(%@) 注入入口行逻辑", NSStringFromClass(cls));
}

/// 同时覆盖 dataSource 与 delegate（两者通常是同一个 VC，但也可能不同类）
static void ZHNASwizzleTableIfNeeded(id tableView) {
    id ds = ZHNA_CALL_ID(tableView, "dataSource");
    if (ds) ZHNASwizzleClassForInjection(object_getClass(ds), YES);
    id del = ZHNA_CALL_ID(tableView, "delegate");
    if (del && object_getClass(del) != object_getClass(ds)) {
        ZHNASwizzleClassForInjection(object_getClass(del), NO);
    }
}

static void ZHNAInjectIntoVC(id vc) {
    if (vc == nil) return;
    if (objc_getAssociatedObject(vc, kZHNAVCDoneKey)) return;           // 本实例只处理一次
    if (!ZHNAIsSettingsVC(vc)) return;

    id view = ZHNA_CALL_ID(vc, "view");
    id tableView = ZHNAFindTableView(view);
    if (tableView == nil) {
        ZHNALog(@"未在当前设置页找到 UITableView，跳过注入");
        return;
    }
    if (objc_getAssociatedObject(tableView, kZHNAInjectedTableKey)) {
        objc_setAssociatedObject(vc, kZHNAVCDoneKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;  // 表已注入
    }

    id dataSource = ZHNA_CALL_ID(tableView, "dataSource");
    if (dataSource == nil) {
        // data source 可能稍后才设，0.3s 后重试一次
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                id ds = ZHNA_CALL_ID(tableView, "dataSource");
                if (ds) {
                    // 注意：numberOfSectionsInTableView: 是 dataSource 的方法，
                    // UITableView 自身不响应它；正确做法是对表本身调用无参的 numberOfSections。
                    NSInteger sections = ZHNA_CALL_INT(tableView, "numberOfSections");
                    objc_setAssociatedObject(tableView, kZHNAInjectedTableKey,
                                             @(sections), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    ZHNASwizzleTableIfNeeded(tableView);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        @try { ZHNA_CALL_ID(tableView, "reloadData"); }
                        @catch (__unused NSException *e) {}
                    });
                }
            } @catch (__unused NSException *e) {
                // 延迟注入出错绝不影响知乎本身
            }
            objc_setAssociatedObject(vc, kZHNAVCDoneKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        });
        return;
    }

    NSInteger sections = ZHNA_CALL_INT(tableView, "numberOfSections");
    // 我们的专属 section 放在现有 section 之后
    objc_setAssociatedObject(tableView, kZHNAInjectedTableKey,
                             @(sections), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    ZHNASwizzleTableIfNeeded(tableView);

    objc_setAssociatedObject(vc, kZHNAVCDoneKey, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    // 下一轮 runloop 刷新，让新行出现
    dispatch_async(dispatch_get_main_queue(), ^{ ZHNA_CALL_ID(tableView, "reloadData"); });

    ZHNALog(@"已在设置页注入「知乎去广告」入口行");
}

#pragma mark - UIViewController 钩子

static void (*orig_vcAppear)(id, SEL, BOOL) = NULL;
static void new_vcAppear(id self, SEL _cmd, BOOL animated) {
    if (orig_vcAppear) orig_vcAppear(self, _cmd, animated);
    @try {
        ZHNAInjectIntoVC(self);
    } @catch (__unused NSException *e) {
        // 识别/注入出问题绝不影响知乎本身
    }
}

void ZHNAInstallSettingsInjection(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ZHNASwizzleInstanceMethodNamed("UIViewController", "viewDidAppear:",
                                       (IMP)new_vcAppear,
                                       (IMP *)&orig_vcAppear);
        ZHNALog(@"设置页入口注入已安装");
    });
}
