//
//  ZHNASwizzle.m
//

#import "ZHNASwizzle.h"
#import "ZHNACommon.h"

static BOOL ZHNASwizzleInternal(Class cls, SEL sel, IMP newIMP, IMP *outOriginal) {
    if (cls == Nil || sel == NULL || newIMP == NULL) return NO;

    Method method = class_getInstanceMethod(cls, sel);
    if (method == NULL) {
        ZHNALog(@"swizzle 失败(方法不存在): %s -[%@]", class_getName(cls), NSStringFromSelector(sel));
        return NO;
    }

    const char *types = method_getTypeEncoding(method);
    IMP original = method_getImplementation(method);

    // 该类自己没有实现（继承自父类）时，先给它加一个自己的实现
    if (class_addMethod(cls, sel, newIMP, types)) {
        if (outOriginal) *outOriginal = original;   // 原实现来自父类，直接调用即可
        return YES;
    }

    // 该类自己实现了，直接换掉
    IMP previous = method_setImplementation(method, newIMP);
    if (outOriginal) *outOriginal = previous;
    return YES;
}

BOOL ZHNASwizzleInstanceMethod(Class cls, SEL sel, IMP newIMP, IMP *outOriginal) {
    return ZHNASwizzleInternal(cls, sel, newIMP, outOriginal);
}

BOOL ZHNASwizzleClassMethod(Class cls, SEL sel, IMP newIMP, IMP *outOriginal) {
    if (cls == Nil) return NO;
    return ZHNASwizzleInternal(object_getClass(cls), sel, newIMP, outOriginal);
}

BOOL ZHNASwizzleInstanceMethodNamed(const char *className, const char *selName, IMP newIMP, IMP *outOriginal) {
    Class cls = objc_getClass(className);
    if (cls == Nil) {
        ZHNALog(@"swizzle 跳过(类不存在): %s", className);
        return NO;
    }
    return ZHNASwizzleInternal(cls, sel_registerName(selName), newIMP, outOriginal);
}
