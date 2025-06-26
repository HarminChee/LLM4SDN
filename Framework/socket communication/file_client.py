"""
===============================================================================
Universal Socket File Client (Cross-platform, Supports Nested Upload/Download)
-------------------------------------------------------------------------------
- Supports bidirectional file transfer (GET/PUT) between client and server.
- Supports arbitrary subdirectory structure in filenames (e.g., case42/r1/r1.conf).
- Fully compatible with file_server.py when BASE_DIR is set to your root 
  topotests directory (e.g., /path/to/frr/tests/topotests).
- When uploading, server will automatically create any missing subdirectories.
- This enables direct integration with automated SDN/pytest workflows,
  allowing the server to receive files in the precise target case/node directory.

*** Usage Notes and Best Practices ***
- Always use forward slashes '/' in filename arguments for nested directories,
  regardless of client OS (Linux/Windows).
- Ensure file_server.py is running on the target machine, with BASE_DIR 
  configured to match the root of your case directories.
- Upload: python file_client.py PUT case42/r1/r1.conf <server_ip> <port> /path/to/local/r1.conf
- Download: python file_client.py GET case42/r1/r1.conf <server_ip> <port> ./save_dir/
- To push or fetch multiple files, use shell loops or automation scripts.
- If server or network fails mid-transfer, re-run the command; partial files
  are overwritten on upload.
===============================================================================
"""

import sys
import socket
import os

def download_file(filename, host, port, save_dir):
    """
    Download a file (including any nested directory) from server.
    The file will be saved with subdirectories preserved under save_dir.
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect((host, int(port)))
        s.sendall(f"GET {filename}\n".encode())
        status = b''
        while not status.endswith(b'\n'):
            recv_chunk = s.recv(1)
            if not recv_chunk:
                break
            status += recv_chunk
        parts = status.strip().decode().split()
        if parts[0] == 'OK':
            filesize = int(parts[1])
            save_path = os.path.join(save_dir, *filename.split('/'))
            os.makedirs(os.path.dirname(save_path), exist_ok=True)
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
            print(f"[ERROR] File not found on server: {filename}")
        else:
            print("[ERROR] Download failed or unknown server response.")

def upload_file(filename, host, port, local_file_path):
    """
    Upload a file (can include subdirectory structure in filename argument).
    The server will automatically create required subdirectories.
    """
    if not os.path.isfile(local_file_path):
        print(f"[ERROR] Local file does not exist: {local_file_path}")
        return
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
            recv_chunk = s.recv(1)
            if not recv_chunk:
                break
            status += recv_chunk
        if status.strip().decode() == 'OK':
            print(f"[SUCCESS] Uploaded {local_file_path} as {filename}")
        else:
            print(f"[ERROR] Upload failed for {filename}")

def usage():
    print("USAGE:")
    print("  Download: python file_client.py GET <filename> <remote_host> <port> <save_dir>")
    print("    Example: python file_client.py GET case42/r1/r1.conf 192.168.1.222 61000 ./save_dir/")
    print("  Upload:   python file_client.py PUT <filename> <remote_host> <port> <local_file_path>")
    print("    Example: python file_client.py PUT case42/r1/r1.conf 192.168.1.222 61000 ./r1.conf")
    sys.exit(1)

if __name__ == "__main__":
    # Command line arg check & parse
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
