//
//  ZHNAJSONFilter.h
//  JSON 递归清洗引擎：把广告字段和广告条目从接口返回里剔除
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZHNAFilterResult : NSObject
@property (nonatomic, strong, nullable) id object;   // 清洗后的对象
@property (nonatomic, assign) NSInteger removedKeys;   // 删掉的广告字段数
@property (nonatomic, assign) NSInteger removedItems;  // 删掉的广告条目数
@property (nonatomic, assign) NSInteger removedPaid;   // 删掉的付费引流条目数
@property (nonatomic, readonly) BOOL changed;
@end

/// 清洗一个已解析的 JSON 对象（NSDictionary / NSArray）
ZHNAFilterResult *ZHNAFilterJSONObject(id _Nullable object);

NS_ASSUME_NONNULL_END
