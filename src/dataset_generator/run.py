"""
    python -m src.dataset_generator.run
"""

from datasets import load_dataset

def make_wikipedia_df(
    subset_name: str = "20220301.simple",
    num_samples: int = 1000,
    seed: int = 42
):
    """
    Load a dataset and return a DataFrame with a specified number of samples.
    
    Args:
        dataset_name (str): Name of the dataset to load.
        subset_name (str): Subset of the dataset to load.
        num_samples (int): Number of samples to select from the dataset.
        seed (int): Random seed for reproducibility.
    
    Returns:
        pd.DataFrame: DataFrame containing the selected samples.
    """
    dataset = load_dataset("wikipedia", subset_name, trust_remote_code=True)
    df = dataset["train"].shuffle(seed=seed).select(range(num_samples)).to_pandas()

    # urlカラムは不要なので削除
    return df[["id", "title", "text"]]


if __name__ == "__main__":
    # Download the Wikipedia dataset

    for i in [1000, 10000, 100000, 1000000]:
        print(f"extracting row_num {i}")
        df = make_wikipedia_df(
            subset_name="20220301.en",
            num_samples=i,
            seed=42
        )
        

        df.to_csv(f"./data/wikipedia_{i}.csv", index=False)