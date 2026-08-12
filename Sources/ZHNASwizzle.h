//
//  ZHNASwizzle.h
//  纯 runtime 方法替换（不依赖 CydiaSubstrate / ElleKit / libhooker）
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// 替换实例方法。成功返回 YES，并把原实现写入 outOriginal。
BOOL ZHNASwizzleInstanceMethod(Class _Nullable cls, SEL sel, IMP newIMP, IMP _Nullable *_Nullable outOriginal);

/// 替换类方法。
BOOL ZHNASwizzleClassMethod(Class _Nullable cls, SEL sel, IMP newIMP, IMP _Nullable *_Nullable outOriginal);

/// 按类名替换实例方法（类不存在时安全返回 NO）
BOOL ZHNASwizzleInstanceMethodNamed(const char *className, const char *selName, IMP newIMP, IMP _Nullable *_Nullable outOriginal);

NS_ASSUME_NONNULL_END
