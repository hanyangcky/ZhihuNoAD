//
//  ZHNAEntry.m
//  插件入口
//

#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNANetworkGuard.h"
#import "ZHNAUIGuard.h"
#import "ZHNASettingsPanel.h"

/// 只在知乎里生效。哪怕被误注入到别的 App，也什么都不做。
static BOOL ZHNAShouldActivate(void) {
    if (getenv("ZHNA_FORCE") != NULL) return YES;

    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    if (bundleID.length == 0) return NO;

    NSString *lower = bundleID.lowercaseString;
    if ([lower hasPrefix:@"com.zhihu."]) return YES;
    if ([lower isEqualToString:@"com.zhihu.ios"]) return YES;
    // 部分自签/改名版本
    if ([lower containsString:@"zhihu"]) return YES;

    return NO;
}

static void ZHNAInstallUILayers(void) {
    if (ZHNAClass("UIView") == Nil) return;   // UIKit 还没加载，等通知
    ZHNAInstallUIGuard();
    ZHNAInstallSettingsPanel();   // 双指长按呼出设置面板
}

/// 进程级幂等锁：即使 dylib 被加载两次（例如同时存在于两个注入目录），也只初始化一次，
/// 避免 swizzle 被重复执行导致原始实现链断裂。用 mainBundle 上的关联对象作为跨镜像标记。
static BOOL ZHNAEnsureFirstRun(void) {
    static const void *kZHNARunOnce = &kZHNARunOnce;
    NSBundle *main = [NSBundle mainBundle];
    if (objc_getAssociatedObject(main, kZHNARunOnce) != nil) return NO;
    objc_setAssociatedObject(main, kZHNARunOnce, @(YES), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

__attribute__((constructor))
static void ZHNABootstrap(void) {
    @autoreleasepool {
        @try {
            if (!ZHNAShouldActivate()) return;
            if (!ZHNAEnsureFirstRun()) return;   // 已经初始化过，直接退出

            ZHNALog(@"%@ v%@ 启动，宿主 %@", ZHNA_DISPLAY_NAME, ZHNA_VERSION,
                    [[NSBundle mainBundle] bundleIdentifier]);

            // 网络层必须尽早装上，赶在 App 发第一个请求之前
            ZHNAInstallNetworkGuard();

            // UIKit 可能还没就绪，先试一次，再挂一个通知兜底
            ZHNAInstallUILayers();

            [[NSNotificationCenter defaultCenter]
                addObserverForName:@"UIApplicationDidFinishLaunchingNotification"
                            object:nil
                             queue:nil
                        usingBlock:^(NSNotification *note) {
                ZHNAInstallUILayers();
                ZHNALog(@"启动完成，防线全部就位");
            }];

        } @catch (NSException *e) {
            // 插件自己出问题，绝不能连累 App 启动
            NSLog(@"[ZhihuNoAds] 初始化异常: %@", e);
        }
    }
}
