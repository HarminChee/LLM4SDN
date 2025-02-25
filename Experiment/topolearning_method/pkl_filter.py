import os
import pickle

def check_pkl_folder(pkl_folder):
    """
    遍历 pkl_folder 中的所有 .pkl 文件：
    1) 加载 SimplicialComplex
    2) 统计 rank=0 (nodes) 和 rank=1 (edges) 数量
    3) 打印结果
    """
    pkl_files = sorted(f for f in os.listdir(pkl_folder) if f.endswith(".pkl"))

    if not pkl_files:
        print(f"[INFO] No .pkl files found in {pkl_folder}")
        return

    for fname in pkl_files:
        full_path = os.path.join(pkl_folder, fname)
        try:
            with open(full_path, "rb") as f:
                sc = pickle.load(f)
        except Exception as e:
            print(f"[ERROR] Unable to load {fname}: {e}")
            continue

        # rank=0 的单形 => 节点
        rank0_list = [s for s in sc if len(s) == 1]
        # rank=1 的单形 => 边
        rank1_list = [s for s in sc if len(s) == 2]

        print(f"{fname}: #nodes={len(rank0_list)}, #edges={len(rank1_list)}")

if __name__ == "__main__":
    pkl_folder = r"C:\Users\harmi\Desktop\sdn\cc_pickles"  # 你的输出 .pkl 文件夹
    check_pkl_folder(pkl_folder)
