#import "ABMCLogger.h"
#include <stdarg.h>

static NSString *const ABMCPrimaryLogPath = @"/rootfs/var/tmp/RealActionButton.log";
static NSString *const ABMCFallbackLogPath = @"/var/tmp/RealActionButton.log";
static const NSTimeInterval ABMCLogLifetime = 24.0 * 60.0 * 60.0;

static NSString *ABMCLogPath(void) {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *parent = [ABMCPrimaryLogPath stringByDeletingLastPathComponent];
    if ([manager fileExistsAtPath:parent] || [manager createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:nil]) return ABMCPrimaryLogPath;
    return ABMCFallbackLogPath;
}

void ABMCLog(NSString *format, ...) {
    @autoreleasepool {
        NSString *path = ABMCLogPath();
        NSFileManager *manager = [NSFileManager defaultManager];
        NSDictionary *attributes = [manager attributesOfItemAtPath:path error:nil];
        NSDate *created = attributes[NSFileCreationDate] ?: attributes[NSFileModificationDate];
        if (created && [[NSDate date] timeIntervalSinceDate:created] >= ABMCLogLifetime) [manager removeItemAtPath:path error:nil];
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [[NSDate date] descriptionWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]], message];
        if (![manager fileExistsAtPath:path]) [line writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            [handle seekToEndOfFile];
            [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [handle closeFile];
        }
    }
}
