#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <sys/file.h>
#import <signal.h>
#import <errno.h>
#import <fcntl.h>

static BOOL alive(NSString *directory) {
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil]) {
        if (![name hasPrefix:@"inuse."] || ![name hasSuffix:@".lock"]) continue;
        NSString *text = [NSString stringWithContentsOfFile:[directory stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
        NSScanner *scanner = [NSScanner scannerWithString:text ?: @""];
        int pid = 0;
        if (![scanner scanInt:&pid] || !scanner.isAtEnd || pid <= 1) continue;
        if (kill(pid, 0) == 0 || errno == EPERM) return YES;
    }
    return NO;
}

@interface Session : NSObject
@property NSUInteger offset;
@property unsigned long long inode;
@property BOOL busy;
@property BOOL turnEnded;
@property (strong) NSMutableSet<NSString *> *waiting;
@property (strong) NSMutableSet<NSString *> *tools;
@property (strong) NSMutableSet<NSString *> *completedTools;
@property NSTimeInterval modified;
- (void)read:(NSString *)path;
@end
@implementation Session
- (instancetype)init {
    if ((self = [super init])) { _waiting = [NSMutableSet set]; _tools = [NSMutableSet set]; _completedTools = [NSMutableSet set]; }
    return self;
}
- (void)event:(NSDictionary *)event {
    NSString *type = event[@"type"];
    if (![type isKindOfClass:NSString.class]) return;
    NSDictionary *data = [event[@"data"] isKindOfClass:NSDictionary.class] ? event[@"data"] : @{};
    if ([type isEqual:@"user.message"] || [type isEqual:@"assistant.turn_start"]) {
        self.busy = YES; self.turnEnded = NO;
        if ([type isEqual:@"user.message"]) { [self.waiting removeAllObjects]; [self.tools removeAllObjects]; [self.completedTools removeAllObjects]; }
    } else if ([type isEqual:@"assistant.turn_end"]) {
        self.turnEnded = YES;
        if (!self.waiting.count && !self.tools.count) self.busy = NO;
    } else if ([@[@"session.idle", @"session.shutdown", @"session.error", @"abort"] containsObject:type]) {
        self.busy = NO; self.turnEnded = YES; [self.waiting removeAllObjects]; [self.tools removeAllObjects]; [self.completedTools removeAllObjects];
    } else if ([type isEqual:@"permission.requested"] || [type isEqual:@"permission.completed"]) {
        NSString *key = [data[@"requestId"] description];
        if (!key || [key isEqual:@"(null)"]) return;
        if ([type isEqual:@"permission.requested"]) [self.waiting addObject:key]; else [self.waiting removeObject:key];
        if (self.turnEnded && !self.waiting.count && !self.tools.count) self.busy = NO;
    } else if ([type isEqual:@"tool.execution_start"] || [type isEqual:@"external_tool.requested"] ||
               [type isEqual:@"tool.execution_complete"] || [type isEqual:@"external_tool.completed"]) {
        NSString *key = [data[@"toolCallId"] description] ?: [data[@"requestId"] description];
        if (!key) return;
        BOOL start = [type hasSuffix:@"start"] || [type hasSuffix:@"requested"];
        NSString *name = [[data[@"toolName"] description] componentsSeparatedByString:@"."].lastObject;
        if (start && [@[@"ask_user", @"ask_user_question", @"askUserQuestion", @"ask_user_input"] containsObject:name] && ![self.completedTools containsObject:key]) [self.tools addObject:key];
        if (!start) { [self.tools removeObject:key]; [self.completedTools addObject:key]; }
        if (self.turnEnded && !self.waiting.count && !self.tools.count) self.busy = NO;
    }
}
- (void)read:(NSString *)path {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    if (!attributes) return;
    unsigned long long inode = [attributes[NSFileSystemFileNumber] unsignedLongLongValue];
    NSUInteger size = [attributes[NSFileSize] unsignedIntegerValue];
    if (self.inode != inode || self.offset > size) {
        self.inode = inode; self.offset = 0; self.busy = NO; self.turnEnded = NO;
        [self.waiting removeAllObjects]; [self.tools removeAllObjects]; [self.completedTools removeAllObjects];
    }
    self.modified = [attributes[NSFileModificationDate] timeIntervalSince1970];
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:path];
    if (!handle) return;
    @try {
        [handle seekToFileOffset:self.offset];
        NSMutableData *buffer = [NSMutableData data];
        while (YES) {
            NSData *chunk = [handle readDataOfLength:65536];
            if (!chunk.length) break;
            [buffer appendData:chunk];
            const char *bytes = buffer.bytes;
            NSUInteger from = 0;
            for (NSUInteger i = 0; i < buffer.length; i++) {
                if (bytes[i] != '\n') continue;
                NSData *line = [buffer subdataWithRange:NSMakeRange(from, i - from)];
                NSDictionary *event = [NSJSONSerialization JSONObjectWithData:line options:0 error:nil];
                if ([event isKindOfClass:NSDictionary.class]) [self event:event];
                from = i + 1;
            }
            self.offset += from;
            if (from) [buffer replaceBytesInRange:NSMakeRange(0, from) withBytes:NULL length:0];
            if (buffer.length > 4 * 1024 * 1024) break;
        }
    } @catch (NSException *exception) { /* A concurrent session write can make a read fail; retry on the next tick. */ }
    [handle closeFile];
}
@end

@interface Monitor : NSObject
@property (strong) NSMutableDictionary<NSString *, Session *> *sessions;
@property (copy) NSString *root;
@property (strong) NSArray<NSString *> *working;
@property (strong) NSArray<NSString *> *waiting;
- (instancetype)initWithRoot:(NSString *)root;
- (void)scan;
@end
@implementation Monitor
- (instancetype)initWithRoot:(NSString *)root {
    if ((self = [super init])) { _root = [root copy]; _sessions = [NSMutableDictionary dictionary]; _working = @[]; _waiting = @[]; }
    return self;
}
- (void)scan {
    NSMutableDictionary *live = [NSMutableDictionary dictionary];
    NSMutableArray *working = [NSMutableArray array], *waiting = [NSMutableArray array];
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.root error:nil]) {
        NSString *directory = [self.root stringByAppendingPathComponent:name];
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory || !alive(directory)) continue;
        NSString *path = [directory stringByAppendingPathComponent:@"events.jsonl"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        Session *session = self.sessions[name] ?: [Session new];
        [session read:path]; live[name] = session;
        if (session.busy) {
            if (session.waiting.count || session.tools.count) [waiting addObject:name];
            else if (now - session.modified < 3600) [working addObject:name];
        }
    }
    self.sessions = live;
    self.working = [working sortedArrayUsingSelector:@selector(compare:)];
    self.waiting = [waiting sortedArrayUsingSelector:@selector(compare:)];
}
@end

static BOOL shouldExit(NSTimeInterval now, NSTimeInterval started, NSTimeInterval lastActive, NSUInteger count) {
    return count == 0 && now - started > 18 && now - lastActive > 12;
}

@interface App : NSObject <NSApplicationDelegate>
@property (strong) Monitor *monitor;
@property (strong) NSStatusItem *item;
@property (strong) NSTimer *timer;
@property NSTimeInterval lastActive;
@property NSTimeInterval started;
@property (copy) NSString *cache;
@end
@implementation App
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *home = NSProcessInfo.processInfo.environment[@"COPILOT_HOME"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@".copilot"];
    self.monitor = [[Monitor alloc] initWithRoot:[home stringByAppendingPathComponent:@"session-state"]];
    self.cache = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/amphetamine-helper"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.cache withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    self.item = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.started = NSDate.date.timeIntervalSince1970; self.lastActive = self.started;
    [self tick:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
}
- (void)tick:(NSTimer *)timer {
    [self.monitor scan];
    NSUInteger count = self.monitor.working.count + self.monitor.waiting.count;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    if (count) self.lastActive = now;
    NSDictionary *status = @{ @"working": @(self.monitor.working.count), @"waiting": @(self.monitor.waiting.count), @"active": @(count) };
    NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
    [json writeToFile:[self.cache stringByAppendingPathComponent:@"status.json"] atomically:YES];
    self.item.button.title = [NSString stringWithFormat:@"☕ %lu", (unsigned long)count];
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:[NSString stringWithFormat:@"Working: %lu · Awaiting input: %lu", (unsigned long)self.monitor.working.count, (unsigned long)self.monitor.waiting.count] action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    for (NSString *name in self.monitor.working) [menu addItemWithTitle:[NSString stringWithFormat:@"Working · %@", [name substringToIndex:MIN(8, name.length)]] action:nil keyEquivalent:@""];
    for (NSString *name in self.monitor.waiting) [menu addItemWithTitle:[NSString stringWithFormat:@"Awaiting input · %@", [name substringToIndex:MIN(8, name.length)]] action:nil keyEquivalent:@""];
    if (!count) [menu addItemWithTitle:@"No active Copilot sessions" action:nil keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quit = [menu addItemWithTitle:@"Quit Amphetamine Helper" action:@selector(terminate:) keyEquivalent:@""];
    quit.target = NSApp;
    self.item.menu = menu;
    if (shouldExit(now, self.started, self.lastActive, count)) {
        [NSApp terminate:nil];
        return;
    }
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 4 && strcmp(argv[1], "--lifecycle") == 0) {
            NSTimeInterval started = atof(argv[2]);
            NSTimeInterval lastActive = atof(argv[3]);
            printf("%d\n", shouldExit(100, started, lastActive, 0));
            return 0;
        }
        if (argc == 3 && strcmp(argv[1], "--inspect") == 0) {
            Monitor *monitor = [[Monitor alloc] initWithRoot:[NSString stringWithUTF8String:argv[2]]];
            [monitor scan];
            NSDictionary *result = @{ @"working": monitor.working, @"waiting": monitor.waiting };
            NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
            fwrite(json.bytes, 1, json.length, stdout); fputc('\n', stdout);
            return 0;
        }
        NSString *cache = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/amphetamine-helper"];
        [[NSFileManager defaultManager] createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
        NSString *lock = [cache stringByAppendingPathComponent:@"run.lock"];
        int fd = open(lock.fileSystemRepresentation, O_CREAT | O_RDWR, 0600);
        if (fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0) return 0;
        [NSApplication sharedApplication];
        NSApp.activationPolicy = NSApplicationActivationPolicyAccessory;
        App *app = [App new];
        NSApp.delegate = app;
        [NSApp run];
        return 0;
    }
}
