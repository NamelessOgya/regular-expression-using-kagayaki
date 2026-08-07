#!/usr/bin/env python3
"""
plot_scale_results.py - 行数スケール実験の可視化

dynamic-small / dynamic-medium / dynamic-large で
GPU Line / Chunk Static / Chunk Dynamic の性能を比較するグラフを生成する。
"""

import csv
import statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

BASE   = 'results/sprint001_scale'
OUTDIR = 'sprints/001/figures'

DATASETS = [
    ('dynamic-small',   25_000,    1_079_824,  0.07),
    ('dynamic-medium',  500_000,   21_580_457, 1.44),
    ('dynamic-large',  2_000_000,  86_319_148, 5.74),
]
METHODS = ['gpu_line', 'gpu_chunk', 'gpu_chunk_dynamic']
LABELS  = ['GPU Line', 'Chunk Static', 'Chunk Dynamic']
COLORS  = ['#4C9BE8', '#E8774C', '#4CE87A']

# ----- データ読み込み -----
results = {}
for name, n_lines, size, waves in DATASETS:
    row = {}
    for m in METHODS:
        path = f'{BASE}/{name}/{m}/avg.csv'
        rows = list(csv.DictReader(open(path)))
        times = [float(r['実行時間(秒)']) * 1000 for r in rows]
        pre   = [float(r['CPU前処理(秒)']) * 1000 for r in rows]
        gpu   = [float(r['GPU実行(秒)']) * 1000 for r in rows]
        row[m] = {
            'tot': statistics.mean(times),
            'pre': statistics.mean(pre),
            'gpu': statistics.mean(gpu),
        }
    results[name] = row

# ----- Figure 1: 合計実行時間の棒グラフ（行数別グループ） -----
fig, axes = plt.subplots(1, 2, figsize=(14, 6))
fig.patch.set_facecolor('#0F1117')
for ax in axes: ax.set_facecolor('#1A1D2E')

n_groups  = len(DATASETS)
n_methods = len(METHODS)
x         = np.arange(n_groups)
width     = 0.25

labels_x = [f"{d[0]}\n({d[1]//1000}K lines\n{d[3]:.2f} waves)" for d in DATASETS]

# 左: 合計実行時間
ax = axes[0]
for j, (m, label, color) in enumerate(zip(METHODS, LABELS, COLORS)):
    vals = [results[d[0]][m]['tot'] for d in DATASETS]
    bars = ax.bar(x + j * width, vals, width, label=label, color=color, alpha=0.9, edgecolor='white', linewidth=0.5)
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3, f'{v:.1f}', 
                ha='center', va='bottom', fontsize=8, color='white', fontweight='bold')

ax.set_xticks(x + width)
ax.set_xticklabels(labels_x, color='white', fontsize=9)
ax.set_xlabel('Dataset (line count / GPU waves)', color='white', fontsize=11)
ax.set_ylabel('Total Execution Time (ms)\n[averaged over 30 regex patterns]', color='white', fontsize=10)
ax.set_title('Total Execution Time by Dataset Scale', color='white', fontsize=13, fontweight='bold')
ax.tick_params(colors='white')
ax.spines['bottom'].set_color('#555'); ax.spines['left'].set_color('#555')
ax.spines['top'].set_visible(False);  ax.spines['right'].set_visible(False)
ax.set_ylim(0, max(results[d[0]]['gpu_line']['tot'] for d in DATASETS) * 1.25)
ax.legend(facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=10)
ax.grid(axis='y', color='#333', linestyle='--', alpha=0.5)

# 右: GPU実行時間のみ（CPU前処理を除く）
ax = axes[1]
for j, (m, label, color) in enumerate(zip(METHODS, LABELS, COLORS)):
    vals = [results[d[0]][m]['gpu'] for d in DATASETS]
    bars = ax.bar(x + j * width, vals, width, label=label, color=color, alpha=0.9, edgecolor='white', linewidth=0.5)
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3, f'{v:.1f}',
                ha='center', va='bottom', fontsize=8, color='white', fontweight='bold')

ax.set_xticks(x + width)
ax.set_xticklabels(labels_x, color='white', fontsize=9)
ax.set_xlabel('Dataset (line count / GPU waves)', color='white', fontsize=11)
ax.set_ylabel('GPU Execution Time (ms)\n[cudaMemcpy + kernel + sync]', color='white', fontsize=10)
ax.set_title('GPU Execution Time by Dataset Scale\n(CPU preprocessing excluded)', color='white', fontsize=13, fontweight='bold')
ax.tick_params(colors='white')
ax.spines['bottom'].set_color('#555'); ax.spines['left'].set_color('#555')
ax.spines['top'].set_visible(False);  ax.spines['right'].set_visible(False)
ax.legend(facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=10)
ax.grid(axis='y', color='#333', linestyle='--', alpha=0.5)

# 注記
fig.text(0.5, 0.01,
    'RTX 5090: 348,160 concurrent threads | Block size=256 | LPC=8 | uniform lines (30-60 chars) | 3-run average',
    ha='center', color='#888', fontsize=8)

plt.tight_layout(rect=[0, 0.04, 1, 1])
path1 = f'{OUTDIR}/fig5_linecount_scaling.png'
plt.savefig(path1, dpi=150, bbox_inches='tight', facecolor='#0F1117')
plt.close()
print(f"Saved: {path1}")

# ----- Figure 2: Line/Static 比率 vs GPU 波数 -----
fig, ax = plt.subplots(figsize=(9, 6))
fig.patch.set_facecolor('#0F1117')
ax.set_facecolor('#1A1D2E')

waves_list = [d[3] for d in DATASETS]
line_sta_ratio = [results[d[0]]['gpu_line']['tot'] / results[d[0]]['gpu_chunk']['tot'] for d in DATASETS]
dyn_sta_ratio  = [results[d[0]]['gpu_chunk_dynamic']['tot'] / results[d[0]]['gpu_chunk']['tot'] for d in DATASETS]

ax.plot(waves_list, line_sta_ratio, 'o-', color='#4C9BE8', lw=2.5, ms=9, label='Line / Static ratio', zorder=5)
ax.plot(waves_list, dyn_sta_ratio,  's--', color='#4CE87A', lw=2, ms=8, label='Dynamic / Static ratio', zorder=5)
ax.axhline(1.0, color='#FF6B6B', lw=1.5, linestyle=':', label='Break-even (ratio = 1.0)')
ax.fill_between([0, 7], 0.9, 1.0, color='#4CE87A', alpha=0.06)  # Dynamic advantage zone
ax.fill_between([0, 7], 1.0, 1.5, color='#E8774C', alpha=0.06)  # Line disadvantage zone

# データポイントにラベル
for waves, r_line, r_dyn, ds in zip(waves_list, line_sta_ratio, dyn_sta_ratio, DATASETS):
    ax.annotate(f"{ds[0].split('-')[1]}\n({ds[1]//1000}K lines)",
                (waves, r_line), textcoords="offset points", xytext=(8, -15),
                color='#4C9BE8', fontsize=8)

ax.set_xlabel('GPU Line Waves\n(n_lines / 348,160 concurrent threads)', color='white', fontsize=12)
ax.set_ylabel('Execution Time Ratio vs Chunk Static', color='white', fontsize=12)
ax.set_title('GPU Line Performance Degradation as Line Count Increases\n(uniform line length, RTX 5090)', 
             color='white', fontsize=13, fontweight='bold')
ax.set_xlim(-0.2, 7)
ax.set_ylim(0.85, 1.55)
ax.tick_params(colors='white')
ax.spines['bottom'].set_color('#555'); ax.spines['left'].set_color('#555')
ax.spines['top'].set_visible(False);  ax.spines['right'].set_visible(False)
ax.legend(facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=10)
ax.grid(color='#333', linestyle='--', alpha=0.5)

# テキスト注記
ax.text(5.5, 1.34, 'Line 35% slower\nthan Static', color='#4C9BE8', fontsize=9, ha='center',
        bbox=dict(boxstyle='round,pad=0.3', facecolor='#1A1D2E', edgecolor='#4C9BE8', alpha=0.8))

plt.tight_layout()
path2 = f'{OUTDIR}/fig6_gpu_line_waves.png'
plt.savefig(path2, dpi=150, bbox_inches='tight', facecolor='#0F1117')
plt.close()
print(f"Saved: {path2}")
