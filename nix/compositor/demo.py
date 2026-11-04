#!/usr/bin/env python3
"""A live, keyboard-driven client displayed by Foot in the nested compositor."""
import math
import os
import select
import shutil
import sys
import termios
import time
import tty


def main():
    original = termios.tcgetattr(sys.stdin)
    phase = 0.0
    paused = False
    typed = ""
    started = time.monotonic()
    try:
        tty.setcbreak(sys.stdin)
        sys.stdout.write("\033[?25l\033[2J")
        while True:
            width, height = shutil.get_terminal_size((80, 30))
            canvas_width = max(8, min(width - 4, 90))
            canvas_height = max(3, min(height - 11, 35))
            lines = [
                "\033[1;38;2;220;205;240mohmansy live surface\033[0m",
                "", "A real Wayland client, updating 20 times per second.",
                "Space: pause    Type: see keyboard input    Esc: quit", "",
            ]
            for y in range(canvas_height):
                row = []
                for x in range(canvas_width):
                    v = math.sin(x * 0.12 + phase) * math.cos(y * 0.18 - phase * 0.7)
                    red = int(75 + 45 * (v + 1))
                    green = int(45 + 28 * (math.sin(v + phase) + 1))
                    blue = int(105 + 65 * (v + 1))
                    row.append(f"\033[48;2;{red};{green};{blue}m ")
                lines.append("".join(row) + "\033[0m")
            lines += ["", f"Running: {time.monotonic() - started:6.1f}s   {'Paused' if paused else 'Animating'}", "Input: " + typed[-max(1, width - 10):], "", os.environ.get("OHMANSY_COMPOSITOR_MODIFIER", "Super+Alt") + "+Enter terminal | H/L focus | S scale"]
            sys.stdout.write("\033[H" + "\033[K\r\n".join(lines) + "\033[J")
            sys.stdout.flush()
            if select.select([sys.stdin], [], [], 0.05)[0]:
                key = os.read(sys.stdin.fileno(), 64)
                if key == b"\x1b":
                    break
                if key == b" ":
                    paused = not paused
                elif key in (b"\x7f", b"\x08"):
                    typed = typed[:-1]
                else:
                    typed += key.decode(errors="replace").replace("\r", " ").replace("\n", " ")
            if not paused:
                phase += 0.055
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, original)
        sys.stdout.write("\033[0m\033[?25h\r\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
