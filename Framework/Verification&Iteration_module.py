#!/usr/bin/env python3
"""
===============================================================================
Automated SDN Pytest & Edge Model Correction via Socket Communication
-------------------------------------------------------------------------------
- Iteratively validates SDN python config files using pytest.
- For each failed case, builds a structured prompt including:
    - Current py config code
    - Topology .json
    - Pytest error log
    - Text system prompt
    - Directory/Node .conf summary
- Sends the prompt to distributed LLM (e.g., Raspberry Pi cluster) over socket.
- Receives new py code, replaces, and re-runs pytest.
===============================================================================
"""

import os
import sys
import re
import json
import time
import socket
import textwrap
import subprocess
from pathlib import Path
from datetime import datetime
import shutil

# --------------------------------------------------------------------------- #
# Path Configurations (edit these as needed for your deployment)
# --------------------------------------------------------------------------- #
TOPOTESTS_ROOT   = Path("/path/to/frr/tests/topotests")
PY_SRC_DIR       = Path("/path/to/generated_py_scripts")
JSON_SRC_DIR     = Path("/path/to/generated_json_topos")
CONF_ROOT        = Path("/path/to/node_conf_dirs")      # e.g., r1, r2, ... node confs
BACKUP_ROOT      = Path("/path/to/pytest_backup")
LOG_DIR          = Path("/path/to/pytest_logs")

for d in [BACKUP_ROOT, LOG_DIR]:
    d.mkdir(parents=True, exist_ok=True)

ITER_MAX = 8

# --------------------------------------------------------------------------- #
# Edge LLM socket configuration
# --------------------------------------------------------------------------- #
LLM_HOST = "192.168.1.101"  # Example Raspberry Pi/Edge Model IP
LLM_PORT = 52000            # Edge LLM server port
SOCKET_TIMEOUT = 180        # Seconds

# --------------------------------------------------------------------------- #
# System Prompt (edit as appropriate or load from file)
# --------------------------------------------------------------------------- #
SYSTEM_PROMPT = (
    "You are an expert FRRouting SDN configuration engineer. "
    "Given the current main python config script, associated JSON topology, pytest error log, "
    "and all relevant node configuration directory summaries, your task is to correct and complete "
    "the main test_xxx.py script so it will pass pytest for the given topology. "
    "Your output must be strictly valid python code—do not include explanations, markdown, or comments."
)

# --------------------------------------------------------------------------- #
# Utility Functions
# --------------------------------------------------------------------------- #
def run_cmd(cmd: list, cwd: Path, timeout: int = 600) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout)

def run_pytest(test_pyfile: Path, case_dir: Path) -> subprocess.CompletedProcess:
    return run_cmd(["sudo", "-E", "pytest", "-q", "-s", test_pyfile.name], cwd=case_dir)

def extract_error(full_log: str, tail_lines: int = 40) -> str:
    # Extract error section, fallback to last lines
    parts = re.split(r"\n={10,}\s*FAILURES\s*={10,}\n", full_log)
    if len(parts) > 1:
        return parts[-1][-1500:]
    return "\n".join(full_log.splitlines()[-tail_lines:])

def sanitize_code(raw: str) -> str:
    # Remove code fences, explanations, and extra text
    cleaned = re.sub(r"```(?:python|py)?\s*", "", raw)
    cleaned = re.sub(r"```", "", cleaned)
    lines = [ln.rstrip() for ln in cleaned.splitlines()]
    keywords = ("import ", "from ", "class ", "def ", "@", "#!")
    code_start = 0
    while code_start < len(lines) and not lines[code_start].strip().startswith(keywords):
        code_start += 1
    pure_code = "\n".join(lines[code_start:]).lstrip()
    while pure_code and not pure_code.lstrip().startswith(keywords):
        pure_code = "\n".join(pure_code.splitlines()[1:]).lstrip()
    return pure_code

def get_nonconflicting_filename(base: Path) -> Path:
    if not base.exists():
        return base
    stem = base.stem
    suffix = base.suffix
    parent = base.parent
    i = 2
    while True:
        candidate = parent / f"{stem}_{i}{suffix}"
        if not candidate.exists():
            return candidate
        i += 1

def backup_script(pyfile: Path, iter_num: int, backup_dir: Path, tag: str = "") -> None:
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    base_stem = pyfile.stem
    if tag:
        backup_file = backup_dir / f"{base_stem}_{tag}_iter{iter_num}_{ts}.py"
    else:
        backup_file = backup_dir / f"{base_stem}_iter{iter_num}_{ts}.py"
    backup_file.write_text(pyfile.read_text(encoding="utf-8"), encoding="utf-8")

def analyze_node_conf_dir(case_dir: Path) -> dict:
    """
    Scan all node directories (e.g., r1, r2, ...) in the case directory,
    collect .conf filenames and optionally file sizes or first lines for summary.
    """
    node_dirs = [d for d in case_dir.iterdir() if d.is_dir() and re.match(r"r\d+$", d.name)]
    conf_summary = {}
    for node in node_dirs:
        conf_files = [f for f in node.glob("*.conf")]
        conf_summary[node.name] = [f.name for f in conf_files]
    return conf_summary

def build_prompt(case_name, py_code: str, topo_json: str, err: str, conf_summary: dict, system_prompt: str) -> str:
    # Compose a clear, well-structured prompt for LLM model
    prompt = textwrap.dedent(f"""
    {system_prompt}

    === Current test_{case_name}.py ===
    {py_code}

    === {case_name}.json (Topology) ===
    {topo_json}

    === Directory summary of all node conf files (format: {{node: [conf files]}}) ===
    {json.dumps(conf_summary, indent=2)}

    === Pytest error log snippet ===
    {err}

    STRICT OUTPUT INSTRUCTION:
    Only reply with valid, executable python code for test_{case_name}.py.
    Do NOT add explanations, markdown, or comments.
    """)
    return prompt

def send_prompt_to_llm(prompt: str, host: str, port: int, timeout: int = SOCKET_TIMEOUT) -> str | None:
    """
    Send a prompt string to the edge LLM model server via socket, receive the result.
    Returns the generated python code as a string, or None on failure.
    """
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            # Send length-prefixed prompt for robustness
            prompt_bytes = prompt.encode('utf-8')
            sock.sendall(f"{len(prompt_bytes)}\n".encode())
            sock.sendall(prompt_bytes)
            # Receive reply (length-prefixed)
            reply_len_line = b''
            while not reply_len_line.endswith(b'\n'):
                chunk = sock.recv(1)
                if not chunk:
                    break
                reply_len_line += chunk
            if not reply_len_line:
                return None
            reply_len = int(reply_len_line.strip())
            received = b''
            while len(received) < reply_len:
                chunk = sock.recv(min(4096, reply_len - len(received)))
                if not chunk:
                    break
                received += chunk
            return received.decode('utf-8')
    except Exception as e:
        print(f"[ERROR] Socket communication with edge LLM failed: {e}")
        return None

# --------------------------------------------------------------------------- #
# Main Loop
# --------------------------------------------------------------------------- #
def main():
    py_files = sorted(PY_SRC_DIR.glob("*.py"))
    total, passed, failed, skipped = 0, 0, 0, 0

    for py_path in py_files:
        total += 1
        case_base = py_path.stem.split("&")[0]
        case_dir = TOPOTESTS_ROOT / case_base
        test_py = case_dir / f"test_{case_base}.py"
        json_topo = JSON_SRC_DIR / f"{case_base}.json"
        base_log_path = LOG_DIR / f"{case_base}_test_log.txt"
        log_path = get_nonconflicting_filename(base_log_path)

        if not (case_dir.exists() and json_topo.exists()):
            print(f"[SKIP] {case_base} (missing folder or json)")
            skipped += 1
            continue

        # Overwrite test_xxx.py with initial candidate script
        try:
            shutil.copy(py_path, test_py)
        except Exception:
            print(f"[SKIP] {case_base} (py copy fail)")
            skipped += 1
            continue

        # Backup initial script
        if test_py.exists():
            tag = log_path.stem.replace("_test_log", "")
            backup_script(test_py, 0, BACKUP_ROOT, tag=tag)

        log_data = {
            "case_name": case_base,
            "result": None,
            "pass_iter": None,
            "iterations": [],
            "start_time": datetime.now().isoformat(),
        }

        case_success = False
        for it in range(1, ITER_MAX + 1):
            print(f"========== ITER {it}/{ITER_MAX} ({case_base}) ==========")
            iter_info = {
                "iter": it,
                "success": False,
            }

            res = run_pytest(test_py, case_dir)
            iter_info["pytest_returncode"] = res.returncode

            if res.returncode == 0:
                log_data["result"] = "PASS"
                log_data["pass_iter"] = it
                iter_info["success"] = True
                log_data["iterations"].append(iter_info)
                passed += 1
                case_success = True
                break

            # Backup every iteration script
            if test_py.exists():
                tag = log_path.stem.replace("_test_log", "")
                backup_script(test_py, it, BACKUP_ROOT, tag=tag)

            # Build next prompt
            err_snippet = extract_error(res.stdout + res.stderr)
            current_py  = test_py.read_text(encoding="utf-8") if test_py.exists() else ""
            topo_json   = json_topo.read_text(encoding="utf-8")
            conf_summary = analyze_node_conf_dir(case_dir)
            prompt      = build_prompt(case_base, current_py, topo_json, err_snippet, conf_summary, SYSTEM_PROMPT)

            t0 = time.time()
            llm_reply = send_prompt_to_llm(prompt, LLM_HOST, LLM_PORT, timeout=SOCKET_TIMEOUT)
            llm_time = time.time() - t0
            iter_info["llm_time_sec"] = llm_time

            if not llm_reply:
                print(f"[ERROR] No response from edge LLM for {case_base}, iter {it}")
                log_data["iterations"].append(iter_info)
                log_data["result"] = "LLM_FAIL"
                failed += 1
                break

            new_code = sanitize_code(llm_reply)
            if not re.search(r"\bimport\b|\bdef\b", new_code):
                print(f"[WARN] No valid python code in reply for {case_base}, iter {it}")
                log_data["iterations"].append(iter_info)
                continue

            test_py.write_text(new_code, encoding="utf-8")
            log_data["iterations"].append(iter_info)

        if log_data.get("result") != "PASS":
            log_data["result"] = "FAIL"
            failed += 1

        log_data["end_time"] = datetime.now().isoformat()
        # Write log file
        with open(log_path, "w", encoding="utf-8") as f:
            f.write(json.dumps(log_data, indent=2))
        # Terminal summary
        if log_data["result"] == "PASS":
            print(f"[PASS] {case_base} validated in {log_data['pass_iter']} iterations (log: {log_path.name})")
        else:
            print(f"[FAIL] {case_base} (after {ITER_MAX} iterations, log: {log_path.name})")

    print(f"\n[ALL DONE] total={total}, passed={passed}, failed={failed}, skipped={skipped}")

if __name__ == "__main__":
    main()
