//
//  ZHNACommon.m
//

#import "ZHNACommon.h"
#import "ZHNAConfig.h"

#pragma mark - 日志

static NSMutableArray<NSString *> *ZHNALogBuf(void) {
    static NSMutableArray *buf;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ buf = [NSMutableArray arrayWithCapacity:512]; });
    return buf;
}

static NSObject *ZHNALogLock(void) {
    static NSObject *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSObject new]; });
    return lock;
}

void ZHNALogImpl(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    static NSDateFormatter *df;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
        df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });

    NSString *line;
    @synchronized (ZHNALogLock()) {
        line = [NSString stringWithFormat:@"[%@] %@", [df stringFromDate:[NSDate date]], body];
        NSMutableArray *buf = ZHNALogBuf();
        [buf addObject:line];
        if (buf.count > 500) {
            [buf removeObjectsInRange:NSMakeRange(0, buf.count - 500)];
        }
    }

    if (ZHNAConfigBool(ZHNAKeyDebug)) {
        NSLog(@"[ZhihuNoAds] %@", body);
    }
}

NSArray<NSString *> *ZHNALogSnapshot(void) {
    @synchronized (ZHNALogLock()) {
        return [ZHNALogBuf() copy];
    }
}

void ZHNALogClear(void) {
    @synchronized (ZHNALogLock()) {
        [ZHNALogBuf() removeAllObjects];
    }
}

NSString *ZHNALogExport(void) {
    NSArray<NSString *> *lines = ZHNALogSnapshot();
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"%@ v%@ 诊断日志\n", ZHNA_DISPLAY_NAME, ZHNA_VERSION];
    [text appendFormat:@"导出时间: %@\n", [NSDate date]];
    [text appendFormat:@"宿主: %@ (%@)\n",
        [[NSBundle mainBundle] bundleIdentifier] ?: @"?",
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"];
    [text appendFormat:@"系统: %@\n", [[NSProcessInfo processInfo] operatingSystemVersionString]];
    [text appendString:@"\n===== 拦截统计 =====\n"];

    NSDictionary *stats = ZHNAStatsSnapshot();
    NSArray *keys = [stats.allKeys sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *k in keys) {
        [text appendFormat:@"%@ : %@\n", k, stats[k]];
    }

    [text appendString:@"\n===== 最近日志 =====\n"];
    for (NSString *l in lines) {
        [text appendFormat:@"%@\n", l];
    }

    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    if (docs.count == 0) return nil;
    NSString *path = [docs.firstObject stringByAppendingPathComponent:@"ZhihuNoAds-诊断日志.txt"];
    NSError *err = nil;
    if (![text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&err]) {
        return nil;
    }
    return path;
}

#pragma mark - 统计

static NSMutableDictionary<NSString *, NSNumber *> *ZHNAStatsDict(void) {
    static NSMutableDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [NSMutableDictionary dictionary]; });
    return d;
}

void ZHNACountBy(NSString *key, NSInteger delta) {
    if (key.length == 0 || delta == 0) return;
    @synchronized (ZHNAStatsDict()) {
        NSMutableDictionary<NSString *, NSNumber *> *d = ZHNAStatsDict();
        NSNumber *old = d[key];
        d[key] = @(old.integerValue + delta);
    }
}

void ZHNACount(NSString *key) { ZHNACountBy(key, 1); }

NSDictionary<NSString *, NSNumber *> *ZHNAStatsSnapshot(void) {
    @synchronized (ZHNAStatsDict()) {
        return [ZHNAStatsDict() copy];
    }
}

NSInteger ZHNAStatsTotal(void) {
    NSInteger total = 0;
    for (NSNumber *n in ZHNAStatsSnapshot().allValues) total += n.integerValue;
    return total;
}

void ZHNAStatsReset(void) {
    @synchronized (ZHNAStatsDict()) {
        [ZHNAStatsDict() removeAllObjects];
    }
}
