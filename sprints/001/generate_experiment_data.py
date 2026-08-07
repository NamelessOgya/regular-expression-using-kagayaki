#!/usr/bin/env python3
"""
generate_experiment_data.py - 実験 B 用データセット生成スクリプト

実際の wiki_plain.txt の行を使って2種類のデータセットを生成する:
  1. uniform.txt  - 行長が均一なデータ（同じ長さ帯の行のみ抽出）
  2. varied.txt   - 行長ばらつきが大きいデータ（短行と長行を交互に配置）

使い方:
  python3 sprints/001/generate_experiment_data.py
"""

import random
import os
import sys

WIKI_PATH = "data/wiki_plain.txt"
OUT_DIR   = "data/experiment"
TARGET_CHARS = 10_000_000  # 各データセットの目標文字数（約1000万文字）
SEED = 42

def load_lines(path):
    with open(path, encoding='utf-8', errors='ignore') as f:
        lines = [line.rstrip('\n') for line in f]
    return lines

def write_dataset(path, lines):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    total_chars = sum(len(l) for l in lines)
    with open(path, 'w', encoding='utf-8') as f:
        for line in lines:
            f.write(line + '\n')
    print(f"  書き込み完了: {path}")
    print(f"    行数: {len(lines):,}")
    print(f"    合計文字数: {total_chars:,}")
    lengths = [len(l) for l in lines]
    import statistics
    print(f"    平均行長: {statistics.mean(lengths):.1f}")
    print(f"    標準偏差: {statistics.stdev(lengths):.1f}")
    print(f"    最小行長: {min(lengths)}")
    print(f"    最大行長: {max(lengths)}")

def main():
    random.seed(SEED)
    print(f"[1/3] {WIKI_PATH} を読み込み中...")
    all_lines = load_lines(WIKI_PATH)
    print(f"  総行数: {len(all_lines):,}")

    # ------------------------------------------------------------------
    # データセット 1: uniform.txt
    # 行長 30〜60 文字の行のみ抽出し、ランダムにシャッフル
    # → 中央値付近の「均一な長さ帯」に限定することで分散を抑える
    # ------------------------------------------------------------------
    print("\n[2/3] uniform.txt を生成中 (行長 30〜60 文字のみ)...")
    uniform_pool = [l for l in all_lines if 30 <= len(l) < 60]
    random.shuffle(uniform_pool)

    uniform_lines = []
    total = 0
    for line in uniform_pool:
        if total >= TARGET_CHARS:
            break
        uniform_lines.append(line)
        total += len(line)
    write_dataset(f"{OUT_DIR}/uniform.txt", uniform_lines)

    # ------------------------------------------------------------------
    # データセット 2: varied.txt
    # 短行（0〜15文字）と長行（500文字以上）を交互に配置
    # → 行長のばらつきを最大化し、Static の不均一さを際立たせる
    # ------------------------------------------------------------------
    print("\n[3/3] varied.txt を生成中 (短行/長行を交互配置)...")
    short_pool = [l for l in all_lines if 0 < len(l) <= 15]
    long_pool  = [l for l in all_lines if len(l) >= 500]
    random.shuffle(short_pool)
    random.shuffle(long_pool)

    varied_lines = []
    total = 0
    si, li = 0, 0
    while total < TARGET_CHARS and si < len(short_pool) and li < len(long_pool):
        # 短行を追加
        varied_lines.append(short_pool[si]); total += len(short_pool[si]); si += 1
        if total >= TARGET_CHARS: break
        # 長行を追加
        varied_lines.append(long_pool[li]);  total += len(long_pool[li]);  li += 1
    write_dataset(f"{OUT_DIR}/varied.txt", varied_lines)

    print("\n完了！")
    print(f"  {OUT_DIR}/uniform.txt  → 行長が均一なデータ（Static ≈ Dynamic を想定）")
    print(f"  {OUT_DIR}/varied.txt   → 行長ばらつきが大きいデータ（Dynamic 有利を想定）")

if __name__ == "__main__":
    main()
