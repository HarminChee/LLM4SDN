import os
import json
import numpy as np
import networkx as nx
import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F
from torch_geometric.data import Data, Dataset, DataLoader
from torch_geometric.nn import GCNConv, global_mean_pool
import matplotlib.pyplot as plt
import seaborn as sns
from numpy.linalg import norm
import hashlib

###############################################################################
# 1. Parse JSON Topology Files => Feature Extraction
###############################################################################

def str_hash(s, num_buckets=8):
    """
    Hash a string into an integer bucket, suitable for encoding interface names, 
    IP prefixes, etc.
    """
    if not isinstance(s, str):
        return 0
    return int(hashlib.md5(s.encode()).hexdigest(), 16) % num_buckets

def parse_topo_from_json(json_path):
    """
    Parse a network topology from a JSON file and extract node and edge features 
    for use with PyTorch Geometric. Designed for topologies describing SDN testbeds.
    Returns: torch_geometric.data.Data instance or None on error.
    """
    try:
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        if not isinstance(data, dict):
            print(f"[WARN] JSON file is not a dict, skipping: {json_path}")
            return None
    except Exception as e:
        print(f"[ERROR] Failed to parse {json_path}: {e}")
        return None

    # Node and protocol type lists for feature one-hot encoding
    NODE_TYPES = ["router", "switch", "host", "device", "pc", "iot"]
    PROTO_LIST = [
        "bgp", "ospf", "rip", "bfd", "static", "isis", "eigrp", "mpls",
        "pim", "igmp", "mld", "policy", "acl", "lo"
    ]
    INTF_BUCKETS = 8
    IP_BUCKETS = 8

    nodes = []
    node_types = []
    name2idx = {}
    idx_count = 0

    # Aggregate all node types, mapping their names and types
    for kind in ["routers", "switches", "hosts", "devices"]:
        node_dict = data.get(kind, {})
        if isinstance(node_dict, dict):
            for nid, ninfo in node_dict.items():
                ntype = ninfo.get("type", kind[:-1])  # Fallback to e.g., 'router'
                nodes.append(nid)
                node_types.append(ntype)
                name2idx[nid] = idx_count
                idx_count += 1

    if idx_count == 0:
        return None  # No nodes found

    # Build undirected edge list
    edges = []
    links = data.get("links", [])
    if isinstance(links, list):
        for lk in links:
            src = lk.get("source")
            tgt = lk.get("target")
            if src in name2idx and tgt in name2idx:
                s_idx = name2idx[src]
                t_idx = name2idx[tgt]
                edges.append((s_idx, t_idx))
                edges.append((t_idx, s_idx))
    # Also add intra-device links if any (some topologies have these)
    for ni, ninfo in enumerate(nodes):
        info = {}
        for kind in ["routers", "switches", "hosts", "devices"]:
            ndict = data.get(kind, {})
            if ninfo in ndict:
                info = ndict[ninfo]
                break
        if info and "links" in info and isinstance(info["links"], dict):
            for tgtname in info["links"]:
                if tgtname in name2idx:
                    edges.append((ni, name2idx[tgtname]))
                    edges.append((name2idx[tgtname], ni))

    # Build NetworkX graph for feature computation
    G = nx.Graph()
    G.add_nodes_from(range(idx_count))
    G.add_edges_from(edges)

    deg_centrality_dict = nx.degree_centrality(G)
    clust_coeff_dict = nx.clustering(G)

    x_list = []
    for i, name_type in enumerate(node_types):
        deg = G.degree(i)
        # 1. Node type one-hot encoding
        type_feat = [1 if name_type.lower() == t else 0 for t in NODE_TYPES]
        node_name = nodes[i]

        # 2. Initialize feature statistics
        proto_count = 0
        pim_count = 0
        rp_count = 0
        group_addr_range_count = 0
        igmp_if_count = 0
        mld_if_count = 0
        vrf_count = 0
        route_count = 0
        as_count = 0
        static_route_count = 0
        acl_count = 0
        intf_count = 0
        lo_count = 0
        intf_type_bucket = [0] * INTF_BUCKETS
        ip_prefix_bucket = [0] * IP_BUCKETS
        neighbor_router = 0
        neighbor_switch = 0
        neighbor_host = 0
        neighbor_device = 0
        link_count = 0

        # 3. Neighbor type distribution
        neighbors = list(G.neighbors(i))
        for j in neighbors:
            if j < len(node_types):
                typ = node_types[j].lower()
                neighbor_router += typ == "router"
                neighbor_switch += typ == "switch"
                neighbor_host += typ == "host"
                neighbor_device += typ == "device"

        # Get specific node info dict
        ninfo = None
        for kind in ["routers", "switches", "hosts", "devices"]:
            ndict = data.get(kind, {})
            if node_name in ndict:
                ninfo = ndict[node_name]
                break
        if ninfo is None:
            ninfo = {}

        # 4. Protocols and advanced node feature statistics
        for proto in PROTO_LIST:
            proto_count += int(proto in ninfo and isinstance(ninfo[proto], dict))
        if "pim" in ninfo and isinstance(ninfo["pim"], dict):
            pim_count += 1
            if "rp" in ninfo["pim"] and isinstance(ninfo["pim"]["rp"], list):
                rp_count += len(ninfo["pim"]["rp"])
                for rp_obj in ninfo["pim"]["rp"]:
                    if "group_addr_range" in rp_obj and isinstance(rp_obj["group_addr_range"], list):
                        group_addr_range_count += len(rp_obj["group_addr_range"])
        if "igmp" in ninfo and isinstance(ninfo["igmp"], dict):
            if "interfaces" in ninfo["igmp"] and isinstance(ninfo["igmp"]["interfaces"], dict):
                igmp_if_count += len(ninfo["igmp"]["interfaces"])
        if "mld" in ninfo and isinstance(ninfo["mld"], dict):
            if "interfaces" in ninfo["mld"] and isinstance(ninfo["mld"]["interfaces"], dict):
                mld_if_count += len(ninfo["mld"]["interfaces"])
        if "links" in ninfo and isinstance(ninfo["links"], dict):
            link_count = len(ninfo["links"])
        if "lo" in ninfo.get("links", {}) and isinstance(ninfo["links"]["lo"], dict):
            lo_count += 1

        # 5. Interface and route statistics
        if "interfaces" in ninfo and isinstance(ninfo["interfaces"], dict):
            intf_count = len(ninfo["interfaces"])
            for intfname, intfval in ninfo["interfaces"].items():
                idx = str_hash(intfname, INTF_BUCKETS)
                intf_type_bucket[idx] += 1
                if isinstance(intfval, dict) and "ipv4" in intfval:
                    ipv4_value = intfval["ipv4"]
                    if isinstance(ipv4_value, str) and ipv4_value:
                        ipstr = ipv4_value.split("/")[0]
                        ip_idx = str_hash(ipstr, IP_BUCKETS)
                        ip_prefix_bucket[ip_idx] += 1
                    else:
                        ip_prefix_bucket[0] += 1

        # BGP/VRF/Route/ACL/Static Route feature extraction
        if "bgp" in ninfo and isinstance(ninfo["bgp"], dict):
            if "as" in ninfo["bgp"]:
                as_count += 1
            if "vrfs" in ninfo["bgp"]:
                vrfs_val = ninfo["bgp"]["vrfs"]
                if isinstance(vrfs_val, dict):
                    vrf_count = len(vrfs_val)
                    for vrf_name, vrf_val in vrfs_val.items():
                        if isinstance(vrf_val, dict) and "routes" in vrf_val and isinstance(vrf_val["routes"], dict):
                            route_count += len(vrf_val["routes"])
                elif isinstance(vrfs_val, list):
                    vrf_count = len(vrfs_val)
                    for vrf_val in vrfs_val:
                        if isinstance(vrf_val, dict) and "routes" in vrf_val and isinstance(vrf_val["routes"], dict):
                            route_count += len(vrf_val["routes"])
        if "static" in ninfo and isinstance(ninfo["static"], dict):
            static_route_count += len(ninfo["static"])
        if "acl" in ninfo and isinstance(ninfo["acl"], dict):
            acl_count += len(ninfo["acl"])

        deg_centrality = deg_centrality_dict[i] if i in deg_centrality_dict else 0.0
        clust_coeff = clust_coeff_dict[i] if i in clust_coeff_dict else 0.0

        # 6. Aggregate all node features into a single vector
        feat = (
            type_feat  # one-hot node type (6+)
            + [float(deg), deg_centrality, clust_coeff]
            + [float(intf_count), float(proto_count), float(pim_count), float(rp_count),
               float(group_addr_range_count), float(igmp_if_count), float(mld_if_count), float(link_count), float(lo_count)]
            + [float(vrf_count), float(route_count), float(as_count), float(static_route_count), float(acl_count)]
            + intf_type_bucket
            + ip_prefix_bucket
            + [float(neighbor_router), float(neighbor_switch), float(neighbor_host), float(neighbor_device)]
        )
        x_list.append(feat)

    x = torch.tensor(x_list, dtype=torch.float)
    edge_index = None
    if len(edges) > 0:
        e_np = np.array(edges, dtype=np.int64).T
        edge_index = torch.from_numpy(e_np)
    else:
        edge_index = torch.zeros((2, 0), dtype=torch.long)

    data_pyG = Data(x=x, edge_index=edge_index)
    return data_pyG

###############################################################################
# 2. PyTorch Geometric Dataset Wrapper for Batch Loading
###############################################################################
class TopoGraphDataset(Dataset):
    """
    Custom Dataset to load all JSON topology files in a folder as PyTorch Geometric graphs.
    """
    def __init__(self, json_dir):
        super().__init__()
        self.json_dir = json_dir
        self.files = sorted([f for f in os.listdir(json_dir) if f.endswith('.json')])
        self.data_list = []
        self.names = []
        for f in self.files:
            fullp = os.path.join(json_dir, f)
            data_pyG = parse_topo_from_json(fullp)
            if data_pyG is not None:
                self.data_list.append(data_pyG)
                self.names.append(f)

    def len(self):
        return len(self.data_list)

    def get(self, idx):
        return self.data_list[idx]

    def get_name(self, idx):
        return self.names[idx]

###############################################################################
# 3. Data Augmentation (GraphCL-style): Random Edge and Node Drop
###############################################################################
def random_drop_edges(data_pyG, drop_prob=0.2):
    """
    Randomly drop edges (and corresponding reverse edges for undirected graphs) 
    for data augmentation.
    """
    edge_index = data_pyG.edge_index
    col = edge_index.size(1)
    if col == 0:
        return data_pyG
    n_edges = col // 2
    if n_edges <= 0:
        return data_pyG

    keep_mask = (torch.rand(n_edges) > drop_prob)
    if not keep_mask.any():
        keep_mask[0] = True  # Ensure at least one edge remains

    new_edges = []
    keep_idx = torch.where(keep_mask)[0]
    for i in keep_idx:
        s_i = 2 * i
        t_i = 2 * i + 1
        if s_i < col and t_i < col:
            s_src = edge_index[0, s_i]
            s_tgt = edge_index[1, s_i]
            t_src = edge_index[0, t_i]
            t_tgt = edge_index[1, t_i]
            new_edges.append((s_src.item(), s_tgt.item()))
            new_edges.append((t_src.item(), t_tgt.item()))

    data_aug = data_pyG.clone()
    if len(new_edges) == 0:
        data_aug.edge_index = torch.zeros((2, 0), dtype=torch.long)
    else:
        e_np = np.array(new_edges, dtype=np.int64).T
        data_aug.edge_index = torch.from_numpy(e_np)
    return data_aug

def random_drop_nodes(data_pyG, drop_prob=0.1):
    """
    Randomly drop nodes from the graph for data augmentation.
    """
    n = data_pyG.x.size(0)
    if n <= 1:
        return data_pyG

    keep_mask = (torch.rand(n) > drop_prob)
    if not keep_mask.any():
        keep_mask[0] = True

    idx_new = torch.where(keep_mask)[0]
    if idx_new.size(0) == n or idx_new.size(0) == 0:
        return data_pyG

    old2new = {}
    for i, old_id in enumerate(idx_new):
        old2new[old_id.item()] = i

    new_x = data_pyG.x[idx_new].clone()
    old_edges = data_pyG.edge_index.t().numpy().tolist()
    new_edges = []
    for s_i, t_i in old_edges:
        if s_i in old2new and t_i in old2new:
            new_edges.append((old2new[s_i], old2new[t_i]))

    data_aug = data_pyG.clone()
    data_aug.x = new_x
    if len(new_edges) == 0:
        data_aug.edge_index = torch.zeros((2, 0), dtype=torch.long)
    else:
        e_np = np.array(new_edges, dtype=np.int64).T
        data_aug.edge_index = torch.from_numpy(e_np)
    return data_aug

def graph_augment(data_pyG, drop_edge_p=0.1, drop_node_p=0.05):
    """
    Perform a two-step augmentation: drop edges then drop nodes.
    """
    d1 = random_drop_edges(data_pyG, drop_edge_p)
    d2 = random_drop_nodes(d1, drop_node_p)
    return d2

###############################################################################
# 4. Graph Neural Network Model Definition
###############################################################################
class GCNEncoder(nn.Module):
    """
    Simple GCN-based encoder with three layers, LayerNorm, and dropout, 
    followed by normalization. Outputs a node embedding matrix.
    """
    def __init__(self, in_dim, hidden_dim, out_dim=32, dropout=0.02):
        super().__init__()
        self.conv1 = GCNConv(in_dim, hidden_dim)
        self.ln1 = nn.LayerNorm(hidden_dim)
        self.conv2 = GCNConv(hidden_dim, hidden_dim)
        self.ln2 = nn.LayerNorm(hidden_dim)
        self.conv3 = GCNConv(hidden_dim, out_dim)
        self.dropout = nn.Dropout(dropout)

    def forward(self, data):
        x, edge_index = data.x, data.edge_index
        x = self.conv1(x, edge_index)
        x = self.ln1(x)
        x = torch.relu(x)
        x = self.dropout(x)
        x = self.conv2(x, edge_index)
        x = self.ln2(x)
        x = torch.relu(x)
        x = self.dropout(x)
        x = self.conv3(x, edge_index)
        return F.normalize(x, dim=1)

def global_pool_embed(x_mat):
    """
    Compute graph-level embedding as the mean of node embeddings.
    """
    emb = x_mat.mean(dim=0)
    return emb

###############################################################################
# 5. Self-Supervised Contrastive Loss (InfoNCE/GraphCL-style)
###############################################################################
def sim_matrix_cos(z):
    """
    Compute cosine similarity matrix for batch of embeddings.
    """
    z_norm = z / (z.norm(dim=1, keepdim=True) + 1e-9)
    sim = z_norm @ z_norm.t()
    return sim

def contrastive_loss(z, batch_size, temperature=0.2):
    """
    Contrastive loss for positive pairs and negatives in a batch.
    """
    sim_mat = sim_matrix_cos(z)
    n = z.size(0)
    losses = []
    for i in range(0, n, 2):
        j = i + 1
        sim_ij = sim_mat[i, j] / temperature
        mask_i = torch.ones(n, dtype=torch.bool, device=z.device)
        mask_i[i] = False
        sim_i_all = sim_mat[i][mask_i] / temperature
        num = torch.exp(sim_ij)
        den = torch.sum(torch.exp(sim_i_all))
        loss_i = -torch.log(num / den)
        losses.append(loss_i)

        sim_ji = sim_mat[j, i] / temperature
        mask_j = torch.ones(n, dtype=torch.bool, device=z.device)
        mask_j[j] = False
        sim_j_all = sim_mat[j][mask_j] / temperature
        num_j = torch.exp(sim_ji)
        den_j = torch.sum(torch.exp(sim_j_all))
        loss_j = -torch.log(num_j / den_j)
        losses.append(loss_j)
    return torch.mean(torch.stack(losses))

###############################################################################
# 6. Graph-level Training: DataLoader, Augmentation, Contrastive Loss
###############################################################################
def train_graphcl(dataset, model, epochs=20, lr=1e-3, device='cpu',
                  drop_edge_p=0.2, drop_node_p=0.1, batch_size=4):
    """
    Main GraphCL-style training loop: 
    - Loads graphs in batches
    - Applies two augmentations per graph
    - Passes through GNN encoder
    - Computes contrastive loss between pairs
    """
    model.train()
    optimizer = optim.Adam(model.parameters(), lr=lr)

    def collate_fn(batch_list):
        return batch_list

    loader = DataLoader(range(dataset.len()), batch_size=batch_size,
                        shuffle=True, drop_last=True,
                        collate_fn=collate_fn)
    for ep in range(1, epochs + 1):
        total_loss = 0.
        batch_count = 0
        for idx_list in loader:
            z_list = []
            for idx in idx_list:
                data_orig = dataset.get(idx).to(device)
                aug1 = graph_augment(data_orig, drop_edge_p, drop_node_p)
                aug2 = graph_augment(data_orig, drop_edge_p, drop_node_p)
                x1 = model(aug1)
                if x1.size(0) == 0:
                    continue
                g1 = global_mean_pool(x1, torch.zeros(x1.size(0), dtype=torch.long, device=x1.device))
                g1 = g1.view(-1)
                x2 = model(aug2)
                if x2.size(0) == 0:
                    continue
                g2 = global_mean_pool(x2, torch.zeros(x2.size(0), dtype=torch.long, device=x2.device))
                g2 = g2.view(-1)
                z_list.append(g1)
                z_list.append(g2)

            if len(z_list) < 2:
                continue

            z_big = torch.stack(z_list, dim=0)
            loss = contrastive_loss(z_big, batch_size, temperature=0.2)
            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss += loss.item()
            batch_count += 1
        avg_loss = total_loss / batch_count if batch_count > 0 else 0
        print(f"[Ep {ep}/{epochs}] Loss={avg_loss:.6f}")

###############################################################################
# 7. Compute Embeddings and Plot Similarity Heatmap
###############################################################################
def compute_graph_embeddings(dataset, model, device='cpu'):
    """
    Compute and return graph-level embeddings for all graphs in the dataset.
    """
    model.eval()
    name2emb = {}
    with torch.no_grad():
        for i in range(dataset.len()):
            data_i = dataset.get(i).to(device)
            x_out = model(data_i)
            emb = global_mean_pool(x_out, torch.zeros(x_out.size(0), dtype=torch.long, device=x_out.device))
            emb = emb.view(-1)
            name = dataset.get_name(i)
            name2emb[name] = emb.cpu().numpy()
    return name2emb

def show_heatmap_batches(name2emb, batch_size=50, title="GraphCL-Style Self-Supervised, Topology Similarity"):
    """
    Plot a similarity heatmap (cosine similarity) for all pairs of graphs in the dataset, batched for scalability.
    """
    names = sorted(name2emb.keys())
    total = len(names)
    batches = (total + batch_size - 1) // batch_size
    for batch in range(batches):
        start = batch * batch_size
        end = min((batch + 1) * batch_size, total)
        sub_names = names[start:end]
        embs = [name2emb[n].reshape(-1) for n in sub_names]
        emb_mat = np.stack(embs, axis=0)
        N = emb_mat.shape[0]
        sim_mat = np.zeros((N, N))
        for i in range(N):
            for j in range(N):
                dot_ij = np.dot(emb_mat[i], emb_mat[j])
                norm_i = norm(emb_mat[i])
                norm_j = norm(emb_mat[j])
                sim_mat[i, j] = 0 if norm_i < 1e-9 or norm_j < 1e-9 else dot_ij / (norm_i * norm_j)
        cmap = sns.color_palette("RdBu_r", as_cmap=True)
        plt.figure(figsize=(12, 10))
        sns.heatmap(sim_mat, xticklabels=sub_names, yticklabels=sub_names, cmap=cmap, vmin=-1, vmax=1)
        plt.title(f"{title} (Batch {batch + 1}/{batches})")
        plt.tight_layout()
        plt.show()

###############################################################################
# Main Entry Point: Training and Similarity Pair Extraction
###############################################################################
def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print("Device:", device)

    # Generic placeholder paths for JSON topology files (change as needed)
    train_json_dir = "/path/to/train_jsons"
    test_json_dir = "/path/to/test_jsons"
    train_dataset = TopoGraphDataset(train_json_dir)
    test_dataset = TopoGraphDataset(test_json_dir)

    print(f"Loaded {train_dataset.len()} train topologies, {test_dataset.len()} test topologies")
    if train_dataset.len() == 0 or test_dataset.len() == 0:
        print("Empty train or test set, abort.")
        return

    # Infer input feature dimension from first sample
    sample_x = train_dataset.get(0).x
    in_dim = sample_x.shape[1]
    print("Detected input feature dim:", in_dim)

    model = GCNEncoder(in_dim=in_dim, hidden_dim=64, out_dim=32).to(device)

    train_graphcl(train_dataset, model, epochs=80, lr=1e-4,
                  device=device,
                  drop_edge_p=0.2, drop_node_p=0.1,
                  batch_size=16)

    name2emb = compute_graph_embeddings(test_dataset, model, device=device)
    show_heatmap_batches(name2emb, batch_size=50, title="Test Set Similarity Heatmap")
    
    # === Output: High similarity graph pairs ===
    output_pairs = []
    names = sorted(name2emb.keys())
    embs = [name2emb[n].reshape(-1) for n in names]
    emb_mat = np.stack(embs, axis=0)
    N = emb_mat.shape[0]
    sim_mat = np.zeros((N, N))
    for i in range(N):
        for j in range(i + 1, N):  # Only consider upper triangle to avoid duplicates/self-pair
            dot_ij = np.dot(emb_mat[i], emb_mat[j])
            norm_i = norm(emb_mat[i])
            norm_j = norm(emb_mat[j])
            score = 0 if norm_i < 1e-9 or norm_j < 1e-9 else dot_ij / (norm_i * norm_j)
            if score > 0.9:  # Filter for highly similar pairs (cosine similarity > 0.9)
                output_pairs.append((names[i], names[j], score))

    # For each file, only keep the most similar file (with the highest score)
    max_pair_map = {}
    for a, b, score in output_pairs:
        for x, y in [(a, b), (b, a)]:
            if x not in max_pair_map or score > max_pair_map[x][1]:
                max_pair_map[x] = (y, score)

    already = set()
    final_pairs = []
    for x, (y, score) in max_pair_map.items():
        pair = tuple(sorted([x, y]))
        if x != y and pair not in already:
            already.add(pair)
            final_pairs.append((pair[0], pair[1], score))

    # Save pairs to a text file
    with open("high_similarity_pairs.txt", "w", encoding="utf-8") as fout:
        for a, b, score in sorted(final_pairs, key=lambda t: -t[2]):
            fout.write(f"{a} & {b}, heatmap: {score:.4f}\n")
    print(f"[Done] Written high similarity pairs to high_similarity_pairs.txt")

if __name__ == "__main__":
    main()
