"""
    python -m src.dataset_generator.run
"""

from datasets import load_dataset


if __name__ == "__main__":
    # Download the Wikipedia dataset
    # The "20220301.simple" version is a simplified version of the English Wikipedia
    load_dataset("wikipedia", "20220301.simple")

    print("dl completed")