#!/usr/bin/env python3
"""
generate_blocked_scale_data.py - ブロック型・行数スケール実験用データセット生成

実験設計:
  長行数を固定（6,422行）し、短行数だけを変化させることで
  「Dynamic の恩恵（=長行の不均衡）を保ちつつ、行数効果だけを変える」。

  blocked-small  : 短行  25,000 + 長行  6,422 =  31,422 行 (0.09 波)
  blocked-medium : 短行 500,000 + 長行  6,422 = 506,422 行 (1.45 波)
  blocked-large  : 短行 2,000,000 + 長行 6,422 = 2,006,422 行 (5.76 波)

  前半ブロック: 短行（1〜15文字）
  後半ブロック: 長行（500文字以上）
"""

import random, itertools, os, statistics

WIKI_PATH = "data/wiki_plain.txt"
OUT_DIR   = "data/experiment"
SEED = 42

# RTX 5090 スペック
GPU_CONCURRENT_THREADS = 348_160
LPC = 8
N_LONG_LINES = 6_422  # 元の blocked.txt に合わせて固定

def make_blocked(name, n_short, short_pool, long_pool):
    short_lines = list(itertools.islice(itertools.cycle(short_pool), n_short))
    long_lines  = list(itertools.islice(itertools.cycle(long_pool),  N_LONG_LINES))
    lines = short_lines + long_lines  # 前半: 短行ブロック / 後半: 長行ブロック

    total = sum(len(l) for l in lines)
    n_lines = len(lines)
    line_waves  = n_lines / GPU_CONCURRENT_THREADS
    chunk_waves = ((n_lines + LPC - 1) // LPC) / GPU_CONCURRENT_THREADS

    path = f"{OUT_DIR}/{name}.txt"
    with open(path, 'w', encoding='utf-8') as f:
        for l in lines:
            f.write(l + '\n')

    print(f"\n[{name}]")
    print(f"  短行数        : {n_short:>12,}  (avg {statistics.mean(len(l) for l in short_lines):.1f} chars)")
    print(f"  長行数        : {N_LONG_LINES:>12,}  (avg {statistics.mean(len(l) for l in long_lines):.1f} chars)")
    print(f"  合計行数      : {n_lines:>12,}")
    print(f"  合計文字数    : {total:>12,}")
    print(f"  GPU Line 波数 : {line_waves:>12.2f}")
    print(f"  Chunk 波数    : {chunk_waves:>12.2f}")
    print(f"  出力          : {path}")
    return os.path.getsize(path)

def main():
    random.seed(SEED)

    print(f"[1/4] {WIKI_PATH} を読み込み中...")
    with open(WIKI_PATH, encoding='utf-8', errors='ignore') as f:
        all_lines = [line.rstrip('\n') for line in f]
    print(f"  総行数: {len(all_lines):,}")

    print("\n[2/4] プール生成...")
    short_pool = [l for l in all_lines if 1 <= len(l) <= 15]
    long_pool  = [l for l in all_lines if len(l) >= 500]
    random.shuffle(short_pool)
    random.shuffle(long_pool)
    print(f"  短行プール: {len(short_pool):,} 行 (avg {statistics.mean(len(l) for l in short_pool[:1000]):.1f} chars)")
    print(f"  長行プール: {len(long_pool):,} 行 (avg {statistics.mean(len(l) for l in long_pool[:1000]):.1f} chars)")

    os.makedirs(OUT_DIR, exist_ok=True)

    print("\n[3/4] データセット生成中...")
    configs = [
        ("blocked-small",    25_000),
        ("blocked-medium",  500_000),
        ("blocked-large", 2_000_000),
    ]
    for name, n_short in configs:
        make_blocked(name, n_short, short_pool, long_pool)

    print("\n[4/4] 完了")
    print("  次のステップ:")
    for name, _ in configs:
        sz = os.path.getsize(f'{OUT_DIR}/{name}.txt')
        print(f"    bash sprints/001/run_scale_experiment.sh  (file: {name}.txt, size: {sz:,} bytes)")

if __name__ == "__main__":
    main()
