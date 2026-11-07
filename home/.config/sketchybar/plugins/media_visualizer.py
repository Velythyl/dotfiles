#!/usr/bin/env python3
"""Render a low-rate Cava spectrum into SketchyBar background images.

The process exists only while playback is active. It uses Cava's Core Audio tap
and raw ASCII output, then writes a handful of tiny PNGs with the Python
standard library. Alternating between two filename sets makes SketchyBar reload
each image without generating unbounded temporary files.
"""

from __future__ import annotations

import os
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import zlib
from pathlib import Path

FPS = 5
DOTS_HIGH = 4
# Each 24pt transport item has a 22pt visible background (1pt inset on each
# side). These must match the background faces, not the wider hit targets.
BUTTON_WIDTH = 22
IMAGE_HEIGHT = 20
BUTTON_BARS = 3
TOTAL_BARS = BUTTON_BARS * 3
# Gruvbox blue (kitty color4). It is darker than the light transport faces and
# intentionally distinct from the title's CLR_FG text colour.
VISUALIZER = (69, 133, 136, 255)
TRANSPARENT = (0, 0, 0, 0)

runtime_dir = Path(os.environ.get("TMPDIR", "/tmp")) / "sketchybar-media"
pid_file = runtime_dir / "visualizer.pid"
config_file = runtime_dir / "cava.conf"
log_file = runtime_dir / "visualizer.log"
items = ("media_previous", "media_toggle", "media_next")


def sketchybar_bin() -> str:
    return os.environ.get("SKETCHYBAR_BIN") or shutil.which("sketchybar") or "/opt/homebrew/bin/sketchybar"


def cava_bin() -> str:
    override = os.environ.get("CAVA_BIN")
    if override:
        return override
    # Homebrew's Cava 1.0.0 calls a private TCC preflight which reports a
    # false denial for Audio Capture on current macOS releases, including when
    # launched by SketchyBar.  `cava-audiotap-install` builds a copy that lets
    # Core Audio perform the real access check instead.
    patched = Path.home() / ".local/opt/cava-audiotap/bin/cava"
    if patched.is_file() and os.access(patched, os.X_OK):
        return str(patched)
    return shutil.which("cava") or "/opt/homebrew/bin/cava"


def process_is_running(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def is_our_helper(pid: int) -> bool:
    """Avoid signalling an unrelated process if a stale PID was reused."""
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "command="],
        capture_output=True,
        text=True,
        check=False,
    )
    command = result.stdout.strip()
    return str(Path(__file__).resolve()) in command and " run" in command


def running_pid() -> int | None:
    try:
        pid = int(pid_file.read_text().strip())
    except (OSError, ValueError):
        return None
    if process_is_running(pid) and is_our_helper(pid):
        return pid
    try:
        pid_file.unlink()
    except OSError:
        pass
    return None


def log(message: str) -> None:
    """Keep Cava diagnostics available without sending output to the bar."""
    try:
        if log_file.exists() and log_file.stat().st_size > 16_384:
            log_file.unlink()
        with log_file.open("a") as handle:
            handle.write(f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message}\n")
    except OSError:
        pass


def set_images_drawing(drawing: bool) -> None:
    command = [sketchybar_bin()]
    for item in items:
        command.extend(("--set", item, f"background.image.drawing={'on' if drawing else 'off'}"))
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def clear_images() -> None:
    set_images_drawing(False)


def write_png(path: Path, width: int, height: int, pixels: bytearray) -> None:
    raw = bytearray()
    row_width = width * 4
    for y in range(height):
        raw.append(0)  # PNG filter: none
        start = y * row_width
        raw.extend(pixels[start : start + row_width])

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), level=1))
    png += chunk(b"IEND", b"")
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_bytes(png)
    temporary.replace(path)


def draw_dot(pixels: bytearray, width: int, center_x: int, center_y: int, colour: tuple[int, int, int, int]) -> None:
    # A two-pixel-wide rounded dot remains crisp in the 20pt menu bar.
    for y in range(center_y - 1, center_y + 2):
        for x in range(center_x - 1, center_x + 2):
            if x < 0 or x >= width or y < 0 or y >= IMAGE_HEIGHT:
                continue
            if (x - center_x) ** 2 + (y - center_y) ** 2 > 2:
                continue
            offset = (y * width + x) * 4
            pixels[offset : offset + 4] = bytes(colour)


def render_region(path: Path, width: int, values: list[int], colour: tuple[int, int, int, int]) -> None:
    pixels = bytearray(TRANSPARENT * (width * IMAGE_HEIGHT))
    count = len(values)
    for index, level in enumerate(values):
        center_x = max(1, min(width - 2, round((index + 0.5) * width / count)))
        for dot in range(max(0, min(DOTS_HIGH, level))):
            center_y = IMAGE_HEIGHT - 3 - (dot * 4)
            draw_dot(pixels, width, center_x, center_y, colour)
    write_png(path, width, IMAGE_HEIGHT, pixels)


def render_frame(values: list[int], slot: int) -> None:
    regions = (
        ("previous", BUTTON_WIDTH, values[:BUTTON_BARS], VISUALIZER),
        ("toggle", BUTTON_WIDTH, values[BUTTON_BARS : BUTTON_BARS * 2], VISUALIZER),
        ("next", BUTTON_WIDTH, values[BUTTON_BARS * 2 :], VISUALIZER),
    )
    paths: list[Path] = []
    for name, width, region_values, colour in regions:
        path = runtime_dir / f"{name}-{slot}.png"
        render_region(path, width, region_values, colour)
        paths.append(path)

    command = [sketchybar_bin()]
    for item, path in zip(items, paths):
        command.extend(("--set", item, f"background.image={path}", "background.image.drawing=on"))
    subprocess.run(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)


def write_cava_config() -> None:
    config_file.write_text(
        "[general]\n"
        f"framerate = {FPS}\n"
        f"bars = {TOTAL_BARS}\n"
        "autosens = 1\n"
        "sensitivity = 100\n"
        "lower_cutoff_freq = 50\n"
        "higher_cutoff_freq = 10000\n\n"
        "[input]\n"
        "method = coreaudio\n"
        "source = tap\n\n"
        "[output]\n"
        "method = raw\n"
        "channels = mono\n"
        "mono_option = average\n"
        "raw_target = /dev/stdout\n"
        "data_format = ascii\n"
        f"ascii_max_range = {DOTS_HIGH}\n"
        "bar_delimiter = 59\n"
        "frame_delimiter = 10\n\n"
        "[smoothing]\n"
        "integral = 0.65\n"
        "monstercat = 0\n"
        "gravity = 1\n"
    )


def parse_frame(line: str) -> list[int] | None:
    try:
        values = [int(value) for value in line.strip().split(";") if value]
    except ValueError:
        return None
    if len(values) != TOTAL_BARS:
        return None
    return [max(0, min(DOTS_HIGH, value)) for value in values]


def remove_own_pid() -> None:
    try:
        if pid_file.read_text().strip() == str(os.getpid()):
            pid_file.unlink()
    except OSError:
        pass


def run() -> int:
    runtime_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    pid_file.write_text(f"{os.getpid()}\n")
    write_cava_config()
    process: subprocess.Popen[str] | None = None
    cava_stderr = None

    def shutdown(_signum: int, _frame: object) -> None:
        if process is not None and process.poll() is None:
            process.terminate()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    try:
        cava_stderr = log_file.open("a")
        try:
            process = subprocess.Popen(
                [cava_bin(), "-p", str(config_file)],
                stdout=subprocess.PIPE,
                stderr=cava_stderr,
                text=True,
                bufsize=1,
            )
        except OSError as error:
            log(f"could not start Cava: {error}")
            return 1
        assert process.stdout is not None
        slot = 0
        for line in process.stdout:
            values = parse_frame(line)
            if values is None:
                continue
            render_frame(values, slot)
            slot = 1 - slot
        if process.returncode not in (None, 0):
            log(f"Cava exited with status {process.returncode}")
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
        if cava_stderr is not None:
            cava_stderr.close()
        clear_images()
        remove_own_pid()
    return 0


def start() -> int:
    runtime_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if running_pid() is not None:
        return 0
    process = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "run"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    # Claim ownership before the child gets scheduled so a burst of media
    # events does not launch a second helper/Cava instance.
    pid_file.write_text(f"{process.pid}\n")
    return 0


def stop() -> int:
    pid = running_pid()
    if pid is not None:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            pass
        deadline = time.monotonic() + 1
        while process_is_running(pid) and time.monotonic() < deadline:
            time.sleep(0.02)
    clear_images()
    return 0


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in {"start", "stop", "run"}:
        print(f"usage: {Path(sys.argv[0]).name} start|stop|run", file=sys.stderr)
        return 2
    return {"start": start, "stop": stop, "run": run}[sys.argv[1]]()


if __name__ == "__main__":
    raise SystemExit(main())
