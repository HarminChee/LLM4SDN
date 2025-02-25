import os
import json
import random
import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim

from torch.utils.data import Dataset, DataLoader
import matplotlib.pyplot as plt
import seaborn as sns
from numpy.linalg import norm

########################################################
# 1. 解析 JSON => 提取“文件级”特征向量
#    这里扩充更多字段并做示例演示
########################################################
def parse_json_to_features(json_path):
    """
    从 JSON 中解析多种字段, 返回一个长度较高的特征向量 (numpy array).
    如果 JSON 结构中缺少某些字段, 就用默认值/0 表示.

    注意：你可以按需增/删特征，本示例仅做演示.
    """

    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except:
        return None

    # 在此定义特征维度, 你可以自行再加. 
    # 这里示例定义 15 维.
    # 0: number of "routers"
    # 1: number of "switches"
    # 2: number of "nodes" (if "nodes" in data)
    # 3: sum of node.interfaces across "nodes" dict
    # 4: sum of router.interfaces across "routers" dict
    # 5: number of "links"
    # 6: sum of local_as in routers
    # 7: count how many routers have BGP local_as
    # 8: count how many routers have OSPF
    # 9: count how many routers have OSPFv6 / ospf6
    # 10: sum of static_routes across all routers
    # 11: do we have address_types? (0 or number of address types)
    # 12: count total "switches[x].connected_nodes"
    # 13: has IPv4 base? (1 if "ipv4base" in data else 0)
    # 14: has IPv6 base? (1 if "ipv6base" in data else 0)

    feat = np.zeros(15, dtype=float)

    # 1) routers
    router_count = 0
    router_data = {}
    if "routers" in data and isinstance(data["routers"], dict):
        router_data = data["routers"]
        router_count = len(router_data)
    feat[0] = float(router_count)

    # 2) switches
    switch_count = 0
    switch_data = {}
    if "switches" in data and isinstance(data["switches"], dict):
        switch_data = data["switches"]
        switch_count = len(switch_data)
    feat[1] = float(switch_count)

    # 3) nodes
    node_count = 0
    node_data = {}
    # 有些 JSON 用 "nodes"->dict, 有的用 "nodes"->list, 还有的干脆没有 "nodes"
    # 这里仅演示如果是 dict
    if "nodes" in data and isinstance(data["nodes"], dict):
        node_data = data["nodes"]
        node_count = len(node_data)
    elif "nodes" in data and isinstance(data["nodes"], list):
        node_list = data["nodes"]
        node_count = len(node_list)
    feat[2] = float(node_count)

    # 4) sum of node.interfaces across data["nodes"]
    #    这里只示例: if "nodes":{ "r1":{interfaces:{...}},... }
    node_if_sum = 0
    for nd_id, nd_info in node_data.items():
        if "interfaces" in nd_info and isinstance(nd_info["interfaces"], dict):
            node_if_sum += len(nd_info["interfaces"])
    feat[3] = float(node_if_sum)

    # 5) sum of router.interfaces across data["routers"]
    router_if_sum = 0
    for rid, rinfo in router_data.items():
        if "interfaces" in rinfo:
            if isinstance(rinfo["interfaces"], dict):
                router_if_sum += len(rinfo["interfaces"])
            elif isinstance(rinfo["interfaces"], list):
                router_if_sum += len(rinfo["interfaces"])
    feat[4] = float(router_if_sum)

    # 6) links
    link_count = 0
    if "links" in data and isinstance(data["links"], list):
        link_count = len(data["links"])
    feat[5] = float(link_count)

    # 7) BGP local_as
    local_as_sum = 0
    local_as_count = 0
    # 8) OSPF count
    ospf_count = 0
    # 9) OSPFv6 or ospf6 count
    ospf6_count = 0
    # 10) sum of static_routes
    static_count = 0

    for rid, rinfo in router_data.items():
        # BGP
        bgp_obj = rinfo.get("bgp", {})
        if isinstance(bgp_obj, dict):
            possible_as = bgp_obj.get("local_as") or bgp_obj.get("as_number")
            if possible_as:
                try:
                    val = float(possible_as)
                    local_as_sum += val
                    local_as_count += 1
                except:
                    pass
            # 如果 "address_family" 下有 neighbor, static routes等可以再查
            if "address_family" in bgp_obj and isinstance(bgp_obj["address_family"], dict):
                # 也可数一数 neighbor
                pass
        # OSPF
        if "ospf" in rinfo:
            ospf_count += 1
        if "ospf6" in rinfo:
            ospf6_count += 1

        # static_routes
        if "static_routes" in rinfo and isinstance(rinfo["static_routes"], list):
            static_count += len(rinfo["static_routes"])

    feat[6] = float(local_as_sum)
    feat[7] = float(local_as_count)
    feat[8] = float(ospf_count)
    feat[9] = float(ospf6_count)
    feat[10] = float(static_count)

    # 11) address_types
    # 如果 "address_types" in data => 记下其数量
    if "address_types" in data and isinstance(data["address_types"], list):
        feat[11] = float(len(data["address_types"]))

    # 12) total "connected_nodes" in all switches
    connected_nodes_sum = 0
    for swid, swinfo in switch_data.items():
        if "connected_nodes" in swinfo and isinstance(swinfo["connected_nodes"], list):
            connected_nodes_sum += len(swinfo["connected_nodes"])
    feat[12] = float(connected_nodes_sum)

    # 13) has ipv4base
    if "ipv4base" in data:
        feat[13] = 1.0
    # 14) has ipv6base
    if "ipv6base" in data:
        feat[14] = 1.0

    return feat


########################################################
# 2. 数据集: 先收集所有特征 => 做全局标准化 => 再返回
########################################################
class JSONDataset(Dataset):
    def __init__(self, folder, max_files=None):
        """
        folder: json文件所在目录
        max_files: 可选，只加载一定数量
        """
        self.filepaths = []
        self.features = []
        json_files = sorted([f for f in os.listdir(folder) if f.lower().endswith(".json")])

        if max_files is not None and max_files < len(json_files):
            random.shuffle(json_files)
            json_files = json_files[:max_files]

        # 先做第一遍：收集所有特征(不转 tensor)
        all_feats = []
        all_names = []
        for fname in json_files:
            path = os.path.join(folder, fname)
            feat = parse_json_to_features(path)
            if feat is not None:
                all_feats.append(feat)
                all_names.append((fname, path))

        if not all_feats:
            # 数据为空
            self.filepaths = []
            self.features = []
            return

        feats_arr = np.stack(all_feats, axis=0)  # shape=(N, F)

        # 对 feats_arr 做标准化 => (x-mean)/std
        mean_ = feats_arr.mean(axis=0, keepdims=True)
        std_  = feats_arr.std(axis=0, keepdims=True)
        std_[std_<1e-9] = 1.0  # 避免除0

        feats_norm = (feats_arr - mean_)/std_

        self.features = feats_norm
        self.filepaths = all_names  # list of (fname, path)

    def __len__(self):
        return len(self.features)

    def __getitem__(self, idx):
        """
        返回 (filename, feat_tensor)
        """
        fname, _ = self.filepaths[idx]
        feat_1d = self.features[idx]
        feat_tensor = torch.tensor(feat_1d, dtype=torch.float)
        return fname, feat_tensor


########################################################
# 3. 简易 MLP AutoEncoder
########################################################
class MLPAutoEncoder(nn.Module):
    def __init__(self, in_dim, hidden_dim=16):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(in_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim)
        )
        self.decoder = nn.Sequential(
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, in_dim)
        )

    def forward(self, x):
        z = self.encoder(x)
        x_recon = self.decoder(z)
        return x_recon, z


########################################################
# 4. 训练
########################################################
def train_ae(model, dataset, epochs=20, batch_size=8, lr=1e-3, device='cpu'):
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)
    optimizer = optim.Adam(model.parameters(), lr=lr)
    criterion = nn.MSELoss()

    model.train()
    for ep in range(1, epochs+1):
        total_loss = 0.0
        count = 0
        for batch_items in loader:
            fnames, feats = batch_items
            feats = feats.to(device)

            optimizer.zero_grad()
            x_recon, z = model(feats)
            loss = criterion(x_recon, feats)
            loss.backward()
            optimizer.step()

            total_loss += loss.item()
            count += 1

        avg_loss = total_loss / count if count>0 else 0
        print(f"Epoch {ep}/{epochs}, Loss={avg_loss:.6f}")


########################################################
# 5. 获取embedding & 画相似度热力图 (cos=1=>红, cos=-1=>蓝)
########################################################
def compute_embeddings(model, dataset, device='cpu'):
    model.eval()
    name2emb = {}
    with torch.no_grad():
        for idx in range(len(dataset)):
            fname, feat_tensor = dataset[idx]
            feat_tensor = feat_tensor.unsqueeze(0).to(device)
            x_recon, z = model(feat_tensor)
            z_np = z.squeeze(0).cpu().numpy()
            name2emb[fname] = z_np
    return name2emb


def show_similarity_heatmap(name2emb):
    names = sorted(name2emb.keys())
    if len(names)==0:
        print("No data => can't show heatmap.")
        return

    emb_list = [name2emb[n] for n in names]
    emb_mat  = np.stack(emb_list, axis=0)  # (N, hidden_dim)
    N = emb_mat.shape[0]

    sim_mat = np.zeros((N,N), dtype=float)
    for i in range(N):
        for j in range(N):
            dot_ij = np.dot(emb_mat[i], emb_mat[j])
            norm_i = norm(emb_mat[i])
            norm_j = norm(emb_mat[j])
            if norm_i<1e-9 or norm_j<1e-9:
                sim_mat[i,j] = 0
            else:
                sim_mat[i,j] = dot_ij/(norm_i*norm_j)

    # 让 cos=+1 => 红, cos=-1 => 蓝
    # 可以使用 "coolwarm" 或 "bwr" colormap
    # "coolwarm" 在 vmax=1 时是红色，vmin=-1 时是蓝色
    plt.figure(figsize=(10,8))
    sns.heatmap(
        sim_mat, 
        xticklabels=names, 
        yticklabels=names,
        cmap="coolwarm",
        vmin=-1, vmax=1
    )
    plt.title("Cosine Similarity of JSON-based embeddings (autoencoder)")
    plt.tight_layout()
    plt.show()


########################################################
# 6. 主函数
########################################################
if __name__=="__main__":
    import sys
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("Using device:", device)

    # 你可以按需修改
    json_folder = r"C:\Users\harmi\Desktop\sdn\json_clear"
    dataset = JSONDataset(json_folder, max_files=50)  # 例如加载50个
    print(f"Loaded {len(dataset)} json files => dataset samples.")
    if len(dataset) == 0:
        sys.exit("No data => stop.")

    feat_dim = len(dataset[0][1])  # (filename, feat_tensor) => feat_tensor长度
    model = MLPAutoEncoder(in_dim=feat_dim, hidden_dim=16).to(device)

    # 调低学习率, 以免loss波动过大; 数据已做标准化 => loss不会那么夸张
    train_ae(model, dataset, epochs=20, batch_size=8, lr=5e-4, device=device)

    name2emb = compute_embeddings(model, dataset, device=device)
    show_similarity_heatmap(name2emb)
