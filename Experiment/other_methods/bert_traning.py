import os
import json
import torch
from torch.utils.data import Dataset, DataLoader
from transformers import AutoTokenizer, AutoModel
import numpy as np
from sklearn.metrics.pairwise import cosine_similarity
import matplotlib.pyplot as plt
import seaborn as sns

# ================================
# Step 1: Data Loading and Preprocessing
# ================================

class TopologyDataset(Dataset):
    """
    Dataset to load and process JSON files for BERT-based topology similarity detection.
    """
    def __init__(self, json_files, tokenizer, max_length=512):
        self.json_files = json_files
        self.tokenizer = tokenizer
        self.max_length = max_length
        self.data = self._prepare_data()

    def _serialize_json(self, json_content):
        """
        Convert a JSON object into a serialized text format.
        """
        serialized = []
        for key, value in json_content.items():
            if isinstance(value, dict):
                serialized.append(f"{key}: {self._serialize_json(value)}")
            elif isinstance(value, list):
                serialized.append(f"{key}: {', '.join(map(str, value))}")
            else:
                serialized.append(f"{key}: {value}")
        return ", ".join(serialized)

    def _prepare_data(self):
        """
        Tokenize JSON files and prepare input for BERT.
        """
        tokenized_data = []
        for jf in self.json_files:
            with open(jf, "r") as jfile:
                json_content = json.load(jfile)
                serialized_text = self._serialize_json(json_content)

                # Tokenize the serialized JSON text
                tokens = self.tokenizer(
                    serialized_text,
                    padding="max_length",
                    truncation=True,
                    max_length=self.max_length,
                    return_tensors="pt"
                )
                tokenized_data.append(tokens)
        return tokenized_data

    def __len__(self):
        return len(self.data)

    def __getitem__(self, idx):
        return self.data[idx]

# ================================
# Step 2: Generate Embeddings Using BERT
# ================================

def generate_embeddings(model, dataloader, device):
    """
    Generate embeddings for JSON files using BERT.
    """
    model.eval()
    embeddings = []

    with torch.no_grad():
        for batch in dataloader:
            input_ids = batch["input_ids"].squeeze(1).to(device)
            attention_mask = batch["attention_mask"].squeeze(1).to(device)

            # Get the CLS token embedding from BERT
            outputs = model(input_ids=input_ids, attention_mask=attention_mask)
            cls_embedding = outputs.last_hidden_state[:, 0, :]  # CLS token
            embeddings.append(cls_embedding.cpu())

    return torch.cat(embeddings, dim=0)

# ================================
# Step 3: Calculate Similarity
# ================================

def calculate_similarity(embeddings):
    """
    Calculate similarity within a single set of embeddings.
    """
    e_np = embeddings.numpy()
    similarity_matrix = cosine_similarity(e_np, e_np)
    return similarity_matrix

# ================================
# Step 4: Save and Visualize Results
# ================================

def save_similarity_matrix(similarity_matrix, filename):
    """
    Save the similarity matrix as a CSV file.
    """
    np.savetxt(filename, similarity_matrix, delimiter=",", fmt="%.6f")
    print(f"Similarity matrix saved to {filename}")

def visualize_similarity_matrix(similarity_matrix, json_files):
    """
    Visualize the similarity matrix using a heatmap.
    """
    json_filenames = [os.path.basename(f) for f in json_files]
    plt.figure(figsize=(12, 10))
    sns.heatmap(similarity_matrix, annot=False, cmap="coolwarm", xticklabels=json_filenames, yticklabels=json_filenames)
    plt.title("Topology Similarity Matrix")
    plt.xlabel("JSON Files")
    plt.ylabel("JSON Files")
    plt.show()

# ================================
# Step 5: Main Function
# ================================

if __name__ == "__main__":
    # Configuration parameters
    max_length = 512  # Maximum token length for BERT
    batch_size = 8
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

    # Choose pre-trained model (BERT)
    model_name = "bert-base-uncased"
    tokenizer = AutoTokenizer.from_pretrained(model_name)
    model = AutoModel.from_pretrained(model_name).to(device)

    # Load all JSON files from the directory
    json_folder = r"C:\Users\harmi\Desktop\sdn\json1_files"
    json_files = [os.path.join(json_folder, f) for f in os.listdir(json_folder) if f.endswith(".json")]
    json_files.sort()

    # Load the dataset
    dataset = TopologyDataset(json_files, tokenizer, max_length=max_length)
    dataloader = DataLoader(dataset, batch_size=batch_size, shuffle=False)

    # Generate embeddings
    print("Generating embeddings...")
    embeddings = generate_embeddings(model, dataloader, device)

    # Calculate similarity within the dataset
    print("Calculating similarity...")
    similarity_matrix = calculate_similarity(embeddings)

    # Save the similarity matrix to a CSV file
    save_similarity_matrix(similarity_matrix, "bert_topology_similarity.csv")

    # Visualize the similarity matrix as a heatmap
    visualize_similarity_matrix(similarity_matrix, json_files)
