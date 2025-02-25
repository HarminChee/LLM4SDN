import os
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
from sklearn.preprocessing import OneHotEncoder
from sklearn.metrics.pairwise import cosine_similarity
import json
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

# ================================
# Step 1: Data Loading and Preprocessing
# ================================

class TopologyDataset(Dataset):
    def __init__(self, json_files, input_dim):
        self.json_files = json_files
        self.input_dim = input_dim
        self.data = self._prepare_data()

    def _extract_topology_features(self, json_content):
        features = []
        logs = []

        for key, value in json_content.items():
            if isinstance(value, dict):
                features += self._process_dict_features(key, value, logs)
            elif isinstance(value, list):
                features += self._process_list_features(key, value, logs)
            elif isinstance(value, (str, int)):
                features.append(f"{key}: {value}")
            else:
                logs.append(f"Unhandled key '{key}' with type {type(value)}")

        if logs:
            print(f"File issues: {logs}")

        return features

    def _process_dict_features(self, parent_key, data, logs):
        features = []

        if "links" in data and isinstance(data["links"], list):
            for link in data["links"]:
                if isinstance(link, dict) and "source" in link and "target" in link:
                    features.append(f"{link['source']}->{link['target']}")
                elif isinstance(link, dict):
                    features.append(f"{link.get('to', 'unknown')} via {link.get('via', 'unknown')}")
                else:
                    logs.append(f"Invalid link format in '{parent_key}': {link}")

        if "interfaces" in data:
            interfaces = data["interfaces"]
            if isinstance(interfaces, list):
                for iface in interfaces:
                    if isinstance(iface, str):
                        features.append(f"{parent_key}: {iface}")
                    elif isinstance(iface, dict):
                        connected_to = iface.get("connected_to", "unknown")
                        features.append(f"{iface.get('interface', 'unknown')}->{connected_to}")

        for key, value in data.items():
            if isinstance(value, dict):
                features += self._process_dict_features(key, value, logs)
            elif isinstance(value, list):
                features += self._process_list_features(key, value, logs)
            elif isinstance(value, (str, int)):
                features.append(f"{parent_key}.{key}: {value}")

        return features

    def _process_list_features(self, parent_key, data, logs):
        features = []
        for item in data:
            if isinstance(item, dict):
                features += self._process_dict_features(parent_key, item, logs)
            elif isinstance(item, (str, int)):
                features.append(f"{parent_key}: {item}")
        return features

    def _vectorize(self, tokens, encoder):
        encoded = encoder.transform(np.array(tokens).reshape(-1, 1))
        return encoded.sum(axis=0)

    def _prepare_data(self):
        all_tokens = []
        json_tokenized = []

        for jf in self.json_files:
            try:
                with open(jf, "r") as jfile:
                    json_content = json.load(jfile)
                    json_tokens = self._extract_topology_features(json_content)

                    if not json_tokens:
                        print(f"Skipping file with no features: {jf}")
                        continue

                    json_tokenized.append(json_tokens)
                    all_tokens.extend(json_tokens)

            except json.JSONDecodeError as e:
                print(f"Skipping invalid JSON file: {jf} - Error: {e}")
                continue

        if not all_tokens:
            raise ValueError("No valid features found in the provided JSON files.")

        encoder = OneHotEncoder(handle_unknown="ignore", sparse_output=False)
        encoder.fit(np.array(all_tokens).reshape(-1, 1))

        data = []
        for j_tokens in json_tokenized:
            j_vector = self._vectorize(j_tokens, encoder)
            j_vector = j_vector[:self.input_dim]
            j_vector = np.pad(j_vector, (0, max(0, self.input_dim - len(j_vector))), 'constant')
            data.append(j_vector)

        return data

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        return torch.tensor(self.data[idx], dtype=torch.float32)

# ================================
# Step 2: Define the Autoencoder Model
# ================================

class Autoencoder(nn.Module):
    def __init__(self, input_dim, latent_dim):
        super(Autoencoder, self).__init__()
        self.encoder = nn.Sequential(
            nn.Linear(input_dim, 256),
            nn.ReLU(),
            nn.Linear(256, latent_dim)
        )
        self.decoder = nn.Sequential(
            nn.Linear(latent_dim, 256),
            nn.ReLU(),
            nn.Linear(256, input_dim)
        )

    def forward(self, x):
        latent = self.encoder(x)
        reconstructed = self.decoder(latent)
        return reconstructed, latent

# ================================
# Step 3: Train the Autoencoder
# ================================

def train_autoencoder(model, dataloader, epochs=50, lr=0.001):
    criterion = nn.MSELoss()
    optimizer = optim.Adam(model.parameters(), lr=lr)

    for epoch in range(epochs):
        total_loss = 0
        for batch in dataloader:
            inputs = batch

            outputs, _ = model(inputs)
            loss = criterion(outputs, inputs)

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()

            total_loss += loss.item()

        print(f"Epoch {epoch + 1}/{epochs}, Loss: {total_loss / len(dataloader)}")

# ================================
# Step 4: Generate Embeddings and Calculate Similarity
# ================================

def generate_embeddings(model, dataloader):
    model.eval()
    embeddings = []

    with torch.no_grad():
        for batch in dataloader:
            _, latent = model(batch)
            embeddings.append(latent)

    return torch.cat(embeddings, dim=0)

# ================================
# Step 5: Output Pairs with High Similarity
# ================================

def save_high_similarity_pairs(similarity_matrix, json_files, threshold=0.9, output_path="C:\\Users\\harmi\\Desktop\\sdn\\similarity_pairs_1.json"):
    file_names = [os.path.basename(file) for file in json_files]
    pairs = []

    for i in range(len(file_names)):
        for j in range(len(file_names)):
            if i != j and similarity_matrix[i, j] > threshold:
                pairs.append({"file1": file_names[i], "file2": file_names[j], "similarity": float(similarity_matrix[i, j])})

    with open(output_path, "w") as outfile:
        json.dump(pairs, outfile, indent=4)

    print(f"High-similarity pairs saved to {output_path}")

    # Plot heatmap
    plt.figure(figsize=(10, 8))
    sns.heatmap(similarity_matrix, annot=False, cmap="coolwarm", xticklabels=file_names, yticklabels=file_names)
    plt.title("Topology Similarity Matrix")
    plt.xlabel("JSON Files")
    plt.ylabel("JSON Files")
    plt.show()

# ================================
# Main Function
# ================================

if __name__ == "__main__":
    input_dim = 512
    latent_dim = 128
    batch_size = 16
    epochs = 50

    json_folder = r"C:\\Users\\harmi\\Desktop\\sdn\\json_clear2"
    json_files = [os.path.join(json_folder, f) for f in os.listdir(json_folder) if f.endswith(".json")]
    json_files.sort()

    dataset = TopologyDataset(json_files, input_dim)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=False)

    model = Autoencoder(input_dim, latent_dim)
    train_autoencoder(model, dataloader, epochs=epochs)

    embeddings = generate_embeddings(model, dataloader)
    similarity_matrix = cosine_similarity(embeddings.numpy(), embeddings.numpy())

    save_high_similarity_pairs(similarity_matrix, json_files)
