#!/usr/bin/env python3
"""Fast LAN APK installer for Android TV over netcat stream.
Automatically handles signature updates, force replacement, and cleanup.
Usage:
    tools/install_apk.py <path_to_apk> [optional_package_name_to_uninstall_if_sig_mismatch]
"""
import os
import socket
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tv

if len(sys.argv) < 2:
    print("Usage: tools/install_apk.py <path_to_apk> [package_name]")
    sys.exit(1)

APK_PATH = sys.argv[1]
PKG_HINT = sys.argv[2] if len(sys.argv) > 2 else None
TV_IP = os.environ.get("TV_HOST", "192.168.29.198")
MAC_IP = "192.168.29.192"
PORT = 9999
REMOTE_APK = "/data/local/tmp/app_install.apk"

filesize = os.path.getsize(APK_PATH)
print(f"Preparing to transfer {APK_PATH} ({filesize / 1024 / 1024:.2f} MB)...")

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("0.0.0.0", PORT))
server.listen(1)
server.settimeout(30.0)

dev = None

def trigger_tv():
    global dev
    time.sleep(1.0)
    print("Connecting to TV to initiate transfer...")
    dev = tv.connect()
    cmd = f"toybox nc {MAC_IP} {PORT} > {REMOTE_APK}"
    print(f"TV executing: {cmd}")
    out = dev.shell(cmd, read_timeout_s=180.0)
    print("TV netcat completed.")

t = threading.Thread(target=trigger_tv)
t.start()

print(f"Listening on port {PORT} for TV connection...")
client, addr = server.accept()
print(f"TV connected from {addr}! Streaming APK...")

with open(APK_PATH, "rb") as f:
    sent = 0
    while True:
        chunk = f.read(128 * 1024)
        if not chunk:
            break
        client.sendall(chunk)
        sent += len(chunk)
        print(f"\rTransferred: {sent / 1024 / 1024:.2f} / {filesize / 1024 / 1024:.2f} MB", end="", flush=True)

client.close()
server.close()
print("\nStream closed. Waiting for TV shell to finish...")
t.join()

print("Verifying size on TV...")
size_out = dev.shell(f"ls -l {REMOTE_APK}", read_timeout_s=30.0)
print(f"TV file info: {size_out.strip()}")

print("Installing on TV...")
install_out = dev.shell(f"pm install -r -d {REMOTE_APK}", read_timeout_s=180.0)
print(f"Install result: {install_out.strip()}")

if "INSTALL_FAILED_UPDATE_INCOMPATIBLE" in install_out and PKG_HINT:
    print(f"Signature mismatch detected. Reinstalling package {PKG_HINT}...")
    uninst = dev.shell(f"pm uninstall {PKG_HINT}")
    print(f"Uninstall result: {uninst.strip()}")
    install_out = dev.shell(f"pm install -r -d {REMOTE_APK}", read_timeout_s=180.0)
    print(f"Re-install result: {install_out.strip()}")

# Cleanup
dev.shell(f"rm -f {REMOTE_APK}")
dev.close()
print("Done!")
