#import "../../native/ClipboardBridge.m"
#include <assert.h>
int main(void) {
    @autoreleasepool {
        OhmansyClipboardBridge *bridge = [[OhmansyClipboardBridge alloc] initWithSocket:@""];
        bridge.pasteboard = [NSPasteboard pasteboardWithUniqueName];
        [bridge.pasteboard setString:@"Mac → guest\nhello" forType:NSPasteboardTypeString];
        int pair[2]; assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
        fcntl(pair[0], F_SETFL, O_NONBLOCK); fcntl(pair[1], F_SETFL, O_NONBLOCK);
        bridge.fd = pair[0];
        write(pair[1], "{\"ready\":", 9); [bridge tick]; assert(!bridge.ready);
        write(pair[1], "true}\n", 6); [bridge tick]; assert(bridge.ready);
        char bytes[4096]; ssize_t size = read(pair[1], bytes, sizeof(bytes)); assert(size > 0);
        NSString *sent = [[NSString alloc] initWithBytes:bytes length:size encoding:NSUTF8StringEncoding];
        NSDictionary *message = [NSJSONSerialization JSONObjectWithData:[[sent componentsSeparatedByString:@"\n"][0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        assert([message[@"text"] isEqual:@"Mac → guest\nhello"]);
        NSData *reply = [@"{\"text\":\"Guest → Mac\\nhello\"}\n" dataUsingEncoding:NSUTF8StringEncoding];
        write(pair[1], reply.bytes, reply.length); [bridge tick];
        assert([[bridge.pasteboard stringForType:NSPasteboardTypeString] isEqual:@"Guest → Mac\nhello"]);
        assert(read(pair[1], bytes, sizeof(bytes)) == -1); // no echo
        write(pair[1], "{\"bye\":true}\n", 13); [bridge tick]; assert(!bridge.ready);
        [bridge.pasteboard clearContents]; [bridge.pasteboard setString:@"private while logged out" forType:NSPasteboardTypeString];
        [bridge tick]; assert(read(pair[1], bytes, sizeof(bytes)) == -1);
        write(pair[1], "[]\n", 3); [bridge tick]; assert(bridge.fd == -1);
        close(pair[1]); [bridge.pasteboard releaseGlobally];
        puts("Clipboard bridge passed: framing, Unicode, both directions, no echo, session stop, malformed input.");
    }
}
