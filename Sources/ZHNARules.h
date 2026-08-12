//
//  ZHNARules.h
//  广告识别规则库
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ZHNAAction) {
    ZHNAActionNone = 0,
    ZHNAActionEmptyJSON,   // 直接返回 {}，App 以为服务端没下发内容
    ZHNAActionDeny,        // 直接让请求失败（用于纯埋点/广告SDK域名）
};

@interface ZHNAURLVerdict : NSObject
@property (nonatomic, assign) ZHNAAction action;
@property (nonatomic, copy)   NSString *ruleName;   // 中文规则名，用于统计和日志
@property (nonatomic, copy)   NSString *category;   // 对应 ZHNAConfig 的开关 key
@end

/// 判断一个 URL 该不该拦截。不拦截返回 nil。
ZHNAURLVerdict *_Nullable ZHNAMatchURL(NSURL *_Nullable url);

/// JSON 里应该整个删掉的字段名（例如 ad_info / market_card）
BOOL ZHNAIsAdKey(NSString *key);

/// 判断数组里的某个条目是不是广告条目（信息流广告卡片）
BOOL ZHNAIsAdItem(NSDictionary *item);

/// 判断 type 字段的值是不是广告类型
BOOL ZHNATypeStringIsAd(NSString *_Nullable type);

/// 判断条目是不是"盐选付费故事"引流
BOOL ZHNAIsPaidItem(NSDictionary *item);

/// 判断一个类名看起来是不是广告相关（用于 UI 兜底，规则很保守，避免误伤）
BOOL ZHNAClassNameLooksLikeAd(NSString *_Nullable name);

/// 判断一个类名看起来是不是"开屏广告控制器"
BOOL ZHNAClassNameLooksLikeSplashAd(NSString *_Nullable name);

/// 快速预检：这段 JSON 数据里有没有可能含广告（避免对每个响应都做深度遍历）
BOOL ZHNADataMayContainAd(NSData *_Nullable data);

NS_ASSUME_NONNULL_END
