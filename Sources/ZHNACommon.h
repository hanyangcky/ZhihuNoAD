//
//  ZHNACommon.h
//  ZhihuNoAds — 知乎去广告插件
//
//  设计要点：
//  1. 不依赖 CydiaSubstrate / libhooker，纯 Objective-C runtime swizzle
//     => 同一个 dylib 既能在越狱环境加载，也能被巨魔(TrollFools/Azule)注入
//  2. 不链接 UIKit（通过影子协议 + objc_getClass 调用）
//     => 可在 macOS 上编译和跑单元测试，降低"编译不过"的风险
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

NS_ASSUME_NONNULL_BEGIN

#define ZHNA_VERSION @"1.1.1"
#define ZHNA_DISPLAY_NAME @"知乎去广告"

#pragma mark - 日志

/// 写入日志（始终进环形缓冲区，开启"诊断模式"时才输出到系统日志）
void ZHNALogImpl(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#define ZHNALog(...) ZHNALogImpl(__VA_ARGS__)

/// 取出最近的日志（最多 500 条）
NSArray<NSString *> *ZHNALogSnapshot(void);
void ZHNALogClear(void);
/// 把日志写到 App 沙盒 Documents 目录，返回文件路径
NSString *_Nullable ZHNALogExport(void);

#pragma mark - 拦截统计

void ZHNACount(NSString *key);
void ZHNACountBy(NSString *key, NSInteger delta);
NSDictionary<NSString *, NSNumber *> *ZHNAStatsSnapshot(void);
NSInteger ZHNAStatsTotal(void);
void ZHNAStatsReset(void);

#pragma mark - UIKit 影子协议

/// 只声明我们要用的方法，不引入 UIKit 头文件，也不产生 UIKit 链接依赖。
/// 使用方式：((id<ZHNAUIShim>)someView).hidden = YES;
@protocol ZHNAUIShim <NSObject>
@optional
// UIView
@property (nonatomic, assign) BOOL hidden;
@property (nonatomic, assign) CGFloat alpha;
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) BOOL userInteractionEnabled;
@property (nonatomic, readonly, nullable) id superview;
@property (nonatomic, readonly, nullable) id window;
- (void)removeFromSuperview;
// UIViewController
@property (nonatomic, readonly, nullable) id presentedViewController;
@property (nonatomic, readonly, nullable) id parentViewController;
@property (nonatomic, readonly, nullable) id view;
- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^_Nullable)(void))completion;
- (void)presentViewController:(id)vc animated:(BOOL)flag completion:(void (^_Nullable)(void))completion;
- (void)removeFromParentViewController;
// UIWindow
@property (nonatomic, nullable) id rootViewController;
// UIAlertController
- (void)addAction:(id)action;
@property (nonatomic, readonly, nullable) id popoverPresentationController;
@end

/// 安全地按名字取类，取不到返回 nil（不会崩）
NS_INLINE Class _Nullable ZHNAClass(const char *name) { return objc_getClass(name); }

NS_ASSUME_NONNULL_END
