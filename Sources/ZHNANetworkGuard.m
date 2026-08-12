//
//  ZHNANetworkGuard.m
//
//  两道防线：
//  第一道 —— NSURLProtocol：命中广告接口的请求直接本地回一个空 JSON，请求根本不出网。
//  第二道 —— NSJSONSerialization：不管 App 用什么网络库，JSON 最终都要过这里解析，
//            在这一层把广告字段和广告条目剔掉，版本升级也不容易失效。
//

#import "ZHNANetworkGuard.h"
#import "ZHNACommon.h"
#import "ZHNAConfig.h"
#import "ZHNARules.h"
#import "ZHNAJSONFilter.h"
#import "ZHNASwizzle.h"

static NSString *const kZHNAHandledKey = @"ZHNAHandled";

#pragma mark - 第一道：URL 拦截

@interface ZHNABlockURLProtocol : NSURLProtocol
@end

@implementation ZHNABlockURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (request.URL == nil) return NO;
    if ([NSURLProtocol propertyForKey:kZHNAHandledKey inRequest:request] != nil) return NO;
    if (!ZHNAConfigRawBool(ZHNAKeyMaster)) return NO;
    return ZHNAMatchURL(request.URL) != nil;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

+ (BOOL)requestIsCacheEquivalent:(NSURLRequest *)a toRequest:(NSURLRequest *)b {
    return NO;
}

- (void)startLoading {
    NSURL *url = self.request.URL;
    ZHNAURLVerdict *verdict = ZHNAMatchURL(url);

    NSString *ruleName = verdict.ruleName ?: @"未知规则";
    ZHNACount([NSString stringWithFormat:@"拦截·%@", ruleName]);
    if (ZHNAConfigBool(ZHNAKeyDebug)) {
        ZHNALog(@"拦截请求 [%@] %@", ruleName, url.absoluteString);
    }

    // 统一回一个 200 + 空 JSON：App 会认为"服务端没有下发内容"，
    // 比让请求失败更安全（不会触发重试、也不会弹网络错误）。
    NSData *body = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    NSHTTPURLResponse *response =
        [[NSHTTPURLResponse alloc] initWithURL:url
                                    statusCode:200
                                   HTTPVersion:@"HTTP/1.1"
                                  headerFields:@{
                                      @"Content-Type": @"application/json; charset=utf-8",
                                      @"Content-Length": [NSString stringWithFormat:@"%lu", (unsigned long)body.length],
                                      @"X-ZhihuNoAds": @"blocked"
                                  }];

    id<NSURLProtocolClient> client = self.client;
    [client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [client URLProtocol:self didLoadData:body];
    [client URLProtocolDidFinishLoading:self];
}

- (void)stopLoading {
    // 本地直接返回，无需清理
}

@end

#pragma mark - 让自定义 NSURLSession 也走我们的 Protocol

static NSArray *ZHNAEnsureProtocolClass(NSArray *classes) {
    Class p = [ZHNABlockURLProtocol class];
    NSMutableArray *m = classes ? [classes mutableCopy] : [NSMutableArray array];
    [m removeObject:p];
    [m insertObject:p atIndex:0];
    return [m copy];
}

static id (*orig_defaultSessionConfiguration)(id, SEL) = NULL;
static id new_defaultSessionConfiguration(id self, SEL _cmd) {
    id config = orig_defaultSessionConfiguration ? orig_defaultSessionConfiguration(self, _cmd) : nil;
    if ([config isKindOfClass:[NSURLSessionConfiguration class]]) {
        NSURLSessionConfiguration *c = (NSURLSessionConfiguration *)config;
        c.protocolClasses = ZHNAEnsureProtocolClass(c.protocolClasses);
    }
    return config;
}

static id (*orig_ephemeralSessionConfiguration)(id, SEL) = NULL;
static id new_ephemeralSessionConfiguration(id self, SEL _cmd) {
    id config = orig_ephemeralSessionConfiguration ? orig_ephemeralSessionConfiguration(self, _cmd) : nil;
    if ([config isKindOfClass:[NSURLSessionConfiguration class]]) {
        NSURLSessionConfiguration *c = (NSURLSessionConfiguration *)config;
        c.protocolClasses = ZHNAEnsureProtocolClass(c.protocolClasses);
    }
    return config;
}

/// App 常常自己 new 一个 configuration 并覆盖 protocolClasses，
/// 所以在"真正创建 session"的最后一刻再补一次，确保拦截器一定在列表里。
static void ZHNAFixupConfig(id config) {
    if ([config isKindOfClass:[NSURLSessionConfiguration class]]) {
        NSURLSessionConfiguration *c = (NSURLSessionConfiguration *)config;
        c.protocolClasses = ZHNAEnsureProtocolClass(c.protocolClasses);
    }
}

static id (*orig_sessionWithConfiguration)(id, SEL, id) = NULL;
static id new_sessionWithConfiguration(id self, SEL _cmd, id config) {
    ZHNAFixupConfig(config);
    return orig_sessionWithConfiguration ? orig_sessionWithConfiguration(self, _cmd, config) : nil;
}

static id (*orig_sessionWithConfigurationDelegate)(id, SEL, id, id, id) = NULL;
static id new_sessionWithConfigurationDelegate(id self, SEL _cmd, id config, id delegate, id queue) {
    ZHNAFixupConfig(config);
    return orig_sessionWithConfigurationDelegate
         ? orig_sessionWithConfigurationDelegate(self, _cmd, config, delegate, queue)
         : nil;
}

#pragma mark - 第二道：JSON 清洗

static id (*orig_JSONObjectWithData)(id, SEL, NSData *, NSJSONReadingOptions, NSError **) = NULL;

static id new_JSONObjectWithData(id self, SEL _cmd, NSData *data,
                                 NSJSONReadingOptions opt, NSError **error) {
    id result = orig_JSONObjectWithData ? orig_JSONObjectWithData(self, _cmd, data, opt, error) : nil;
    if (result == nil) return result;
    if (!ZHNAConfigRawBool(ZHNAKeyMaster)) return result;

    // 快速预检，绝大多数响应在这里就被放行了，几乎没有性能开销
    if (!ZHNADataMayContainAd(data)) return result;

    ZHNAFilterResult *filtered = ZHNAFilterJSONObject(result);
    if (!filtered.changed) return result;

    ZHNACountBy(@"过滤·广告字段", filtered.removedKeys);
    ZHNACountBy(@"过滤·广告条目", filtered.removedItems);
    ZHNACountBy(@"过滤·付费引流", filtered.removedPaid);

    if (ZHNAConfigBool(ZHNAKeyDebug)) {
        ZHNALog(@"JSON 清洗: 字段-%ld 条目-%ld 付费-%ld",
                (long)filtered.removedKeys, (long)filtered.removedItems, (long)filtered.removedPaid);
    }

    id output = filtered.object;

    // 调用方要求可变容器时，重新走一遍解析，保证可变性语义完全一致（否则 App 改数据会崩）
    if (opt & (NSJSONReadingMutableContainers | NSJSONReadingMutableLeaves)) {
        NSError *reErr = nil;
        NSData *reData = [NSJSONSerialization dataWithJSONObject:output options:0 error:&reErr];
        if (reData != nil) {
            id remade = orig_JSONObjectWithData(self, _cmd, reData, opt, error);
            if (remade != nil) return remade;
        }
        // 重建失败就退回原始结果，宁可留广告也不能让 App 崩
        return result;
    }

    return output;
}

#pragma mark - 安装

void ZHNAInstallNetworkGuard(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // 1) 注册 URL 拦截器（覆盖 NSURLConnection 和 sharedSession）
        [NSURLProtocol registerClass:[ZHNABlockURLProtocol class]];

        // 2) 让 App 自建的 NSURLSession 也带上我们的拦截器
        Class cfgCls = [NSURLSessionConfiguration class];
        ZHNASwizzleClassMethod(cfgCls, @selector(defaultSessionConfiguration),
                               (IMP)new_defaultSessionConfiguration,
                               (IMP *)&orig_defaultSessionConfiguration);
        ZHNASwizzleClassMethod(cfgCls, @selector(ephemeralSessionConfiguration),
                               (IMP)new_ephemeralSessionConfiguration,
                               (IMP *)&orig_ephemeralSessionConfiguration);

        Class sessionCls = [NSURLSession class];
        ZHNASwizzleClassMethod(sessionCls, @selector(sessionWithConfiguration:),
                               (IMP)new_sessionWithConfiguration,
                               (IMP *)&orig_sessionWithConfiguration);
        ZHNASwizzleClassMethod(sessionCls, @selector(sessionWithConfiguration:delegate:delegateQueue:),
                               (IMP)new_sessionWithConfigurationDelegate,
                               (IMP *)&orig_sessionWithConfigurationDelegate);

        // 3) JSON 清洗
        ZHNASwizzleClassMethod([NSJSONSerialization class],
                               @selector(JSONObjectWithData:options:error:),
                               (IMP)new_JSONObjectWithData,
                               (IMP *)&orig_JSONObjectWithData);

        ZHNALog(@"网络层拦截已安装");
    });
}
