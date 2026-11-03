"""Text clipboard bridge for the app-owned virtio port. Never logs clipboard data."""
import json
import os
import selectors
import signal
import subprocess
import sys
import time

PORT = '/dev/virtio-ports/dev.ohmansy.clipboard'
TEXT_LIMIT = 1024 * 1024
FRAME_LIMIT = 6 * TEXT_LIMIT + 128


def encode(message):
    return (json.dumps(message, ensure_ascii=True) + '\n').encode()


def decode(line):
    if len(line) > FRAME_LIMIT:
        raise ValueError('Oversized frame')
    message = json.loads(line)
    if not isinstance(message, dict):
        raise ValueError('Invalid frame')
    if 'text' in message:
        if not isinstance(message['text'], str) or len(message['text'].encode('utf-8')) > TEXT_LIMIT:
            raise ValueError('Invalid text')
    return message


def capture():
    # wl-paste launches this for each selection; unsupported formats stay local.
    data = sys.stdin.buffer.read(TEXT_LIMIT + 1)
    if os.environ.get('CLIPBOARD_STATE') in ('nil', 'clear', 'sensitive') or len(data) > TEXT_LIMIT:
        return
    try:
        sys.stdout.buffer.write(encode({'text': data.decode('utf-8')}))
        sys.stdout.buffer.flush()
    except UnicodeError:
        pass


def session(fd):
    selector = selectors.DefaultSelector()
    selector.register(fd, selectors.EVENT_READ)
    buffers = {fd: bytearray()}
    outgoing = bytearray(encode({'ready': True}))
    watcher = None
    copied = None
    try:
        while True:
            selector.modify(fd, selectors.EVENT_READ | (selectors.EVENT_WRITE if outgoing else 0))
            for key, events in selector.select(timeout=1):
                if key.fd == fd and events & selectors.EVENT_WRITE:
                    try:
                        del outgoing[:os.write(fd, outgoing)]
                    except BlockingIOError:
                        pass
                if not events & selectors.EVENT_READ:
                    continue
                try:
                    chunk = os.read(key.fd, 65536)
                except BlockingIOError:
                    continue
                if not chunk:
                    raise OSError('Clipboard peer closed')
                buffer = buffers[key.fd]
                buffer.extend(chunk)
                if len(buffer) > FRAME_LIMIT:
                    raise ValueError('Oversized clipboard frame')
                while b'\n' in buffer:
                    line, _, rest = buffer.partition(b'\n')
                    buffer[:] = rest
                    message = decode(line)
                    if key.fd == fd:
                        if message.get('hello') is True:
                            outgoing.extend(encode({'ready': True}))
                        if 'text' in message:
                            copied = message['text']
                            subprocess.run(['wl-copy', '--type', 'text/plain;charset=utf-8'],
                                           input=copied.encode(), check=True, timeout=5,
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                        if message.get('start') is True and watcher is None:
                            watcher = subprocess.Popen(['wl-paste', '--type', 'text', '--no-newline', '--watch',
                                                        sys.executable, __file__, '--capture'],
                                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
                            os.set_blocking(watcher.stdout.fileno(), False)
                            buffers[watcher.stdout.fileno()] = bytearray()
                            selector.register(watcher.stdout, selectors.EVENT_READ)
                    elif 'text' in message and message['text'] != copied:
                        copied = message['text']
                        outgoing.extend(encode(message))
                    if len(outgoing) > FRAME_LIMIT * 2:
                        raise ValueError('Clipboard peer is too slow')
    finally:
        if watcher:
            watcher.terminate()
            try:
                watcher.wait(timeout=2)
            except subprocess.TimeoutExpired:
                watcher.kill()
                watcher.wait()
        try:
            os.write(fd, encode({'bye': True}))
        except OSError:
            pass
        selector.close()


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        try:
            fd = os.open(PORT, os.O_RDWR | os.O_NONBLOCK | os.O_NOCTTY)
            try:
                session(fd)
            finally:
                os.close(fd)
        except (OSError, ValueError, UnicodeError, subprocess.SubprocessError):
            # No active host bridge, permissions not ready, or malformed input.
            time.sleep(1)


if __name__ == '__main__':
    if sys.argv[1:] == ['--capture']:
        capture()
    else:
        main()
