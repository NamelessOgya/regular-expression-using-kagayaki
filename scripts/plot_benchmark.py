#!/usr/bin/env python3
"""
plot_benchmark.py - ベンチマーク結果をグラフで可視化するスクリプト

使い方:
  # CPU のみ
  python3 scripts/plot_benchmark.py --cpu results/cpu/avg.csv

  # CPU + GPU 2種比較
  python3 scripts/plot_benchmark.py \
      --cpu        results/run_xxx/cpu/avg.csv \
      --gpu-line   results/run_xxx/gpu_line/avg.csv \
      --gpu-chunk  results/run_xxx/gpu_chunk/avg.csv \
      --out        results/run_xxx/plots/

出力:
  benchmark_grid.png          ... 全パターンをまとめたグリッド図
  benchmark_<regex>.png       ... 正規表現ごとの個別図
"""

import argparse
import csv
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # GUI なし環境でも動作
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

TIMEOUT_SEC = 300.0

# ============================================================
# データ読み込み
# ============================================================

def load_sweep(filepath: str) -> dict:
    """
    sweep CSV を読み込み、{正規表現: {文字数: 実行時間}} の辞書を返す。
    タイムアウト行の実行時間は TIMEOUT_SEC (300.0) として扱う。
    """
    data: dict[str, dict[int, float]] = {}
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            regex = row["正規表現"].strip().rstrip("\n\r")
            size  = int(row["文字数"])
            note  = row.get("備考", "").strip()
            try:
                time = float(row["実行時間(秒)"])
            except (ValueError, KeyError):
                time = TIMEOUT_SEC
            if note == "TIMEOUT":
                time = TIMEOUT_SEC
            data.setdefault(regex, {})[size] = time
    return data


# ============================================================
# プロット
# ============================================================

COLOR_CPU       = "#2E86C1"   # 青
COLOR_GPU_LINE  = "#E74C3C"   # 赤（愚直 GPU: 行並列）
COLOR_GPU_CHUNK = "#27AE60"   # 緑（チャンク並列 GPU）

def _safe_filename(regex: str) -> str:
    """正規表現を安全なファイル名に変換する"""
    table = str.maketrans({
        "*": "star", "+": "plus", "|": "or", "?": "q",
        "[": "", "]": "", "/": "_", "\\": "_", " ": "_",
    })
    return regex.translate(table)[:40]


def _plot_one(ax, regex: str,
              cpu: dict,
              gpu_line: dict,
              gpu_chunk: dict):
    """1つの正規表現について CPU / GPU×2 の実行時間を ax に描画する"""
    def draw(sizes, times, color, label, marker, linestyle):
        if not sizes:
            return
        is_to = [t >= TIMEOUT_SEC for t in times]
        ax.plot(sizes, times, marker=marker, linestyle=linestyle,
                color=color, label=label, linewidth=2, markersize=7, zorder=3)
        for s, t, to in zip(sizes, times, is_to):
            if to:
                ax.annotate("TIMEOUT",
                            xy=(s, t), xytext=(8, -12),
                            textcoords="offset points",
                            fontsize=7, color=color,
                            arrowprops=dict(arrowstyle="-", color=color, lw=0.8))

    cpu_sizes       = sorted(cpu.keys())
    cpu_times       = [cpu[s] for s in cpu_sizes]
    gpu_line_sizes  = sorted(gpu_line.keys())  if gpu_line  else []
    gpu_line_times  = [gpu_line[s]  for s in gpu_line_sizes]
    gpu_chunk_sizes = sorted(gpu_chunk.keys()) if gpu_chunk else []
    gpu_chunk_times = [gpu_chunk[s] for s in gpu_chunk_sizes]

    draw(cpu_sizes,       cpu_times,       COLOR_CPU,       "CPU",              "o", "-")
    draw(gpu_line_sizes,  gpu_line_times,  COLOR_GPU_LINE,  "GPU (Line-Parallel)",  "s", "--")
    draw(gpu_chunk_sizes, gpu_chunk_times, COLOR_GPU_CHUNK, "GPU (Chunk-Parallel)", "^", "-.")

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Text size (chars)", fontsize=10)
    ax.set_ylabel("Execution time (sec)", fontsize=10)
    ax.set_title(f"regex:  {regex}", fontsize=11, fontweight="bold", pad=8)
    ax.grid(True, which="both", linestyle="--", alpha=0.4, color="gray")
    ax.legend(fontsize=9, loc="upper left")
    ax.xaxis.set_major_formatter(
        ticker.FuncFormatter(lambda x, _: f"{int(x):,}")
    )
    ax.tick_params(axis="x", rotation=25, labelsize=8)
    ax.tick_params(axis="y", labelsize=8)

    # タイムアウト上限ラインを点線で表示
    ax.axhline(y=TIMEOUT_SEC, color="gray", linestyle=":", linewidth=1,
               label=f"timeout ({int(TIMEOUT_SEC)}s)")


def plot_all(cpu_data: dict,
             gpu_line_data: dict | None,
             gpu_chunk_data: dict | None,
             out_dir: str):
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    all_regexes = sorted(set(
        list(cpu_data.keys()) +
        (list(gpu_line_data.keys())  if gpu_line_data  else []) +
        (list(gpu_chunk_data.keys()) if gpu_chunk_data else [])
    ))
    n = len(all_regexes)
    if n == 0:
        print("[ERROR] No data to plot.")
        sys.exit(1)

    # ----------------------------------------------------------
    # 1. グリッド図（全パターンを1枚に）
    # ----------------------------------------------------------
    ncols = 2
    nrows = (n + ncols - 1) // ncols
    fig, axes = plt.subplots(nrows, ncols, figsize=(14, nrows * 4.5))
    fig.suptitle("NFA Benchmark: CPU vs GPU Line-Parallel vs GPU Chunk-Parallel",
                 fontsize=14, fontweight="bold", y=1.005)

    axes_flat = axes.flatten() if n > 1 else [axes]
    for i, regex in enumerate(all_regexes):
        _plot_one(axes_flat[i], regex,
                  cpu_data.get(regex, {}),
                  gpu_line_data.get(regex,  {}) if gpu_line_data  else {},
                  gpu_chunk_data.get(regex, {}) if gpu_chunk_data else {})

    for j in range(i + 1, len(axes_flat)):
        axes_flat[j].set_visible(False)

    fig.tight_layout(pad=2.5)
    grid_path = os.path.join(out_dir, "benchmark_grid.png")
    fig.savefig(grid_path, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {grid_path}")

    # ----------------------------------------------------------
    # 2. 正規表現ごとの個別図
    # ----------------------------------------------------------
    for regex in all_regexes:
        fig2, ax2 = plt.subplots(figsize=(8, 5))
        _plot_one(ax2, regex,
                  cpu_data.get(regex, {}),
                  gpu_line_data.get(regex,  {}) if gpu_line_data  else {},
                  gpu_chunk_data.get(regex, {}) if gpu_chunk_data else {})
        fig2.tight_layout()
        single_path = os.path.join(out_dir, f"benchmark_{_safe_filename(regex)}.png")
        fig2.savefig(single_path, dpi=150, bbox_inches="tight")
        plt.close(fig2)
        print(f"Saved: {single_path}")


# ============================================================
# エントリポイント
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Plot NFA benchmark sweep results (CPU vs GPU×2).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--cpu", required=True,
                        help="CPU sweep summary CSV")
    parser.add_argument("--gpu-line", default=None,
                        help="GPU Line-Parallel summary CSV（愚直GPU）")
    parser.add_argument("--gpu-chunk", default=None,
                        help="GPU Chunk-Parallel summary CSV（チャンク並列GPU）")
    # 後方互換: --gpu は --gpu-line として扱う
    parser.add_argument("--gpu", default=None,
                        help=argparse.SUPPRESS)
    parser.add_argument("--out", default="./results/plots",
                        help="Output directory for PNG files (default: ./results/plots)")
    args = parser.parse_args()

    # --gpu を --gpu-line の別名として扱う
    if args.gpu and not args.gpu_line:
        args.gpu_line = args.gpu

    if not os.path.exists(args.cpu):
        print(f"[ERROR] CPU CSV not found: {args.cpu}")
        sys.exit(1)

    print(f"Loading CPU data       : {args.cpu}")
    cpu_data = load_sweep(args.cpu)
    print(f"  -> {len(cpu_data)} patterns, "
          f"{sum(len(v) for v in cpu_data.values())} data points")

    gpu_line_data = None
    if args.gpu_line:
        if not os.path.exists(args.gpu_line):
            print(f"[WARN] GPU-Line CSV not found: {args.gpu_line}")
        else:
            print(f"Loading GPU-Line data  : {args.gpu_line}")
            gpu_line_data = load_sweep(args.gpu_line)
            print(f"  -> {len(gpu_line_data)} patterns")

    gpu_chunk_data = None
    if args.gpu_chunk:
        if not os.path.exists(args.gpu_chunk):
            print(f"[WARN] GPU-Chunk CSV not found: {args.gpu_chunk}")
        else:
            print(f"Loading GPU-Chunk data : {args.gpu_chunk}")
            gpu_chunk_data = load_sweep(args.gpu_chunk)
            print(f"  -> {len(gpu_chunk_data)} patterns")

    print(f"Output dir: {args.out}")
    plot_all(cpu_data, gpu_line_data, gpu_chunk_data, args.out)
    print("Done.")


if __name__ == "__main__":
    main()
