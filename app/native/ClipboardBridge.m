#import "ClipboardBridge.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

static const NSUInteger TextLimit = 1024 * 1024;
static const NSUInteger FrameLimit = 6 * 1024 * 1024 + 128;

@interface OhmansyClipboardBridge ()
@property(nonatomic, copy) NSString *path;
@property(nonatomic) int fd;
@property(nonatomic) BOOL ready;
@property(nonatomic) NSInteger changeCount;
@property(nonatomic, strong) NSMutableData *incoming;
@property(nonatomic, strong) NSMutableData *outgoing;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, strong) NSPasteboard *pasteboard;
@end

@implementation OhmansyClipboardBridge
- (instancetype)initWithSocket:(NSString *)path {
    if ((self = [super init])) {
        _path = [path copy]; _fd = -1;
        _pasteboard = NSPasteboard.generalPasteboard;
        _incoming = [NSMutableData data]; _outgoing = [NSMutableData data];
    }
    return self;
}
- (void)disconnect {
    if (_fd >= 0) close(_fd);
    _fd = -1; _ready = NO;
    [_incoming setLength:0]; [_outgoing setLength:0];
}
- (void)start {
    if (!_path.length || _timer) return;
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer *timer) {
        [weakSelf tick];
    }];
}
- (void)enqueue:(NSDictionary *)message {
    NSData *data = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!data || data.length > FrameLimit || _outgoing.length + data.length > FrameLimit * 2) {
        [self disconnect]; return;
    }
    [_outgoing appendData:data]; [_outgoing appendBytes:"\n" length:1];
}
- (void)sendClipboard {
    NSPasteboard *board = _pasteboard;
    NSString *text = [board stringForType:NSPasteboardTypeString];
    _changeCount = board.changeCount;
    if (text && [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= TextLimit)
        [self enqueue:@{@"text":text}];
}
- (void)receive:(NSData *)data {
    id message = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![message isKindOfClass:NSDictionary.class]) { [self disconnect]; return; }
    if ([message[@"ready"] isEqual:@YES]) {
        _ready = YES;
        [self sendClipboard];
        [self enqueue:@{@"start":@YES}];
    } else if ([message[@"bye"] isEqual:@YES]) {
        _ready = NO; [_outgoing setLength:0];
    } else if (_ready && [message[@"text"] isKindOfClass:NSString.class]) {
        NSString *text = message[@"text"];
        if ([text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > TextLimit) { [self disconnect]; return; }
        NSPasteboard *board = _pasteboard;
        [board clearContents];
        [board setString:text forType:NSPasteboardTypeString];
        _changeCount = board.changeCount; // Do not echo a guest selection back.
    }
}
- (void)tick {
    if (_fd < 0) {
        struct sockaddr_un address = { .sun_family = AF_UNIX };
        if ([_path lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >= sizeof(address.sun_path)) return;
        strlcpy(address.sun_path, _path.fileSystemRepresentation, sizeof(address.sun_path));
        _fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (_fd < 0) return;
        fcntl(_fd, F_SETFL, O_NONBLOCK);
        int one = 1; setsockopt(_fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof(one));
        if (connect(_fd, (struct sockaddr *)&address, sizeof(address)) < 0) { [self disconnect]; return; }
        // The guest replies only while its desktop session is running.
        [self enqueue:@{@"hello":@YES}];
    }
    char buffer[65536];
    for (int i = 0; i < 16; i++) {
        ssize_t count = read(_fd, buffer, sizeof(buffer));
        if (count == 0) { [self disconnect]; return; }
        if (count < 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) [self disconnect];
            break;
        }
        [_incoming appendBytes:buffer length:(NSUInteger)count];
        if (_incoming.length > FrameLimit) { [self disconnect]; return; }
        NSRange newline;
        while ((newline = [_incoming rangeOfData:[NSData dataWithBytes:"\n" length:1] options:0 range:NSMakeRange(0, _incoming.length)]).location != NSNotFound) {
            NSData *frame = [_incoming subdataWithRange:NSMakeRange(0, newline.location)];
            [_incoming replaceBytesInRange:NSMakeRange(0, newline.location + 1) withBytes:NULL length:0];
            [self receive:frame];
            if (_fd < 0) return;
        }
    }
    if (_ready && !_outgoing.length && _pasteboard.changeCount != _changeCount)
        [self sendClipboard];
    if (_outgoing.length && _fd >= 0) {
        ssize_t count = write(_fd, _outgoing.bytes, _outgoing.length);
        if (count > 0) [_outgoing replaceBytesInRange:NSMakeRange(0, (NSUInteger)count) withBytes:NULL length:0];
        else if (count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR) [self disconnect];
    }
}
@end
