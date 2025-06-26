#!/usr/bin/env python3
"""
===============================================================================
Node Conf Completion Request Sender for Edge LLM (Main Control Side)
-------------------------------------------------------------------------------
- For a given case name:
    - Scans official topotests dir for case folder, collects its directory/files
    - Reads corresponding JSON topology and generated .py config
    - Builds a detailed prompt describing the directory and required .conf files
    - Sends this prompt to the Edge LLM via socket, expects a dict: {node: conf_content}
    - Receives all .conf content, saves as {node}.conf, then pushes to Linux validation machine
===============================================================================
"""

import os
import socket
import json
from pathlib import Path

# --- Config --- (set according to your environment)
OFFICIAL_TOPOTESTS_DIR = Path("/path/to/frr/tests/topotests")        # Official cases
PY_GEN_DIR             = Path("/path/to/generated_py")               # LLM .py files
JSON_GEN_DIR           = Path("/path/to/generated_json")             # LLM .json files
TMP_CONF_SAVE_DIR      = Path("/tmp/tmp_node_confs")                 # Temp save for .conf
LLM_HOST               = "192.168.1.101"                             # Edge LLM IP
LLM_PORT               = 53000                                       # Edge LLM port

# --- Core functions ---

def scan_case_structure(case_dir: Path):
    """
    Returns a dict summary of the case directory, focusing on r1/r2... nodes and their .conf files.
    """
    structure = {}
    if not case_dir.is_dir():
        return structure
    for node_dir in sorted(case_dir.iterdir()):
        if node_dir.is_dir() and node_dir.name.startswith("r"):
            conf_files = [f.name for f in node_dir.glob("*.conf")]
            structure[node_dir.name] = conf_files
    return structure

def build_conf_completion_prompt(case_name, dir_summary, py_code, topo_json):
    return (
        f"You are an expert in FRRouting SDN topotests. "
        f"For the test case '{case_name}', here is the case directory structure and current node folders/files:\n"
        f"{json.dumps(dir_summary, indent=2)}\n"
        f"Below is the current main test_{case_name}.py config file:\n"
        f"{py_code}\n"
        f"Below is the corresponding topology JSON:\n"
        f"{topo_json}\n"
        "TASK: For each node (e.g., r1, r2, ...), generate a valid .conf file string for this topology and test script. "
        "Return your answer as a JSON object: {node_name: conf_content, ...}. Only output pure JSON, with no comments or markdown."
    )

def send_prompt_to_llm_socket(prompt, host, port, timeout=180):
    """
    Send prompt to LLM socket server, receive a (length-prefixed) JSON dict.
    """
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            prompt_bytes = prompt.encode("utf-8")
            sock.sendall(f"{len(prompt_bytes)}\n".encode())
            sock.sendall(prompt_bytes)
            # Receive length-prefixed JSON reply
            reply_len_line = b''
            while not reply_len_line.endswith(b'\n'):
                chunk = sock.recv(1)
                if not chunk:
                    break
                reply_len_line += chunk
            reply_len = int(reply_len_line.strip())
            received = b''
            while len(received) < reply_len:
                chunk = sock.recv(min(4096, reply_len - len(received)))
                if not chunk:
                    break
                received += chunk
            return received.decode("utf-8")
    except Exception as e:
        print(f"[ERROR] Socket communication with LLM failed: {e}")
        return None

def main():
    case_name = input("Enter target case name: ").strip()
    case_dir  = OFFICIAL_TOPOTESTS_DIR / case_name
    py_file   = PY_GEN_DIR / f"{case_name}.py"
    json_file = JSON_GEN_DIR / f"{case_name}.json"

    if not (case_dir.is_dir() and py_file.exists() and json_file.exists()):
        print("[ERROR] Required files/folders not found.")
        return

    dir_summary = scan_case_structure(case_dir)
    py_code     = py_file.read_text(encoding="utf-8")
    topo_json   = json_file.read_text(encoding="utf-8")

    prompt = build_conf_completion_prompt(case_name, dir_summary, py_code, topo_json)
    print("[INFO] Sending prompt to Edge LLM...")
    llm_reply = send_prompt_to_llm_socket(prompt, LLM_HOST, LLM_PORT)
    if not llm_reply:
        print("[ERROR] No reply from LLM.")
        return

    # Parse JSON, save .conf files
    try:
        node_conf_dict = json.loads(llm_reply)
        TMP_CONF_SAVE_DIR.mkdir(exist_ok=True)
        for node, conf_str in node_conf_dict.items():
            save_path = TMP_CONF_SAVE_DIR / f"{node}.conf"
            with open(save_path, "w", encoding="utf-8") as f:
                f.write(conf_str)
            print(f"[INFO] Saved conf: {save_path}")
    except Exception as e:
        print(f"[ERROR] LLM reply is not valid JSON: {e}")
        return

    # TODO: You can now push these .conf files to the Linux validator, 
    #       for example using the universal socket file_client.py from earlier,
    #       or scp, or any desired method.

if __name__ == "__main__":
    main()
