#!/usr/bin/env python3
"""
send_star_frame.py - Star Tracker Test Image Streamer over UDP
--------------------------------------------------------------
Streams synthetic starfield frames over UDP to the ALINX AX7010 Zynq PS.

The PS writes the stream into the AXI4-Stream FIFO, which drives:
  axis_cam_bridge -> star_detect (centroids) -> fb_mem -> HDMI display!

By default, streams in native RGB565 (640x480 @ 2 bytes/pix = 614,400 bytes/frame)
matching the hardware's power-on default mode.

Usage:
    # Stream animated stars continuously (press Ctrl+C to stop):
    python send_star_frame.py --ip 192.168.1.10 --port 8080 --fps 15

    # Stream 5 frames and exit:
    python send_star_frame.py --ip 192.168.1.10 --port 8080 --repeat 5
"""

import socket
import time
import argparse
import math
import sys

WIDTH  = 640
HEIGHT = 480
MAGIC_HEADER = bytes([0xAA, 0x55, 0xAA, 0x55])

def generate_star_frame_rgb565(t=0.0):
    """
    Generate a 640x480 RGB565 frame (2 bytes per pixel, 614,400 bytes total).
    Matches the hardware's native camera format (1,280 bytes per line).
    Optionally animates star positions based on time 't'.
    """
    frame = bytearray(WIDTH * HEIGHT * 2)

    # Base star catalog with orbital motion: (center_x, center_y, peak, radius, drift_speed, angle_offset)
    star_defs = [
        (320, 240, 255, 4, 0.5, 0.0),            # Bright central star orbiting slowly
        (150, 100, 220, 3, 0.3, 1.2),            # Star 2
        (480, 120, 200, 3, 0.4, 2.5),            # Star 3
        (220, 380, 190, 2, 0.2, 3.8),            # Star 4
        (520, 360, 230, 3, 0.6, 4.5),            # Star 5
        (160, 220, 170, 2, 0.3, 5.2),            # Star 6
        (420, 280, 180, 2, 0.4, 0.8),            # Star 7
    ]

    for cx, cy, peak, r, speed, phase in star_defs:
        # Subtle orbital drift around the anchor point
        drift_r = 15.0
        sx = int(cx + drift_r * math.cos(speed * t + phase))
        sy = int(cy + drift_r * math.sin(speed * t + phase))

        for dy in range(-r, r + 1):
            py = sy + dy
            if py < 0 or py >= HEIGHT:
                continue
            for dx in range(-r, r + 1):
                px = sx + dx
                if px < 0 or px >= WIDTH:
                    continue
                dist_sq = dx * dx + dy * dy
                if dist_sq <= r * r:
                    intensity = int(peak * math.exp(-dist_sq / (r * 0.7)))
                    # White star in RGB565: R[4:0]=I>>3, G[5:0]=I>>2, B[4:0]=I>>3
                    r5 = (intensity >> 3) & 0x1F
                    g6 = (intensity >> 2) & 0x3F
                    b5 = (intensity >> 3) & 0x1F
                    val16 = (r5 << 11) | (g6 << 5) | b5
                    idx = (py * WIDTH + px) * 2

                    # OV7670 Big-Endian bus packing: Byte 0 = MSB, Byte 1 = LSB
                    frame[idx]     = max(frame[idx], (val16 >> 8) & 0xFF)
                    frame[idx + 1] = max(frame[idx + 1], val16 & 0xFF)

    return frame

def generate_star_frame_gray(t=0.0):
    """
    Generate a 640x480 grayscale frame (1 byte per pixel, 307,200 bytes total).
    Used when the board is in Grayscale mode (KEY3 pressed).
    """
    frame = bytearray(WIDTH * HEIGHT)
    star_defs = [
        (320, 240, 255, 4, 0.5, 0.0),
        (150, 100, 220, 3, 0.3, 1.2),
        (480, 120, 200, 3, 0.4, 2.5),
        (220, 380, 190, 2, 0.2, 3.8),
        (520, 360, 230, 3, 0.6, 4.5),
        (160, 220, 170, 2, 0.3, 5.2),
        (420, 280, 180, 2, 0.4, 0.8),
    ]

    for cx, cy, peak, r, speed, phase in star_defs:
        drift_r = 15.0
        sx = int(cx + drift_r * math.cos(speed * t + phase))
        sy = int(cy + drift_r * math.sin(speed * t + phase))

        for dy in range(-r, r + 1):
            py = sy + dy
            if py < 0 or py >= HEIGHT:
                continue
            for dx in range(-r, r + 1):
                px = sx + dx
                if px < 0 or px >= WIDTH:
                    continue
                dist_sq = dx * dx + dy * dy
                if dist_sq <= r * r:
                    intensity = int(peak * math.exp(-dist_sq / (r * 0.7)))
                    idx = py * WIDTH + px
                    frame[idx] = max(frame[idx], min(255, intensity))

    return frame

def precise_delay(target_s):
    """
    High-precision busy-wait timer for Windows to eliminate OS timer quantum jitter.
    """
    if target_s <= 0:
        return
    t_end = time.perf_counter() + target_s
    while time.perf_counter() < t_end:
        pass

def send_frame(sock, target_ip, target_port, frame_bytes, chunk_size=1280, delay_s=0.0002):
    """
    Sends the 4-byte synchronization magic word followed by the image data in UDP chunks.
    """
    total_bytes = len(frame_bytes)

    # 1. Send Magic Frame Start Word (0xAA55AA55)
    sock.sendto(MAGIC_HEADER, (target_ip, target_port))
    time.sleep(0.005) # 5 ms pause to let hardware VSYNC pulse complete and reset pointers

    # 2. Send scanline data in chunks (1280 bytes = exactly 1 full line in RGB565)
    for offset in range(0, total_bytes, chunk_size):
        chunk = frame_bytes[offset : offset + chunk_size]
        sock.sendto(chunk, (target_ip, target_port))
        if delay_s > 0:
            precise_delay(delay_s)

def main():
    parser = argparse.ArgumentParser(description="Stream Star Field Image over UDP to FPGA")
    parser.add_argument("--ip", default="192.168.1.10", help="Target board IP (default: 192.168.1.10)")
    parser.add_argument("--port", type=int, default=8080, help="Target UDP port (default: 8080)")
    parser.add_argument("--mode", choices=["rgb565", "gray"], default="rgb565",
                        help="Video mode: rgb565 (614KB, default) or gray (307KB, KEY3)")
    parser.add_argument("--repeat", type=int, default=0,
                        help="Number of frames to send (0 = continuous live stream until Ctrl+C)")
    parser.add_argument("--fps", type=float, default=10.0, help="Target FPS (default: 10.0)")
    parser.add_argument("--delay", type=float, default=0.0002,
                        help="Inter-packet delay in seconds (default: 0.0002 = 200us precise pacing)")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    is_rgb = (args.mode == "rgb565")
    frame_size = WIDTH * HEIGHT * (2 if is_rgb else 1)
    chunk_size = 1280 if is_rgb else 640
    packets_per_frame = frame_size // chunk_size

    print("=" * 65)
    print("   Star Tracker AXI-Stream UDP Test Frame Generator")
    print(f"   Target   : {args.ip}:{args.port}")
    print(f"   Mode     : {args.mode.upper()} ({frame_size:,} bytes/frame)")
    print(f"   Packets  : {packets_per_frame} scanlines ({chunk_size} bytes/packet)")
    print(f"   Stream   : {'Continuous (Ctrl+C to stop)' if args.repeat == 0 else f'{args.repeat} frames'}")
    print(f"   Target FPS: {args.fps}")
    print(f"   Pkt Delay: {args.delay*1000:.2f} ms")
    print("=" * 65)

    frame_count = 0
    start_time = time.time()
    t_sim = 0.0

    try:
        while True:
            t0 = time.time()
            frame_count += 1

            # Generate frame with slight animation
            if is_rgb:
                frame = generate_star_frame_rgb565(t=t_sim)
            else:
                frame = generate_star_frame_gray(t=t_sim)

            send_frame(sock, args.ip, args.port, frame, chunk_size=chunk_size, delay_s=args.delay)

            t_send = time.time() - t0
            t_sim += 1.0 / args.fps
            mbps = (frame_size * 8 / 1_000_000.0) / t_send if t_send > 0 else 0

            print(f"\r[+] Streaming frame #{frame_count:<5} | {mbps:5.1f} Mbps | Frame time: {t_send*1000:4.1f} ms", end="", flush=True)

            if args.repeat > 0 and frame_count >= args.repeat:
                break

            # Sleep to match target FPS
            sleep_time = (1.0 / args.fps) - (time.time() - t0)
            if sleep_time > 0:
                time.sleep(sleep_time)

        total_elapsed = time.time() - start_time
        avg_fps = frame_count / total_elapsed if total_elapsed > 0 else 0
        print(f"\n\n[OK] Completed {frame_count} frames in {total_elapsed:.2f}s ({avg_fps:.1f} avg FPS).")

    except KeyboardInterrupt:
        print("\n\n[!] Stream stopped by user.")
    finally:
        sock.close()

if __name__ == "__main__":
    main()
