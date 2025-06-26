"""
===============================================================================
Distributed SDN Config Generation via Edge-Deployed LLMs
-------------------------------------------------------------------------------
- The LLM backend (such as Raspberry Pi edge devices) MUST run a compatible 
  socket server that accepts prompt strings and returns ONLY valid Python code 
  as a string. This script assumes each server can serve requests independently 
  and uses round-robin scheduling for load balancing.

- All paths (for .py configs, .json topologies, output directory, and pair txt) 
  MUST be adapted to your data structure. It is recommended to keep .py/.json 
  files in unified directories for open-source portability.

- This script supports batch and persistent processing, making it suitable for 
  large-scale distributed inference on multiple edge devices.

- The LLM output is STRICTLY limited to Python code only—no explanations, 
  comments, markdown, or extra text allowed. This ensures output files can be 
  directly used for SDN system testing and automation.

- The SDN system prompt (background information) can be loaded from an external 
  text file. If not provided, a default prompt is used.
===============================================================================
"""

import os
import time
import socket

# ========================== CONFIGURATION SECTION ===========================

# Path settings (please change to your own data structure for open source use)
PAIR_TXT_PATH = '/path/to/high_similarity_pairs.txt'   # TXT file: each line is "A & B, heatmap: score"
SDN_PY_DIR = '/path/to/py_configs'                    # Folder: contains *.py configuration files
SDN_JSON_DIR = '/path/to/json_topos'                  # Folder: contains *.json topology files
OUTPUT_DIR = '/path/to/generated_output'              # Folder: generated *.py files are saved here
SDN_SYSTEM_PROMPT_PATH = '/path/to/sdn_background_info.txt'  # TXT file: SDN background info prompt

# Distributed model serving (example: multi-Raspberry Pi cluster) configuration
LLM_SERVER_HOSTS = ['10.0.0.101', '10.0.0.102', '10.0.0.103', '10.0.0.104']  # Example edge model IPs
LLM_SERVER_PORT = 50007                                                      # LLM socket server port
TIMEOUT_SEC = 180                                                            # Network/model timeout per request (sec)
MAX_RETRY = 3                                                                # Retry times if a server fails

# ============================================================================

def read_pairs(pair_txt_path):
    """
    Read the A&B similarity pairs from the txt file. Return a list of tuples (A, B).
    """
    pairs = []
    with open(pair_txt_path, 'r', encoding='utf-8') as f:
        for line in f:
            # Supports both "A & B, ..." and "A&B, ..." formats
            parts = line.strip().split(',')
            ab = parts[0].replace(' ', '')
            if '&' in ab:
                a, b = ab.split('&')
                pairs.append((a.strip(), b.strip()))
    return pairs

def load_file(file_path):
    """
    Utility function to safely read a file as string. Return None if not found.
    """
    if not os.path.isfile(file_path):
        return None
    with open(file_path, 'r', encoding='utf-8') as f:
        return f.read()

def load_system_prompt(path):
    """
    Load the SDN system prompt (background knowledge) from a txt file.
    If the file does not exist, use a default prompt.
    """
    if not os.path.isfile(path):
        print(f"[WARN] System prompt file not found: {path}, using default prompt.")
        return (
            "You are a professional SDN (Software-Defined Networking) engineer. "
            "Given detailed topology and a reference SDN configuration, "
            "your task is to generate or repair a main configuration file (.py format) "
            "for a new SDN topology. Only output valid python code, no explanations or comments."
        )
    with open(path, 'r', encoding='utf-8') as f:
        return f.read().strip()

def build_prompt(target_name, ref_name, ref_py, ref_json, target_json, system_prompt):
    """
    Construct the LLM prompt for configuration generation, enforcing output code-only.
    """
    prompt = (
        f"{system_prompt}\n"
        f"\nReference SDN main configuration (.py):\n"
        f"-----BEGIN REFERENCE PY-----\n{ref_py}\n-----END REFERENCE PY-----\n"
        f"\nReference topology (JSON):\n"
        f"-----BEGIN REFERENCE JSON-----\n{ref_json}\n-----END REFERENCE JSON-----\n"
        f"\nTarget topology (JSON):\n"
        f"-----BEGIN TARGET JSON-----\n{target_json}\n-----END TARGET JSON-----\n"
        "\nNow, generate the target SDN main configuration file (.py) for the above topology."
        "\nIMPORTANT: Only output valid python code, with NO extra comments, markdown, or explanations."
    )
    return prompt

def choose_llm_host(task_id):
    """
    Distribute workload across available LLM servers (simple round-robin).
    """
    idx = task_id % len(LLM_SERVER_HOSTS)
    return LLM_SERVER_HOSTS[idx]

def llm_socket_infer(prompt, server_host, port=LLM_SERVER_PORT, timeout=TIMEOUT_SEC):
    """
    Send prompt to remote LLM model via socket, receive the generated python code.
    The edge device should be running a compatible LLM serving process that
    accepts prompt string, outputs only python code as plain text.
    """
    data = prompt.encode('utf-8')
    result = None
    for attempt in range(MAX_RETRY):
        try:
            with socket.create_connection((server_host, port), timeout=timeout) as sock:
                sock.sendall(data)
                # You may need to adjust buffer size and chunk handling for your LLM server
                response = b''
                while True:
                    chunk = sock.recv(4096)
                    if not chunk:
                        break
                    response += chunk
                result = response.decode('utf-8')
                break
        except Exception as e:
            print(f"[WARN] LLM server {server_host}:{port} failed (attempt {attempt+1}): {e}")
            time.sleep(2)
    return result

def process_pair(pair_id, src_name, tgt_name, direction, output_dir, system_prompt):
    """
    Given (src, tgt), build prompt, send to LLM, save output as py file.
    direction: 'forward' (src->tgt) or 'reverse' (tgt->src)
    """
    if direction == 'forward':
        ref_py_name, ref_json_name = f"{src_name}.py", f"{src_name}.json"
        tgt_json_name = f"{tgt_name}.json"
        output_py_name = f"{tgt_name}.py"
    else:
        ref_py_name, ref_json_name = f"{tgt_name}.py", f"{tgt_name}.json"
        tgt_json_name = f"{src_name}.json"
        output_py_name = f"{src_name}.py"

    # Load all required input files
    ref_py_path = os.path.join(SDN_PY_DIR, ref_py_name)
    ref_json_path = os.path.join(SDN_JSON_DIR, ref_json_name)
    tgt_json_path = os.path.join(SDN_JSON_DIR, tgt_json_name)

    ref_py = load_file(ref_py_path)
    ref_json = load_file(ref_json_path)
    tgt_json = load_file(tgt_json_path)

    if not all([ref_py, ref_json, tgt_json]):
        print(f"[ERROR] Missing files for pair ({src_name}, {tgt_name}), direction: {direction}")
        return

    prompt = build_prompt(
        target_name=tgt_name if direction == 'forward' else src_name,
        ref_name=src_name if direction == 'forward' else tgt_name,
        ref_py=ref_py,
        ref_json=ref_json,
        target_json=tgt_json,
        system_prompt=system_prompt
    )
    llm_host = choose_llm_host(pair_id)
    print(f"[INFO] Sending inference request to LLM server: {llm_host} ({direction}) ...")
    result_code = llm_socket_infer(prompt, llm_host)
    if not result_code:
        print(f"[ERROR] LLM inference failed for ({src_name}, {tgt_name}), direction: {direction}")
        return

    output_path = os.path.join(output_dir, output_py_name)
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(result_code)
    print(f"[SUCCESS] Generated file saved: {output_path}")

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    pairs = read_pairs(PAIR_TXT_PATH)
    print(f"[INFO] Loaded {len(pairs)} A&B pairs from {PAIR_TXT_PATH}")
    system_prompt = load_system_prompt(SDN_SYSTEM_PROMPT_PATH)

    for i, (a_name, b_name) in enumerate(pairs):
        print(f"\n====== Processing pair {i+1}/{len(pairs)}: {a_name} <-> {b_name} ======")
        # Generate B.py using A as reference
        process_pair(i, a_name, b_name, direction='forward', output_dir=OUTPUT_DIR, system_prompt=system_prompt)
        # Generate A.py using B as reference (reverse)
        process_pair(i, a_name, b_name, direction='reverse', output_dir=OUTPUT_DIR, system_prompt=system_prompt)
        # Optional: add sleep if needed for edge model throughput
        time.sleep(1)

if __name__ == "__main__":
    main()
