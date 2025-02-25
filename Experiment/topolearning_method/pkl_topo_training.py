
import os
import pickle
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader

import numpy as np
import random
import matplotlib.pyplot as plt
import seaborn as sns
from numpy.linalg import norm


########################################################
# 1. Dataset: node-level. 先收集全部特征 => 全局归一化
########################################################
class NodeLevelDataset(Dataset):
    def __init__(self, pkl_folder):
        """
        参数:
          pkl_folder: 存放 .pkl 文件的目录
        功能:
          1) 扫描所有 pkl 文件, 提取其 rank=0 节点的特征 (如 bgp_local_as, bgp_neighbor_count...),
             并先行收集到 self.all_features 做全局统计.
          2) 计算全局 mean/std 后, 再次扫描, 构造 self.samples:
               每个样本形如 {"name": <文件名>, "x_0": <(n_nodes,feat_dim)张量>}
        """

        self.samples = []
        self.all_features = []  
        self.feature_names = [
            "bgp_local_as",
            "ospf_area",
            "interfaces_count",
            "bgp_neighbor_count",
            "bgp_network_count",
            "route_map_count",
            "static_rt_count",

        ]

        pkl_files = sorted([f for f in os.listdir(pkl_folder) if f.endswith(".pkl")])
        

        for fname in pkl_files:
            full_path = os.path.join(pkl_folder, fname)
            try:
                sc = pickle.load(open(full_path, "rb"))
            except Exception as e:
                print(f"[ERROR] Fail to load {fname}: {e}")
                continue

            node_list = [face for face in sc if len(face) == 1]
            if not node_list:
                print(f"[INFO] {fname} => no rank=0 face => skip")
                continue

            feat_list = []
            for single_node in node_list:
                if single_node not in sc:
                    continue

                node_data = sc[single_node]  


                feats_one_node = []
                for feat_name in self.feature_names:
                    val = float(node_data.get(feat_name, 0.0))
                    feats_one_node.append(val)

                vendor_str = str(node_data.get("vendor", "")).lower()
                vendor_flag = 1.0 if "cisco" in vendor_str else 0.0
                feats_one_node.append(vendor_flag)  

                feat_list.append(feats_one_node)

            if not feat_list:
                continue

 
            self.all_features.extend(feat_list)


        if not self.all_features:
            print("[WARN] No node features found in entire dataset!")
            return


        all_feat_tensor = torch.tensor(self.all_features, dtype=torch.float)
        
        self.global_mean = all_feat_tensor.mean(dim=0, keepdim=True)
        self.global_std  = all_feat_tensor.std(dim=0, keepdim=True) + 1e-9

        self.samples = []
        for fname in pkl_files:
            full_path = os.path.join(pkl_folder, fname)
            try:
                sc = pickle.load(open(full_path, "rb"))
            except Exception as e:
                continue

            node_list = [face for face in sc if len(face) == 1]
            if not node_list:
                continue

            feat_list = []
            for single_node in node_list:
                if single_node not in sc:
                    continue

                node_data = sc[single_node]

                feats_one_node = []
                for feat_name in self.feature_names:
                    val = float(node_data.get(feat_name, 0.0))
                    feats_one_node.append(val)

                # 再加 vendor_flag
                vendor_str = str(node_data.get("vendor", "")).lower()
                vendor_flag = 1.0 if "cisco" in vendor_str else 0.0
                feats_one_node.append(vendor_flag)

                feat_list.append(feats_one_node)

            if not feat_list:
                continue

            x_0 = torch.tensor(feat_list, dtype=torch.float)
            x_0 = (x_0 - self.global_mean) / self.global_std

            self.samples.append({
                "name": fname,
                "x_0": x_0
            })

        print(f"[DEBUG] NodeLevelDataset => loaded {len(self.samples)} files total.")
        print(f"[DEBUG] global_mean={self.global_mean}, global_std={self.global_std}")

    def __len__(self):
        return len(self.samples)

    def __getitem__(self, idx):
        return self.samples[idx]


########################################################
# 2. 增广函数: (先关掉随机丢弃，用于调试)
########################################################
def random_augment_node(x_0, drop_node_p=0.0, drop_feat_p=0.0):
    """
    先暂时关掉 node/feat 的随机丢弃，用于观察是否能学到差异
    """
    return x_0.clone()


########################################################
# 3. Node-level对比模型: MLP => (n_nodes, hidden_dim)
#    => mean pool => (hidden_dim)
########################################################
class NodeContrastiveModel(nn.Module):
    def __init__(self, in_dim, hidden_dim):
        super().__init__()
        self.encoder = nn.Sequential(
            nn.Linear(in_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim)
        )

    def forward(self, x_0):
        """
        x_0: (n_nodes, in_dim)
        返回 z_mean: (hidden_dim,)
        """
        z = self.encoder(x_0)
        z_mean = z.mean(dim=0)
        return z_mean


########################################################
# 4. 对比损失: SimCLR
########################################################
def contrastive_loss(z_list, temperature=0.5):
    big_z = torch.stack(z_list, dim=0)
    big_z = nn.functional.normalize(big_z, dim=1)
    n_samples = big_z.size(0)
    sim_matrix = big_z @ big_z.t()

    loss_list = []
    for i in range(0, n_samples, 2):
        j = i+1
        sim_ij = sim_matrix[i,j]/temperature
        mask_i = torch.ones(n_samples, dtype=torch.bool, device=big_z.device)
        mask_i[i] = False
        sim_i_all = sim_matrix[i][mask_i]/temperature

        num = torch.exp(sim_ij)
        den = torch.sum(torch.exp(sim_i_all))
        if den<=0 or torch.isnan(den):
            return torch.tensor(float('nan'), device=big_z.device)
        loss_i = -torch.log(num/den)
        loss_list.append(loss_i)

        sim_ji = sim_matrix[j,i]/temperature
        mask_j = torch.ones(n_samples, dtype=torch.bool, device=big_z.device)
        mask_j[j] = False
        sim_j_all = sim_matrix[j][mask_j]/temperature

        num_j = torch.exp(sim_ji)
        den_j = torch.sum(torch.exp(sim_j_all))
        if den_j<=0 or torch.isnan(den_j):
            return torch.tensor(float('nan'), device=big_z.device)
        loss_j = -torch.log(num_j/den_j)
        loss_list.append(loss_j)

    return torch.mean(torch.stack(loss_list))


########################################################
# 5. 训练
########################################################
def train_contrastive_nodelevel(model, dataset, epochs=10, lr=1e-3,
                                device='cpu', drop_node_p=0.0, drop_feat_p=0.0,
                                batch_size=4):
    model.train()
    optimizer = optim.Adam(model.parameters(), lr=lr)

    def collate_fn(batch):
        return batch

    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True, drop_last=True, collate_fn=collate_fn)

    for ep in range(1, epochs+1):
        total_loss=0.0
        batch_count=0
        for samples in loader:
            z_list=[]
            for s in samples:
                x_0 = s["x_0"].to(device)

                x_a = random_augment_node(x_0, drop_node_p, drop_feat_p)
                x_b = random_augment_node(x_0, drop_node_p, drop_feat_p)

                z_a = model(x_a)
                z_b = model(x_b)

                z_list.append(z_a)
                z_list.append(z_b)

            if len(z_list)<2:
                continue

            loss=contrastive_loss(z_list, temperature=0.5)
            if torch.isnan(loss):
                print(f"[ERROR] Found NaN at epoch={ep}, stop training.")
                return

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss+=loss.item()
            batch_count+=1

        avg_loss = total_loss/batch_count if batch_count>0 else 0
        print(f"Epoch {ep}/{epochs}, Contr.NodeLoss={avg_loss:.6f}")


########################################################
# 6. 计算embedding & 画相似度热力图
########################################################
def compute_embeddings_nodelevel(model, dataset, device='cpu'):
    model.eval()
    name2emb={}
    with torch.no_grad():
        for s in dataset:
            fname=s["name"]
            x_0 = s["x_0"].to(device)
            emb=model(x_0).cpu().numpy()
            name2emb[fname]=emb
    return name2emb

def show_similarity_heatmap(name2emb, title="Node-level Contrastive CosineSim"):
    names=sorted(name2emb.keys())
    if not names:
        print("[WARN] name2emb empty => no heatmap.")
        return
    emb_list=[name2emb[n] for n in names]
    emb_mat=np.stack(emb_list, axis=0)
    N=emb_mat.shape[0]

    sim_mat=np.zeros((N,N))
    for i in range(N):
        for j in range(N):
            dot_ij=np.dot(emb_mat[i], emb_mat[j])
            norm_i=norm(emb_mat[i])
            norm_j=norm(emb_mat[j])
            if norm_i<1e-9 or norm_j<1e-9:
                sim_mat[i,j]=0
            else:
                sim_mat[i,j]=dot_ij/(norm_i*norm_j)

    plt.figure(figsize=(10,8))
    sns.heatmap(sim_mat,
                xticklabels=names,
                yticklabels=names,
                cmap="RdBu",
                vmin=-1, vmax=1)
    plt.title(title)
    plt.tight_layout()
    plt.show()


########################################################
# 7. 主函数
########################################################
if __name__=="__main__":
    import sys
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("Using device:", device)

    pkl_folder = r"C:\Users\harmi\Desktop\sdn\cc_pickles"
    dataset = NodeLevelDataset(pkl_folder)
    print("Loaded", len(dataset), "pkl with rank=0 nodes (some may have 0 edges).")
    if len(dataset)==0:
        sys.exit("No node data => exit")

    in_dim = dataset[0]["x_0"].size(1)  # 预期=4
    hidden_dim=16

    model=NodeContrastiveModel(in_dim, hidden_dim).to(device)

    # 先把drop_node_p, drop_feat_p设为0
    train_contrastive_nodelevel(model, dataset,
                                epochs=20, lr=1e-3,
                                device=device,
                                drop_node_p=0.0,
                                drop_feat_p=0.0,
                                batch_size=4)

    name2emb = compute_embeddings_nodelevel(model, dataset, device=device)
    show_similarity_heatmap(name2emb, title="Node-level Contrastive CosineSim")
