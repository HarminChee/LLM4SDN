
"""
===============================================================================
Universal Socket File Server (Cross-platform, Supports Upload/Download)
-------------------------------------------------------------------------------
- Can receive or send any file (.py, .conf, .json, etc.) upon request.
- Supports both upload (client->server) and download (server->client) modes.
- Use on any device (Linux, Raspberry Pi, Windows with Python3).
===============================================================================
"""

import socket
import threading
import os

# Basic configuration (adjust for your deployment)
HOST = '0.0.0.0'
PORT = 61000
BASE_DIR = '/path/to/file_exchange_dir'  # Directory for storing/exchanging files

def handle_client(conn, addr):
    try:
        # Receive command (e.g. "GET filename", "PUT filename")
        header = b''
        while not header.endswith(b'\n'):
            header += conn.recv(1)
        parts = header.strip().decode().split()
        if len(parts) < 2:
            conn.sendall(b'ERROR\n')
            return
        cmd, filename = parts[0].upper(), parts[1]
        filepath = os.path.join(BASE_DIR, filename)
        if cmd == "GET":
            # Download mode: send file to client
            if os.path.isfile(filepath):
                filesize = os.path.getsize(filepath)
                conn.sendall(f"OK {filesize}\n".encode())
                with open(filepath, 'rb') as f:
                    while True:
                        chunk = f.read(4096)
                        if not chunk:
                            break
                        conn.sendall(chunk)
                print(f"[INFO] Sent file: {filepath} to {addr}")
            else:
                conn.sendall(b'NOTFOUND\n')
                print(f"[WARN] File not found: {filepath}")
        elif cmd == "PUT":
            # Upload mode: receive file from client
            size_line = b''
            while not size_line.endswith(b'\n'):
                size_line += conn.recv(1)
            filesize = int(size_line.strip())
            received = 0
                # === NOTE ===
                # This line ensures that any subdirectory in filename (e.g., case42/r1/r1.conf)
                # will be automatically created if not present, so that files are always saved
                # in the intended nested structure.
            os.makedirs(os.path.dirname(filepath), exist_ok=True)
            with open(filepath, 'wb') as f:
                while received < filesize:
                    chunk = conn.recv(min(4096, filesize - received))
                    if not chunk:
                        break
                    f.write(chunk)
                    received += len(chunk)
            conn.sendall(b'OK\n')
            print(f"[INFO] Received file: {filepath} from {addr}")
        else:
            conn.sendall(b'ERROR\n')
    except Exception as e:
        print(f"[ERROR] {e}")
        conn.sendall(b'ERROR\n')
    finally:
        conn.close()

def main():
    os.makedirs(BASE_DIR, exist_ok=True)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind((HOST, PORT))
        s.listen(8)
        print(f"[INFO] Universal file server listening on {HOST}:{PORT} ...")
        while True:
            conn, addr = s.accept()
            threading.Thread(target=handle_client, args=(conn, addr)).start()

if __name__ == "__main__":
    main()
