#!/usr/bin/env python3
"""
generate_scale_data.py - 行数スケール実験用データセット生成スクリプト

GPU Line の並列度限界（RTX 5090: 348,160 同時スレッド）を検証するため、
均一行長（30〜60文字）で行数だけを変えた 3 データセットを生成する。

  dynamic-small  :   25,000 行 → GPU Line で 0.07 ウェーブ（有利）
  dynamic-medium :  500,000 行 → GPU Line で 1.44 ウェーブ（crossover）
  dynamic-large  : 2,000,000 行 → GPU Line で 5.75 ウェーブ（劣後）
"""

import random
import itertools
import os
import statistics

WIKI_PATH = "data/wiki_plain.txt"
OUT_DIR = "data/experiment"
SEED = 42

# RTX 5090 スペック（情報用）
GPU_CONCURRENT_THREADS = 348_160
BLOCK_SIZE = 256
LPC = 8

def make_dataset(name, n_lines, pool):
    path = f"{OUT_DIR}/{name}.txt"
    # pool を循環させて n_lines 行生成
    lines = list(itertools.islice(itertools.cycle(pool), n_lines))
    total_chars = sum(len(l) for l in lines)
    lengths = [len(l) for l in lines]

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        for l in lines:
            f.write(l + '\n')

    line_waves  = n_lines / GPU_CONCURRENT_THREADS
    chunk_waves = ((n_lines + LPC - 1) // LPC) / GPU_CONCURRENT_THREADS

    print(f"\n[{name}]")
    print(f"  行数          : {n_lines:>12,}")
    print(f"  合計文字数    : {total_chars:>12,}")
    print(f"  平均行長      : {statistics.mean(lengths):>12.1f}")
    print(f"  標準偏差      : {statistics.stdev(lengths):>12.1f}")
    print(f"  GPU Line 波数 : {line_waves:>12.2f}")
    print(f"  Chunk 波数    : {chunk_waves:>12.2f}")
    print(f"  出力          : {path}")


def main():
    random.seed(SEED)

    print(f"[1/4] {WIKI_PATH} を読み込み中...")
    with open(WIKI_PATH, encoding='utf-8', errors='ignore') as f:
        all_lines = [line.rstrip('\n') for line in f]
    print(f"  総行数: {len(all_lines):,}")

    print("\n[2/4] プール生成 (行長 30〜60 文字)...")
    pool = [l for l in all_lines if 30 <= len(l) < 60]
    random.shuffle(pool)
    print(f"  プールサイズ: {len(pool):,} 行")

    if len(pool) < 1000:
        raise RuntimeError("プールが小さすぎます。wiki_plain.txt を確認してください。")

    print("\n[3/4] データセット生成中...")
    configs = [
        ("dynamic-small",   25_000),
        ("dynamic-medium",  500_000),
        ("dynamic-large", 2_000_000),
    ]

    for name, n_lines in configs:
        make_dataset(name, n_lines, pool)

    print("\n[4/4] 完了")
    print("  次のステップ:")
    for name, _ in configs:
        print(f"    bash run_all.sh data/experiment/{name}.txt --runs 3")


if __name__ == "__main__":
    main()
