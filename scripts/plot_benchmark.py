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
    sweep CSV を読み込み、{正規表現: {文字数: {"total": float, "cpu_pre": float, "gpu_exec": float}}} の辞書を返す。
    タイムアウト行の実行時間は TIMEOUT_SEC (300.0) として扱う。
    """
    data = {}
    with open(filepath, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            regex = row["正規表現"].strip().rstrip("\n\r")
            size  = int(row["文字数"])
            note  = row.get("備考", "").strip()
            
            try:
                total = float(row["実行時間(秒)"])
            except (ValueError, KeyError):
                total = TIMEOUT_SEC
            if note == "TIMEOUT":
                total = TIMEOUT_SEC
                
            cpu_pre_str = row.get("CPU前処理(秒)")
            gpu_exec_str = row.get("GPU実行(秒)")
            
            try:
                cpu_pre = float(cpu_pre_str) if cpu_pre_str is not None else 0.0
            except ValueError:
                cpu_pre = 0.0
                
            try:
                gpu_exec = float(gpu_exec_str) if gpu_exec_str is not None else total
            except ValueError:
                gpu_exec = total
                
            if note == "TIMEOUT":
                cpu_pre = 0.0
                gpu_exec = TIMEOUT_SEC
                
            data.setdefault(regex, {})[size] = {
                "total": total,
                "cpu_pre": cpu_pre,
                "gpu_exec": gpu_exec
            }
    return data


# ============================================================
# プロット
# ============================================================

COLOR_CPU               = "#2E86C1"   # 青
COLOR_GPU_LINE_EXEC     = "#C0392B"   # 濃い赤 (GPU Execution Line)
COLOR_GPU_LINE_PRE      = "#E8ADAA"   # 薄い赤 / ピンク (CPU Preprocess Line)
COLOR_GPU_CHUNK_DYN_EXEC= "#D35400"   # 濃いオレンジ (GPU Execution Dynamic)
COLOR_GPU_CHUNK_DYN_PRE = "#F5CBA7"   # 薄いオレンジ / 黄 (CPU Preprocess Dynamic)

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
              gpu_chunk: dict,
              gpu_chunk_dynamic: dict = None):
    """1つの正規表現について CPU、GPU (Line-Parallel)、GPU (Chunk-Dynamic) の実行時間をグループ化積み上げ棒グラフで描画する"""
    sizes = sorted(list(set(
        list(cpu.keys()) +
        (list(gpu_line.keys()) if gpu_line else []) +
        (list(gpu_chunk_dynamic.keys()) if gpu_chunk_dynamic else [])
    )))
    if not sizes:
        return

    x = list(range(len(sizes)))
    width = 0.25
    baseline = 1e-6

    cpu_totals = []
    line_execs = []
    line_pres = []
    dyn_execs = []
    dyn_pres = []

    for s in sizes:
        # CPU
        if s in cpu:
            cpu_totals.append(max(cpu[s]["total"], baseline))
        else:
            cpu_totals.append(baseline)
        
        # GPU Line-Parallel
        if gpu_line and s in gpu_line:
            line_execs.append(max(gpu_line[s]["gpu_exec"], baseline))
            line_pres.append(max(gpu_line[s]["cpu_pre"], baseline))
        else:
            line_execs.append(baseline)
            line_pres.append(baseline)
            
        # GPU Chunk-Dynamic
        if gpu_chunk_dynamic and s in gpu_chunk_dynamic:
            dyn_execs.append(max(gpu_chunk_dynamic[s]["gpu_exec"], baseline))
            dyn_pres.append(max(gpu_chunk_dynamic[s]["cpu_pre"], baseline))
        else:
            dyn_execs.append(baseline)
            dyn_pres.append(baseline)

    # Plot bars
    x_cpu = [val - width for val in x]
    x_line = x
    x_dyn = [val + width for val in x]

    ax.bar(x_cpu, cpu_totals, width, bottom=baseline, color=COLOR_CPU, label="CPU", zorder=3)

    ax.bar(x_line, line_execs, width, bottom=baseline, color=COLOR_GPU_LINE_EXEC, label="GPU Exec (Line)", zorder=3)
    line_stack_bottom = [baseline + le for le in line_execs]
    ax.bar(x_line, line_pres, width, bottom=line_stack_bottom, color=COLOR_GPU_LINE_PRE, label="CPU Pre (Line)", zorder=3)

    ax.bar(x_dyn, dyn_execs, width, bottom=baseline, color=COLOR_GPU_CHUNK_DYN_EXEC, label="GPU Exec (Dynamic)", zorder=3)
    dyn_stack_bottom = [baseline + de for de in dyn_execs]
    ax.bar(x_dyn, dyn_pres, width, bottom=dyn_stack_bottom, color=COLOR_GPU_CHUNK_DYN_PRE, label="CPU Pre (Dynamic)", zorder=3)

    # Annotate TIMEOUTs
    for i, s in enumerate(sizes):
        if s in cpu and cpu[s]["total"] >= TIMEOUT_SEC:
            ax.text(i - width, TIMEOUT_SEC, "TIMEOUT", ha="center", va="bottom", fontsize=7, color=COLOR_CPU, rotation=90)
        if gpu_line and s in gpu_line and gpu_line[s]["total"] >= TIMEOUT_SEC:
            ax.text(i, TIMEOUT_SEC, "TIMEOUT", ha="center", va="bottom", fontsize=7, color=COLOR_GPU_LINE_EXEC, rotation=90)
        if gpu_chunk_dynamic and s in gpu_chunk_dynamic and gpu_chunk_dynamic[s]["total"] >= TIMEOUT_SEC:
            ax.text(i + width, TIMEOUT_SEC, "TIMEOUT", ha="center", va="bottom", fontsize=7, color=COLOR_GPU_CHUNK_DYN_EXEC, rotation=90)

    ax.set_yscale("log")
    ax.set_ylim(bottom=1e-5, top=TIMEOUT_SEC * 3)
    ax.set_xticks(x)
    ax.set_xticklabels([f"{s:,}" for s in sizes])
    
    ax.set_xlabel("Text size (chars)", fontsize=10)
    ax.set_ylabel("Execution time (sec)", fontsize=10)
    ax.set_title(f"regex:  {regex}", fontsize=11, fontweight="bold", pad=8)
    ax.grid(True, which="both", linestyle="--", alpha=0.4, color="gray")
    
    # Filter duplicate legend entries
    handles, labels = ax.get_legend_handles_labels()
    by_label = dict(zip(labels, handles))
    ax.legend(by_label.values(), by_label.keys(), fontsize=9, loc="upper left")

    ax.tick_params(axis="x", rotation=25, labelsize=8)
    ax.tick_params(axis="y", labelsize=8)

    # タイムアウト上限ラインを点線で表示
    ax.axhline(y=TIMEOUT_SEC, color="gray", linestyle=":", linewidth=1)


def plot_all(cpu_data: dict,
             gpu_line_data: dict | None,
             gpu_chunk_data: dict | None,
             gpu_chunk_dyn_data: dict | None,
             out_dir: str):
    Path(out_dir).mkdir(parents=True, exist_ok=True)
    all_regexes = sorted(set(
        list(cpu_data.keys()) +
        (list(gpu_line_data.keys())  if gpu_line_data  else []) +
        (list(gpu_chunk_data.keys()) if gpu_chunk_data else []) +
        (list(gpu_chunk_dyn_data.keys()) if gpu_chunk_dyn_data else [])
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
    fig.suptitle("NFA Benchmark: CPU vs GPU (Line-Parallel vs Dynamic Chunking Breakdown)",
                 fontsize=14, fontweight="bold", y=1.005)

    axes_flat = axes.flatten() if n > 1 else [axes]
    for i, regex in enumerate(all_regexes):
        _plot_one(axes_flat[i], regex,
                  cpu_data.get(regex, {}),
                  gpu_line_data.get(regex,  {}) if gpu_line_data  else {},
                  gpu_chunk_data.get(regex, {}) if gpu_chunk_data else {},
                  gpu_chunk_dyn_data.get(regex, {}) if gpu_chunk_dyn_data else {})

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
                  gpu_chunk_data.get(regex, {}) if gpu_chunk_data else {},
                  gpu_chunk_dyn_data.get(regex, {}) if gpu_chunk_dyn_data else {})
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
    parser.add_argument("--gpu-chunk-dynamic", default=None,
                        help="GPU Chunk-Parallel Dynamic summary CSV")
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

    gpu_chunk_dyn_data = None
    if args.gpu_chunk_dynamic:
        if not os.path.exists(args.gpu_chunk_dynamic):
            print(f"[WARN] GPU-Chunk-Dynamic CSV not found: {args.gpu_chunk_dynamic}")
        else:
            print(f"Loading GPU-Chunk-Dynamic data : {args.gpu_chunk_dynamic}")
            gpu_chunk_dyn_data = load_sweep(args.gpu_chunk_dynamic)
            print(f"  -> {len(gpu_chunk_dyn_data)} patterns")

    print(f"Output dir: {args.out}")
    plot_all(cpu_data, gpu_line_data, gpu_chunk_data, gpu_chunk_dyn_data, args.out)
    print("Done.")


if __name__ == "__main__":
    main()
