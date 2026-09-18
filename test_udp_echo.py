#!/usr/bin/env python3
"""
UDP State Echo Test Script for Star Tracker PS (AX7010 Zynq-7000)
----------------------------------------------------------------
Sends test UDP datagrams to the board and awaits the state echo response.

Usage:
    python test_udp_echo.py [target_ip] [target_port]
"""

import socket
import sys
import time

TARGET_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.10"
TARGET_PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8080
TIMEOUT_SEC = 2.0

def main():
    print("=" * 60)
    print(f" Star Tracker UDP Echo Test")
    print(f" Target Board: {TARGET_IP}:{TARGET_PORT}")
    print("=" * 60)

    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(TIMEOUT_SEC)

    test_messages = [
        "PING",
        "STAR_TRACKER_CALIBRATE",
        "GET_CAMERA_STATE",
        "TELEMETRY_REQUEST",
        "HELLO_ZYNQ_PS"
    ]

    success_count = 0

    for idx, msg in enumerate(test_messages, start=1):
        payload = msg.encode("utf-8")
        print(f"\n[Test #{idx}] Sending -> \"{msg}\"")
        start_time = time.time()

        try:
            # Send UDP packet
            sock.sendto(payload, (TARGET_IP, TARGET_PORT))

            # Wait for Echo Response containing board state
            reply, addr = sock.recvfrom(1024)
            rtt_ms = (time.time() - start_time) * 1000.0

            print(f"  [ACK #{idx}] From {addr[0]}:{addr[1]} (RTT: {rtt_ms:.2f} ms)")
            print(f"  Response: {reply.decode('utf-8', errors='replace').strip()}")
            success_count += 1

        except socket.timeout:
            print(f"  [TIMEOUT] No response from board within {TIMEOUT_SEC}s!")
            print("  Check: Ethernet cable, board power, IP subnet (e.g. host at 192.168.1.50)")

        time.sleep(0.5)

    sock.close()

    print("\n" + "=" * 60)
    print(f" Summary: {success_count}/{len(test_messages)} packets echoed successfully.")
    print("=" * 60)

if __name__ == "__main__":
    main()
