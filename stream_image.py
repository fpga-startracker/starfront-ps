#!/usr/bin/env python3
"""
stream_image.py - Real Star Tracker Image Streamer over UDP to FPGA
-------------------------------------------------------------------
Loads real image files (PNG, JPG, BMP, TIFF, etc.) or folders of images,
automatically formats/resizes them to 640x480 RGB565 (or Grayscale),
and streams them over Ethernet UDP to the ALINX AX7010 Zynq FPGA.

The hardware receives the pixels via AXI4-Stream, stores them in the framebuffer,
runs the real-time centroid detector, and displays the image + crosshairs on HDMI!

Usage Examples:
    # 1. Stream a single real star picture continuously to the HDMI display:
    python stream_image.py star_sky.jpg

    # 2. Stream a picture with contrast enhancement for faint stars:
    python stream_image.py night_sky.png --contrast 2.0 --brightness 1.2

    # 3. Stream a sequence of photos from a directory as an animation:
    python stream_image.py ./star_dataset/ --fps 10 --loop

    # 4. Stream using native Grayscale mode (if KEY3 pressed on board):
    python stream_image.py star_field.png --mode gray
"""

import socket
import time
import argparse
import sys
from pathlib import Path
import numpy as np
from PIL import Image, ImageEnhance

WIDTH = 640
HEIGHT = 480
MAGIC_HEADER = bytes([0xAA, 0x55, 0xAA, 0x55])

def precise_delay(target_s):
    """High-precision busy-wait delay to eliminate OS timer quantum jitter."""
    if target_s <= 0:
        return
    t_end = time.perf_counter() + target_s
    while time.perf_counter() < t_end:
        pass

def preprocess_image(image_path, fit_mode="stretch", brightness=1.0, contrast=1.0, is_rgb=True):
    """
    Loads any image file, applies optional brightness/contrast enhancements,
    resizes to exactly 640x480 according to the fit policy, and converts to
    hardware-compliant raw bytes (RGB565 or Grayscale).
    """
    try:
        img = Image.open(image_path)
    except Exception as e:
        print(f"[ERROR] Failed to open image '{image_path}': {e}")
        return None

    # Apply brightness/contrast enhancement if requested
    if brightness != 1.0:
        img = ImageEnhance.Brightness(img).enhance(brightness)
    if contrast != 1.0:
        img = ImageEnhance.Contrast(img).enhance(contrast)

    # Resize/fit to 640x480
    if fit_mode == "stretch":
        img = img.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
    elif fit_mode == "contain":
        # Preserve aspect ratio with black borders (letterbox/pillarbox)
        img.thumbnail((WIDTH, HEIGHT), Image.Resampling.LANCZOS)
        background = Image.new("RGB" if is_rgb else "L", (WIDTH, HEIGHT), 0)
        offset_x = (WIDTH - img.width) // 2
        offset_y = (HEIGHT - img.height) // 2
        background.paste(img, (offset_x, offset_y))
        img = background
    elif fit_mode == "cover":
        # Fill 640x480 and center-crop excess
        scale = max(WIDTH / img.width, HEIGHT / img.height)
        new_w, new_h = int(img.width * scale), int(img.height * scale)
        img = img.resize((new_w, new_h), Image.Resampling.LANCZOS)
        left = (new_w - WIDTH) // 2
        top = (new_h - HEIGHT) // 2
        img = img.crop((left, top, left + WIDTH, top + HEIGHT))

    if is_rgb:
        img_rgb = img.convert("RGB")
        arr = np.array(img_rgb, dtype=np.uint8)

        # Vectorized RGB565 packing
        r = arr[:, :, 0].astype(np.uint16)
        g = arr[:, :, 1].astype(np.uint16)
        b = arr[:, :, 2].astype(np.uint16)

        val16 = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

        # OV7670 Big-Endian bus layout: MSB then LSB
        raw_bytes = np.empty((HEIGHT, WIDTH, 2), dtype=np.uint8)
        raw_bytes[:, :, 0] = (val16 >> 8) & 0xFF
        raw_bytes[:, :, 1] = val16 & 0xFF
        return raw_bytes.tobytes()
    else:
        img_gray = img.convert("L")
        return np.array(img_gray, dtype=np.uint8).tobytes()

def send_frame(sock, target_ip, target_port, frame_bytes, chunk_size=1280, delay_s=0.0002):
    """
    Sends the 4-byte synchronization magic word followed by the image data in UDP scanlines.
    """
    total_bytes = len(frame_bytes)

    # 1. Send Magic Frame Start Word (0xAA55AA55)
    sock.sendto(MAGIC_HEADER, (target_ip, target_port))
    time.sleep(0.005) # 5 ms pause to let hardware VSYNC pulse complete and reset pointers

    # 2. Send scanline data in chunks (1280 bytes = 1 line in RGB565, 640 bytes in Grayscale)
    for offset in range(0, total_bytes, chunk_size):
        chunk = frame_bytes[offset : offset + chunk_size]
        sock.sendto(chunk, (target_ip, target_port))
        if delay_s > 0:
            precise_delay(delay_s)

def collect_image_files(path_str):
    """Gathers image paths whether given a single file or a directory."""
    p = Path(path_str)
    if not p.exists():
        print(f"[ERROR] Path does not exist: {path_str}")
        sys.exit(1)

    valid_exts = {".png", ".jpg", ".jpeg", ".bmp", ".tif", ".tiff", ".webp"}
    if p.is_file():
        if p.suffix.lower() in valid_exts:
            return [p]
        else:
            print(f"[WARNING] Unrecognized image extension '{p.suffix}', attempting to open anyway...")
            return [p]
    elif p.is_dir():
        files = sorted([f for f in p.iterdir() if f.suffix.lower() in valid_exts])
        if not files:
            print(f"[ERROR] No valid image files found in directory: {path_str}")
            sys.exit(1)
        return files

def main():
    parser = argparse.ArgumentParser(description="Stream Real Star Images over UDP to FPGA Star Tracker")
    parser.add_argument("input", help="Path to image file (PNG, JPG, BMP, TIFF) or directory of images")
    parser.add_argument("--ip", default="192.168.1.10", help="Target board IP (default: 192.168.1.10)")
    parser.add_argument("--port", type=int, default=8080, help="Target UDP port (default: 8080)")
    parser.add_argument("--mode", choices=["rgb565", "gray"], default="rgb565",
                        help="Video mode: rgb565 (default, 614KB) or gray (307KB, KEY3)")
    parser.add_argument("--fit", choices=["stretch", "contain", "cover"], default="stretch",
                        help="Resizing fit: stretch (fill exactly), contain (letterbox), cover (center crop)")
    parser.add_argument("--brightness", type=float, default=1.0, help="Brightness scale (e.g. 1.2 to brighten)")
    parser.add_argument("--contrast", type=float, default=1.0, help="Contrast scale (e.g. 2.0 to make stars pop)")
    parser.add_argument("--fps", type=float, default=10.0, help="Target streaming FPS (default: 10.0)")
    parser.add_argument("--repeat", type=int, default=0,
                        help="Number of times to stream (default: 0 = continuous stream until Ctrl+C)")
    parser.add_argument("--loop", action="store_true", help="Continuously loop if input is a directory of images")
    parser.add_argument("--delay", type=float, default=0.0002, help="Packet delay in seconds (default: 200us)")

    args = parser.parse_args()

    image_paths = collect_image_files(args.input)
    is_rgb = (args.mode == "rgb565")
    frame_size = WIDTH * HEIGHT * (2 if is_rgb else 1)
    chunk_size = 1280 if is_rgb else 640

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    print("=" * 65)
    print("   Star Tracker Real Image Streamer (UDP -> FPGA HDMI)")
    print(f"   Target Board : {args.ip}:{args.port}")
    print(f"   Input Source : {args.input} ({len(image_paths)} file{'s' if len(image_paths) > 1 else ''})")
    print(f"   Mode         : {args.mode.upper()} ({frame_size:,} bytes/frame)")
    print(f"   Fit Policy   : {args.fit}")
    if args.brightness != 1.0 or args.contrast != 1.0:
        print(f"   Enhancement  : Brightness x{args.brightness}, Contrast x{args.contrast}")
    print(f"   Stream Mode  : {'Continuous (Ctrl+C to stop)' if args.repeat == 0 else f'{args.repeat} frames'}")
    print(f"   Target FPS   : {args.fps}")
    print("=" * 65)

    # Pre-encode images for maximum streaming throughput
    print(f"[*] Pre-formatting {len(image_paths)} image(s) to 640x480 {args.mode.upper()}...")
    cached_frames = []
    for p in image_paths:
        raw = preprocess_image(p, fit_mode=args.fit, brightness=args.brightness,
                               contrast=args.contrast, is_rgb=is_rgb)
        if raw is not None:
            cached_frames.append((p.name, raw))

    if not cached_frames:
        print("[FATAL] No images could be formatted.")
        sys.exit(1)

    print(f"[OK] {len(cached_frames)} image(s) ready in memory. Streaming now...")

    frame_count = 0
    img_idx = 0
    target_interval = 1.0 / args.fps

    try:
        while True:
            t0 = time.time()
            img_name, raw_data = cached_frames[img_idx]

            send_frame(sock, args.ip, args.port, raw_data, chunk_size=chunk_size, delay_s=args.delay)
            frame_count += 1

            t_send = time.time() - t0
            mbps = (frame_size * 8 / 1_000_000.0) / t_send if t_send > 0 else 0

            print(f"\r[+] Streaming frame #{frame_count:<5} | [{img_name}] | {mbps:5.1f} Mbps | Frame time: {t_send*1000:4.1f} ms", end="", flush=True)

            # Move to next image in directory
            if len(cached_frames) > 1:
                img_idx = (img_idx + 1) % len(cached_frames)
                if img_idx == 0 and not args.loop and args.repeat == 0:
                    print("\n[INFO] Finished sequence.")
                    break

            if args.repeat > 0 and frame_count >= args.repeat:
                print(f"\n[OK] Completed {frame_count} frames.")
                break

            # Pace frame rate
            sleep_rem = target_interval - (time.time() - t0)
            if sleep_rem > 0:
                time.sleep(sleep_rem)

    except KeyboardInterrupt:
        print("\n\n[!] Stream stopped by user (Ctrl+C).")

if __name__ == "__main__":
    main()
