
"""
===============================================================================
Universal Socket File Client (Cross-platform, Supports Upload/Download)
-------------------------------------------------------------------------------
- Usage examples:
    - Download file from server:   python file_client.py GET filename remote_host port save_dir
    - Upload file to server:       python file_client.py PUT filename remote_host port local_file
===============================================================================
"""

import sys
import socket
import os

def download_file(filename, host, port, save_dir):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((host, int(port)))
        s.sendall(f"GET {filename}\n".encode())
        status = b''
        while not status.endswith(b'\n'):
            status += s.recv(1)
        parts = status.strip().decode().split()
        if parts[0] == 'OK':
            filesize = int(parts[1])
            save_path = os.path.join(save_dir, filename)
            os.makedirs(save_dir, exist_ok=True)
            received = 0
            with open(save_path, 'wb') as f:
                while received < filesize:
                    chunk = s.recv(min(4096, filesize - received))
                    if not chunk:
                        break
                    f.write(chunk)
                    received += len(chunk)
            print(f"[SUCCESS] Downloaded {filename} to {save_path}")
        elif parts[0] == 'NOTFOUND':
            print("[ERROR] File not found on server.")
        else:
            print("[ERROR] Download failed.")

def upload_file(filename, host, port, local_file_path):
    filesize = os.path.getsize(local_file_path)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((host, int(port)))
        s.sendall(f"PUT {filename}\n".encode())
        s.sendall(f"{filesize}\n".encode())
        with open(local_file_path, 'rb') as f:
            while True:
                chunk = f.read(4096)
                if not chunk:
                    break
                s.sendall(chunk)
        status = b''
        while not status.endswith(b'\n'):
            status += s.recv(1)
        if status.strip().decode() == 'OK':
            print(f"[SUCCESS] Uploaded {local_file_path} as {filename}")
        else:
            print("[ERROR] Upload failed.")

def usage():
    print("USAGE:")
    print("  Download: python file_client.py GET filename remote_host port save_dir")
    print("  Upload:   python file_client.py PUT filename remote_host port local_file_path")
    sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 6 and not (len(sys.argv) == 5 and sys.argv[1].upper() == "GET"):
        usage()
    cmd = sys.argv[1].upper()
    filename = sys.argv[2]
    host = sys.argv[3]
    port = sys.argv[4]
    if cmd == "GET":
        save_dir = sys.argv[5] if len(sys.argv) > 5 else '.'
        download_file(filename, host, port, save_dir)
    elif cmd == "PUT":
        local_file_path = sys.argv[5]
        upload_file(filename, host, port, local_file_path)
    else:
        usage()
