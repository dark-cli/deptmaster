#!/usr/bin/env python3
"""
Unified log viewer for multiple Flutter app instances.
Fixed status bar at top; log area below; switch instance with 1-9, quit with q.
Reads keys from /dev/tty so switching works when run from scripts.
Usage: multi_instance_log_viewer.py --log-dir DIR --count N [--pids-file FILE]
"""

import argparse
import os
import sys
import time

try:
    import curses
except ImportError:
    curses = None

STATUS_BAR_FORMAT = (
    " [ Instances: {running}/{total} running, {stopped} stopped | "
    "Watching: Instance {watching} | Keys: 1-{max_key} switch, q quit ] "
)


def count_running(pids_file: str) -> int:
    if not pids_file or not os.path.isfile(pids_file):
        return 0
    try:
        with open(pids_file) as f:
            pids = [int(line.strip()) for line in f if line.strip().isdigit()]
        return sum(1 for p in pids if _process_exists(p))
    except (ValueError, OSError):
        return 0


def _process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def read_new_lines(path: str, position: int) -> tuple[str, int]:
    if not os.path.isfile(path):
        return "", position
    try:
        with open(path) as f:
            f.seek(position)
            data = f.read()
            new_pos = f.tell()
            return data, new_pos
    except OSError:
        return "", position


def run_curses(stdscr, log_dir: str, count: int, pids_file: str) -> int:
    curses.curs_set(0)
    # Short timeout so keypresses feel instant (important in tmux)
    stdscr.timeout(15)
    height, width = stdscr.getmaxyx()
    if height < 3:
        return 1
    # Status bar is line 0; log area is lines 1..height-1
    # Per-instance log buffers so switching shows the right content immediately
    instance_buffers: dict[int, list[str]] = {i: [] for i in range(1, count + 1)}
    current = 1
    file_positions: dict[int, int] = {}
    log_start_row = 1
    log_height = height - 1
    status_redraw_counter = 0

    def draw_status_bar() -> None:
        running = count_running(pids_file)
        stopped = count - running
        line = STATUS_BAR_FORMAT.format(
            running=running,
            total=count,
            stopped=stopped,
            watching=current,
            max_key=count,
        )
        stdscr.attron(curses.A_REVERSE)
        stdscr.move(0, 0)
        stdscr.clrtoeol()
        stdscr.addstr(0, 0, line[: width - 1])
        stdscr.attroff(curses.A_REVERSE)
        stdscr.refresh()

    def draw_log(buf: list[str]) -> None:
        for r in range(log_start_row, height):
            stdscr.move(r, 0)
            stdscr.clrtoeol()
        visible = buf[-log_height:] if len(buf) > log_height else buf
        for i, line in enumerate(visible):
            row = log_start_row + i
            if row >= height:
                break
            text = (line.rstrip("\n\r") + "\n")[: width - 1]
            try:
                stdscr.addstr(row, 0, text)
            except curses.error:
                pass
        stdscr.refresh()

    def load_entire_log(instance: int) -> None:
        path = os.path.join(log_dir, f"instance_{instance}.log")
        if not os.path.isfile(path):
            return
        try:
            with open(path) as f:
                content = f.read()
            file_positions[instance] = len(content)
            instance_buffers[instance] = content.splitlines(keepends=True)
        except OSError:
            pass

    draw_status_bar()
    load_entire_log(1)
    draw_log(instance_buffers[current])

    while True:
        try:
            ch = stdscr.getch()
        except curses.error:
            ch = -1
        if ch == ord("q") or ch == ord("Q") or ch == 4:
            return 0
        if ch >= ord("1") and ch <= ord("9"):
            idx = ch - ord("0")
            if 1 <= idx <= count and idx != current:
                current = idx
                if not instance_buffers[current]:
                    load_entire_log(current)
                draw_status_bar()
                draw_log(instance_buffers[current])
                status_redraw_counter = 0
                continue
        # Append new content from current instance log
        path = os.path.join(log_dir, f"instance_{current}.log")
        pos = file_positions.get(current, 0)
        new_text, new_pos = read_new_lines(path, pos)
        file_positions[current] = new_pos
        if new_text:
            for line in new_text.splitlines(keepends=True):
                instance_buffers[current].append(line)
            draw_log(instance_buffers[current])
        status_redraw_counter += 1
        if status_redraw_counter >= 40:
            status_redraw_counter = 0
            draw_status_bar()
    return 0


def run_fallback(log_dir: str, count: int, pids_file: str) -> int:
    """Fallback when curses not available: print bar once, tail one log, no key switch."""
    current = 1
    file_positions: dict[int, int] = {}
    running = count_running(pids_file)
    stopped = count - running
    line = STATUS_BAR_FORMAT.format(
        running=running, total=count, stopped=stopped, watching=current, max_key=count
    )
    sys.stdout.write(line + "\n")
    sys.stdout.flush()
    while True:
        path = os.path.join(log_dir, f"instance_{current}.log")
        pos = file_positions.get(current, 0)
        new_text, new_pos = read_new_lines(path, pos)
        file_positions[current] = new_pos
        if new_text:
            sys.stdout.write(new_text)
            sys.stdout.flush()
        time.sleep(0.2)


def main() -> int:
    parser = argparse.ArgumentParser(description="Multi-instance log viewer")
    parser.add_argument("--log-dir", required=True, help="Directory containing instance_1.log, ...")
    parser.add_argument("--count", type=int, required=True, help="Number of instances (1-9)")
    parser.add_argument("--pids-file", default="", help="File with one PID per line")
    args = parser.parse_args()

    if args.count < 1 or args.count > 9:
        print("Count must be 1-9", file=sys.stderr)
        return 1
    if not os.path.isdir(args.log_dir):
        print(f"Log dir not found: {args.log_dir}", file=sys.stderr)
        return 1

    if curses is not None and sys.stdout.isatty():
        return curses.wrapper(run_curses, args.log_dir, args.count, args.pids_file)
    return run_fallback(args.log_dir, args.count, args.pids_file)


if __name__ == "__main__":
    sys.exit(main())
