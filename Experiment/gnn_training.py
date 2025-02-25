
import os
import json
import random
import numpy as np
import networkx as nx
import torch
import torch.nn as nn
import torch.optim as optim
from torch_geometric.data import Data, Dataset, DataLoader
from torch_geometric.nn import GCNConv, global_mean_pool
import matplotlib.pyplot as plt
import seaborn as sns
from numpy.linalg import norm

###############################################################################
# 1. 读取 JSON => 只关注 router/switch/links
#    => 构建无向图 => 提取节点特征: 
#       - node_type (router/switch) => one-hot 
#       - node_degree => scalar
#       - config_count => optional(默认0), 代表一些简单“配置差异”
###############################################################################
def parse_topo_from_json(json_path):
    try:
        with open(json_path,'r',encoding='utf-8') as f:
            data = json.load(f)
    except:
        return None

    # Collect routers & switches
    nodes = []
    node_types = []
    name2idx = {}
    idx_count = 0

    routers = data.get("routers", {})
    if isinstance(routers, dict):
        for r_id, r_info in routers.items():
            nodes.append(r_id)
            node_types.append(r_info.get("type","router"))
            name2idx[r_id] = idx_count
            idx_count+=1

    switches = data.get("switches", {})
    if isinstance(switches, dict):
        for s_id, s_info in switches.items():
            nodes.append(s_id)
            node_types.append(s_info.get("type","switch"))
            name2idx[s_id] = idx_count
            idx_count+=1

    if idx_count==0:
        return None

    # edges
    edges=[]
    links = data.get("links", [])
    if isinstance(links, list):
        for lk in links:
            src = lk.get("source")
            tgt = lk.get("target")
            if src in name2idx and tgt in name2idx:
                s_idx = name2idx[src]
                t_idx = name2idx[tgt]
                edges.append((s_idx,t_idx))
                edges.append((t_idx,s_idx))

    G = nx.Graph()
    G.add_nodes_from(range(idx_count))
    G.add_edges_from(edges)

    x_list=[]
    for i,name_type in enumerate(node_types):
        deg = G.degree(i)

        if name_type.lower()=="router":
            type_feat = [1,0]
        else:
            type_feat = [0,1]

        config_count = 0
        node_name = nodes[i]
        if node_name in routers:
            r_info = routers[node_name]
            if "bgp" in r_info: 
                config_count+=1
            if "ospf" in r_info:
                config_count+=1
        elif node_name in switches:
            s_info = switches[node_name]

        feat = type_feat + [float(deg), float(config_count)]
        x_list.append(feat)

    x = torch.tensor(x_list, dtype=torch.float) 
    edge_index = None
    if len(edges)>0:
        e_np = np.array(edges,dtype=np.int64).T
        edge_index = torch.from_numpy(e_np)
    else:
        edge_index = torch.zeros((2,0), dtype=torch.long)

    data_pyG = Data(x=x, edge_index=edge_index)
    return data_pyG

###############################################################################
# 2. PyG Dataset => load all JSON from a folder
###############################################################################
class TopoGraphDataset(Dataset):
    def __init__(self, json_dir):
        super().__init__()
        self.json_dir = json_dir
        self.files = sorted([f for f in os.listdir(json_dir) if f.endswith('.json')])
        self.data_list=[]
        self.names=[]
        for f in self.files:
            fullp = os.path.join(json_dir, f)
            data_pyG = parse_topo_from_json(fullp)
            if data_pyG is not None:
                self.data_list.append(data_pyG)
                self.names.append(f)

    def len(self):
        return len(self.data_list)

    def get(self,idx):
        return self.data_list[idx]

    def get_name(self, idx):
        return self.names[idx]

###############################################################################
# 3. Data augmentation => GraphCL style
#    random drop edges, random drop nodes
###############################################################################
def random_drop_edges(data_pyG, drop_prob=0.2):
    edge_index = data_pyG.edge_index
    col = edge_index.size(1)
    if col==0:
        return data_pyG  # no edges => do nothing

    n_edges = col//2
    if n_edges<=0:
        return data_pyG

    keep_mask = (torch.rand(n_edges)>drop_prob)
    if not keep_mask.any():
        keep_mask[0]=True

    new_edges=[]
    keep_idx = torch.where(keep_mask)[0]
    for i in keep_idx:
        s_i=2*i
        t_i=2*i+1
        if s_i<col and t_i<col:
            s_src = edge_index[0,s_i]
            s_tgt = edge_index[1,s_i]
            t_src = edge_index[0,t_i]
            t_tgt = edge_index[1,t_i]
            new_edges.append((s_src.item(), s_tgt.item()))
            new_edges.append((t_src.item(), t_tgt.item()))

    data_aug = data_pyG.clone()
    if len(new_edges)==0:
        data_aug.edge_index = torch.zeros((2,0),dtype=torch.long)
    else:
        e_np = np.array(new_edges,dtype=np.int64).T
        data_aug.edge_index = torch.from_numpy(e_np)
    return data_aug

def random_drop_nodes(data_pyG, drop_prob=0.1):
    n = data_pyG.x.size(0)
    if n<=1:
        return data_pyG

    keep_mask = (torch.rand(n)>drop_prob)
    if not keep_mask.any():
        keep_mask[0]=True

    idx_new = torch.where(keep_mask)[0]
    if idx_new.size(0)==n:
        return data_pyG  # no node dropped
    if idx_new.size(0)==0:
        return data_pyG  # all dropped => revert

    old2new = {}
    for i,old_id in enumerate(idx_new):
        old2new[old_id.item()]=i

    new_x = data_pyG.x[idx_new].clone()
    old_edges = data_pyG.edge_index.t().numpy().tolist()
    new_edges=[]
    for s_i, t_i in old_edges:
        if s_i in old2new and t_i in old2new:
            new_edges.append((old2new[s_i], old2new[t_i]))

    data_aug = data_pyG.clone()
    data_aug.x = new_x
    if len(new_edges)==0:
        data_aug.edge_index = torch.zeros((2,0),dtype=torch.long)
    else:
        e_np = np.array(new_edges,dtype=np.int64).T
        data_aug.edge_index = torch.from_numpy(e_np)
    return data_aug

def graph_augment(data_pyG, drop_edge_p=0.2, drop_node_p=0.1):
    d1 = random_drop_edges(data_pyG, drop_edge_p)
    d2 = random_drop_nodes(d1, drop_node_p)
    return d2



###############################################################################
# 4. GNN Model
###############################################################################
class GCNEncoder(nn.Module):
    def __init__(self, in_dim, hidden_dim, out_dim=32):
        super().__init__()
        self.conv1 = GCNConv(in_dim, hidden_dim)
        self.conv2 = GCNConv(hidden_dim, hidden_dim)
        self.conv3 = GCNConv(hidden_dim, out_dim)

    def forward(self, data):
        x, edge_index = data.x, data.edge_index
        x = self.conv1(x, edge_index)
        x = torch.relu(x)
        x = self.conv2(x, edge_index)
        x = torch.relu(x)
        x = self.conv3(x, edge_index)
        return x  # shape=(N, out_dim)

def global_pool_embed(x_mat):
    # mean pool
    emb = x_mat.mean(dim=0)  # shape=(out_dim,)
    return emb

###############################################################################
# 5. 自监督对比学习: InfoNCE / GraphCL style
#    for batch of graphs => each graph do 2 augment => embed => 2B embeddings => loss
###############################################################################
def sim_matrix_cos(z):
    # z => (n_samples, dim)
    z_norm = z / (z.norm(dim=1, keepdim=True)+1e-9)
    sim = z_norm @ z_norm.t()
    return sim

def contrastive_loss(z, batch_size, temperature=0.2):
    """
    z: (2B, dim), (0,1) is pair, (2,3) is pair, etc...
    2B x dim
    InfoNCE => see GraphCL style
    """
    sim_mat = sim_matrix_cos(z)
    n = z.size(0)
    half = n//2
    losses=[]
    for i in range(0, n, 2):
        j = i+1
        # i->j
        sim_ij = sim_mat[i,j]/temperature
        # exclude i
        mask_i = torch.ones(n, dtype=torch.bool, device=z.device)
        mask_i[i]=False
        sim_i_all = sim_mat[i][mask_i]/temperature
        num = torch.exp(sim_ij)
        den = torch.sum(torch.exp(sim_i_all))
        loss_i = -torch.log(num/den)
        losses.append(loss_i)

        # j->i
        sim_ji = sim_mat[j,i]/temperature
        mask_j = torch.ones(n,dtype=torch.bool, device=z.device)
        mask_j[j]=False
        sim_j_all = sim_mat[j][mask_j]/temperature
        num_j = torch.exp(sim_ji)
        den_j = torch.sum(torch.exp(sim_j_all))
        loss_j = -torch.log(num_j/den_j)
        losses.append(loss_j)
    return torch.mean(torch.stack(losses))

###############################################################################
# 6. Node-level => Graph-level => do InfoNCE
###############################################################################
def train_graphcl(dataset, model, epochs=20, lr=1e-3, device='cpu',
                  drop_edge_p=0.2, drop_node_p=0.1, batch_size=4):
    model.train()
    optimizer = optim.Adam(model.parameters(), lr=lr)

    # collate => just group
    def collate_fn(batch_list):
        return batch_list

    loader = DataLoader(range(dataset.len()), batch_size=batch_size,
                        shuffle=True, drop_last=True,
                        collate_fn=collate_fn)
    for ep in range(1, epochs+1):
        total_loss=0.
        batch_count=0
        for idx_list in loader:
            # idx_list => some indices
            z_list=[]
            for idx in idx_list:
                data_orig = dataset.get(idx).to(device)

                # 2 augment
                aug1 = graph_augment(data_orig, drop_edge_p, drop_node_p)
                aug2 = graph_augment(data_orig, drop_edge_p, drop_node_p)

                # embed
                x1 = model(aug1)
                if x1.size(0)==0:
                    continue
                g1 = global_mean_pool(x1, torch.zeros(x1.size(0),dtype=torch.long, device=x1.device))
                g1 = g1.view(-1)  # => (out_dim,)

                x2 = model(aug2)
                if x2.size(0)==0:
                    continue
                g2 = global_mean_pool(x2, torch.zeros(x2.size(0),dtype=torch.long, device=x2.device))
                g2 = g2.view(-1)

                z_list.append(g1)
                z_list.append(g2)

            if len(z_list)<2:
                continue
            
            z_big = torch.stack(z_list, dim=0) # shape=(2B, out_dim)
            loss=contrastive_loss(z_big, batch_size, temperature=0.2)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss+=loss.item()
            batch_count+=1
        avg_loss= total_loss/batch_count if batch_count>0 else 0
        print(f"[Ep {ep}/{epochs}] Loss={avg_loss:.6f}")

###############################################################################
# 7. 最后 => compute embeddings => 画相似度热力图
###############################################################################
def compute_graph_embeddings(dataset, model, device='cpu'):
    model.eval()
    name2emb={}
    with torch.no_grad():
        for i in range(dataset.len()):
            data_i = dataset.get(i)
            x_out = model(data_i)
            emb = global_mean_pool(x_out, torch.zeros(x_out.size(0), dtype=torch.long, device=x_out.device))
            name = dataset.get_name(i)
            name2emb[name]=emb.cpu().numpy()
    return name2emb

def show_heatmap(name2emb):
    names = sorted(name2emb.keys())
    if not names:
        print("[WARN] no embeddings => skip heatmap")
        return
    
    # 取出所有 embedding
    embs = [name2emb[n] for n in names]
    emb_mat = np.stack(embs, axis=0)
    
    # 计算余弦相似度矩阵
    N = emb_mat.shape[0]
    sim_mat = np.zeros((N, N))
    
    for i in range(N):
        for j in range(N):
            dot_ij = np.dot(emb_mat[i], emb_mat[j])
            norm_i = norm(emb_mat[i])
            norm_j = norm(emb_mat[j])
            if norm_i < 1e-9 or norm_j < 1e-9:
                sim_mat[i, j] = 0
            else:
                sim_mat[i, j] = dot_ij / (norm_i * norm_j)
    
    # 反转 cmap 让 1 显示为红色，-1 显示为蓝色
    cmap = sns.color_palette("RdBu_r", as_cmap=True)  # 反转 RdBu 颜色

    plt.figure(figsize=(10, 8))
    sns.heatmap(sim_mat, xticklabels=names, yticklabels=names, cmap=cmap, vmin=-1, vmax=1)
    plt.title("GraphCL-Style Self-Supervised, Pure Topology Similarity")
    plt.tight_layout()
    plt.show()

###############################################################################
# main
###############################################################################
def main():
    import sys
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("Device:", device)

    json_dir = r"C:\Users\harmi\Research\sdn\json_exp"
    dataset = TopoGraphDataset(json_dir)
    n_graphs = dataset.len()
    print(f"Loaded {n_graphs} topologies")
    if n_graphs==0:
        return

    # in_dim=4 => [ router_onehot(2), deg(1), config_count(1) ]
    model = GCNEncoder(in_dim=4, hidden_dim=32, out_dim=32).to(device)

    # Train self-supervised
    train_graphcl(dataset, model, epochs=40, lr=1e-3,
                  device=device,
                  drop_edge_p=0.2, drop_node_p=0.1,
                  batch_size=4)

    # Compute embeddings => show heatmap
    name2emb = {}
    with torch.no_grad():
        for i in range(n_graphs):
            data_i = dataset.get(i).to(device)
            x_out = model(data_i)
            # pooling
            emb = global_mean_pool(x_out, torch.zeros(x_out.size(0), dtype=torch.long, device=x_out.device))
            emb = emb.view(-1)
            fname= dataset.get_name(i)
            name2emb[fname] = emb.cpu().numpy()

    show_heatmap(name2emb)

if __name__=="__main__":
    main()
