#!/usr/bin/env python3
"""
plot_lpc_sweep.py  - LINES_PER_CHUNK スイープ結果を可視化するスクリプト

使い方:
  python3 scripts/plot_lpc_sweep.py \\
      --lpc 1:results/run_xxx/lpc_sweep/lpc_1/avg.csv \\
      --lpc 4:results/run_xxx/lpc_sweep/lpc_4/avg.csv \\
      --lpc 8:results/run_xxx/lpc_sweep/lpc_8/avg.csv \\
      --cpu   results/run_xxx/cpu/avg.csv \\
      --gpu-line results/run_xxx/gpu_line/avg.csv \\
      --out   results/run_xxx/plots/

出力:
  lpc_sweep_grid.png          ... 全パターンをまとめたグリッド図
  lpc_sweep_<regex>.png       ... 正規表現ごとの個別図
"""

import argparse
import csv
import os
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import matplotlib.cm as cm
import numpy as np

TIMEOUT_SEC = 300.0


def load_sweep(filepath: str) -> dict:
    data = {}
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


def _safe_filename(regex: str) -> str:
    table = str.maketrans({
        "*": "star", "+": "plus", "|": "or", "?": "q",
        "[": "", "]": "", "/": "_", "\\": "_", " ": "_",
    })
    return regex.translate(table)[:40]


def _plot_one(ax, regex: str,
              lpc_datasets: list[tuple[int, dict]],
              cpu_data: dict | None,
              gpu_line_data: dict | None):
    """1 つの正規表現について LPC 値ごとの実行時間を描画"""

    # LPC ごとに色を cmap で割り当て
    n = len(lpc_datasets)
    colors = cm.plasma(np.linspace(0.15, 0.85, n))

    markers = ["o", "s", "^", "D", "v", "P", "X", "*"]

    for idx, (lpc, data) in enumerate(lpc_datasets):
        sizes = sorted(data.keys())
        times = [data[s] for s in sizes]
        color = colors[idx]
        marker = markers[idx % len(markers)]
        ax.plot(sizes, times, marker=marker, linestyle="--",
                color=color, label=f"Chunk (N={lpc})",
                linewidth=1.8, markersize=6, zorder=3)

    # CPU / GPU-Line は参考線として表示
    if cpu_data:
        cpu_data_r = cpu_data.get(regex, {})
        sizes = sorted(cpu_data_r.keys())
        times = [cpu_data_r[s] for s in sizes]
        if sizes:
            ax.plot(sizes, times, marker="o", linestyle="-",
                    color="#2E86C1", label="CPU", linewidth=2.2,
                    markersize=7, zorder=4)

    if gpu_line_data:
        gld = gpu_line_data.get(regex, {})
        sizes = sorted(gld.keys())
        times = [gld[s] for s in sizes]
        if sizes:
            ax.plot(sizes, times, marker="s", linestyle="-",
                    color="#E74C3C", label="GPU Line-Parallel",
                    linewidth=2.2, markersize=7, zorder=4)

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel("Text size (chars)", fontsize=9)
    ax.set_ylabel("Execution time (sec)", fontsize=9)
    ax.set_title(f"regex:  {regex}", fontsize=10, fontweight="bold", pad=6)
    ax.grid(True, which="both", linestyle="--", alpha=0.4, color="gray")
    ax.legend(fontsize=7, loc="upper left", ncol=2)
    ax.xaxis.set_major_formatter(
        ticker.FuncFormatter(lambda x, _: f"{int(x):,}")
    )
    ax.tick_params(axis="x", rotation=25, labelsize=7)
    ax.tick_params(axis="y", labelsize=7)
    ax.axhline(y=TIMEOUT_SEC, color="gray", linestyle=":", linewidth=1)


def plot_all(lpc_datasets: list[tuple[int, dict]],
             cpu_data: dict | None,
             gpu_line_data: dict | None,
             out_dir: str):
    Path(out_dir).mkdir(parents=True, exist_ok=True)

    # 全 LPC データから正規表現リストを収集
    all_regexes = set()
    for _, d in lpc_datasets:
        all_regexes.update(d.keys())
    if cpu_data:
        all_regexes.update(cpu_data.keys())
    all_regexes = sorted(all_regexes)

    print(f"Output dir: {out_dir}")

    # ---- グリッドプロット ----
    n = len(all_regexes)
    cols = 2
    rows = (n + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols,
                             figsize=(cols * 7, rows * 4.5),
                             squeeze=False)
    fig.suptitle("NFA Benchmark: LINES_PER_CHUNK Sweep (GPU Chunk-Parallel)",
                 fontsize=14, fontweight="bold", y=1.002)

    for idx, regex in enumerate(all_regexes):
        r, c = divmod(idx, cols)
        ax = axes[r][c]
        per_regex = [(lpc, d.get(regex, {})) for lpc, d in lpc_datasets]
        _plot_one(ax, regex, per_regex, cpu_data, gpu_line_data)

    # 余った軸を非表示
    for idx in range(len(all_regexes), rows * cols):
        r, c = divmod(idx, cols)
        axes[r][c].set_visible(False)

    fig.tight_layout()
    grid_path = os.path.join(out_dir, "lpc_sweep_grid.png")
    fig.savefig(grid_path, dpi=120, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {grid_path}")

    # ---- 個別プロット ----
    for regex in all_regexes:
        fig, ax = plt.subplots(figsize=(8, 5))
        per_regex = [(lpc, d.get(regex, {})) for lpc, d in lpc_datasets]
        _plot_one(ax, regex, per_regex, cpu_data, gpu_line_data)
        fig.tight_layout()
        fname = f"lpc_sweep_{_safe_filename(regex)}.png"
        path = os.path.join(out_dir, fname)
        fig.savefig(path, dpi=120, bbox_inches="tight")
        plt.close(fig)
        print(f"Saved: {path}")

    print("Done.")


# ============================================================
# エントリポイント
# ============================================================
def main():
    parser = argparse.ArgumentParser(description="Plot LINES_PER_CHUNK sweep results")
    parser.add_argument("--lpc", action="append", default=[],
                        help="N:path/to/avg.csv  (複数指定可)")
    parser.add_argument("--cpu",      default=None, help="CPU avg.csv")
    parser.add_argument("--gpu-line", default=None, help="GPU Line avg.csv")
    parser.add_argument("--out",      default="./results/lpc_plots", help="出力ディレクトリ")
    args = parser.parse_args()

    if not args.lpc:
        parser.error("--lpc N:path を少なくとも1つ指定してください")

    lpc_datasets = []
    for spec in args.lpc:
        n_str, path = spec.split(":", 1)
        print(f"Loading LPC={n_str:>3} : {path}")
        lpc_datasets.append((int(n_str), load_sweep(path)))
    # N の昇順に並べる
    lpc_datasets.sort(key=lambda x: x[0])

    cpu_data      = load_sweep(args.cpu)      if args.cpu      else None
    gpu_line_data = load_sweep(args.gpu_line) if args.gpu_line else None

    plot_all(lpc_datasets, cpu_data, gpu_line_data, args.out)


if __name__ == "__main__":
    main()
