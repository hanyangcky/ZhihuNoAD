//
//  ZHNAConfig.h
//  开关配置（存在 App 自己的 NSUserDefaults 里，越狱/巨魔都能用）
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 功能分类开关。每一项对应设置面板里的一行。
extern NSString *const ZHNAKeyMaster;    // 总开关
extern NSString *const ZHNAKeySplash;    // 开屏广告
extern NSString *const ZHNAKeyFeed;      // 首页/热榜 信息流广告
extern NSString *const ZHNAKeyDetail;    // 回答/文章页推广卡片
extern NSString *const ZHNAKeySearch;    // 搜索页热搜/预置词推广
extern NSString *const ZHNAKeyPopup;     // 弹窗/浮层/角标
extern NSString *const ZHNAKeyPaid;      // 盐选付费故事推广
extern NSString *const ZHNAKeyTracking;  // 埋点/广告SDK域名
extern NSString *const ZHNAKeyUIGuard;   // UI 兜底（隐藏残留广告视图）
extern NSString *const ZHNAKeyDebug;     // 诊断模式

/// 所有开关的顺序列表（用于设置面板渲染）
NSArray<NSString *> *ZHNAAllKeys(void);
/// 开关的中文标题
NSString *ZHNATitleForKey(NSString *key);
/// 开关的说明文字
NSString *ZHNADetailForKey(NSString *key);

/// 读取开关（自动考虑总开关；总开关关闭时除 debug 外一律返回 NO）
BOOL ZHNAConfigBool(NSString *key);
/// 读取开关的原始值（不受总开关影响，设置面板显示用）
BOOL ZHNAConfigRawBool(NSString *key);
void ZHNAConfigSetBool(NSString *key, BOOL value);
void ZHNAConfigToggle(NSString *key);
void ZHNAConfigResetToDefault(void);

NS_ASSUME_NONNULL_END
