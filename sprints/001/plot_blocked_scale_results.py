#!/usr/bin/env python3
"""
plot_blocked_scale_results.py - ブロック型・行数スケール実験の可視化

blocked-small / blocked-medium / blocked-large で
GPU Line / Chunk Static / Chunk Dynamic の性能を比較するグラフを生成する。
"""
import csv, statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

BASE   = 'results/sprint001_blocked_scale'
OUTDIR = 'sprints/001/figures'

DATASETS = [
    ('blocked-small',    31_422,  5_276_414, 0.09),
    ('blocked-medium',  506_422, 10_298_334, 1.45),
    ('blocked-large', 2_006_422, 26_166_954, 5.76),
]
METHODS = ['gpu_line', 'gpu_chunk', 'gpu_chunk_dynamic']
LABELS  = ['GPU Line', 'Chunk Static', 'Chunk Dynamic']
COLORS  = ['#4C9BE8', '#E8774C', '#4CE87A']

results = {}
for name, n_lines, size, waves in DATASETS:
    row = {}
    for m in METHODS:
        rows = list(csv.DictReader(open(f'{BASE}/{name}/{m}/avg.csv')))
        row[m] = {
            'tot': statistics.mean(float(r['実行時間(秒)'])*1000 for r in rows),
            'pre': statistics.mean(float(r['CPU前処理(秒)'])*1000 for r in rows),
            'gpu': statistics.mean(float(r['GPU実行(秒)'])*1000 for r in rows),
        }
    results[name] = row

# ----- Figure: 積み上げ棒グラフ (pre + gpu) + ratio折れ線 -----
fig, axes = plt.subplots(1, 2, figsize=(15, 6))
fig.patch.set_facecolor('#0F1117')
for ax in axes: ax.set_facecolor('#1A1D2E')

x     = np.arange(len(DATASETS))
width = 0.25
labels_x = [f"{d[0]}\n({d[1]//1000}K lines\n{d[3]:.2f} waves)" for d in DATASETS]

# 左: 積み上げ棒グラフ (pre + gpu)
ax = axes[0]
for j, (m, label, color) in enumerate(zip(METHODS, LABELS, COLORS)):
    pre_vals = [results[d[0]][m]['pre'] for d in DATASETS]
    gpu_vals = [results[d[0]][m]['gpu'] for d in DATASETS]
    tot_vals = [results[d[0]][m]['tot'] for d in DATASETS]
    bars_pre = ax.bar(x + j*width, pre_vals, width, label=f'{label} (preproc)',
                      color=color, alpha=0.4, edgecolor='white', linewidth=0.3)
    bars_gpu = ax.bar(x + j*width, gpu_vals, width, bottom=pre_vals, label=f'{label} (GPU)',
                      color=color, alpha=0.9, edgecolor='white', linewidth=0.5)
    for bar, total in zip(bars_gpu, tot_vals):
        ax.text(bar.get_x() + bar.get_width()/2, total + 0.3,
                f'{total:.1f}', ha='center', va='bottom', fontsize=8, color='white', fontweight='bold')

ax.set_xticks(x + width)
ax.set_xticklabels(labels_x, color='white', fontsize=9)
ax.set_xlabel('Dataset (line count / GPU waves)', color='white', fontsize=11)
ax.set_ylabel('Execution Time (ms)\n[dark=GPU kernel, light=CPU preprocessing]', color='white', fontsize=10)
ax.set_title('Blocked-Scale: Total Time by Method\n(6,422 long lines fixed, short lines scaled)', color='white', fontsize=12, fontweight='bold')
ax.tick_params(colors='white')
ax.spines['bottom'].set_color('#555'); ax.spines['left'].set_color('#555')
ax.spines['top'].set_visible(False);  ax.spines['right'].set_visible(False)

# カスタム凡例（pre/gpu 分けない）
handles = [plt.Rectangle((0,0),1,1, color=c, alpha=0.9) for c in COLORS]
ax.legend(handles, LABELS, facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=10)
ax.grid(axis='y', color='#333', linestyle='--', alpha=0.5)
ax.set_ylim(0, max(results[d[0]]['gpu_line']['tot'] for d in DATASETS) * 1.3)

# 右: 比率折れ線グラフ
ax = axes[1]
waves_list = [d[3] for d in DATASETS]
line_sta   = [results[d[0]]['gpu_line']['tot'] / results[d[0]]['gpu_chunk']['tot'] for d in DATASETS]
dyn_sta    = [results[d[0]]['gpu_chunk_dynamic']['tot'] / results[d[0]]['gpu_chunk']['tot'] for d in DATASETS]
line_dyn   = [results[d[0]]['gpu_line']['tot'] / results[d[0]]['gpu_chunk_dynamic']['tot'] for d in DATASETS]

ax.plot(waves_list, line_sta, 'o-',  color='#4C9BE8', lw=2.5, ms=9, label='Line / Static')
ax.plot(waves_list, dyn_sta,  's--', color='#4CE87A', lw=2.5, ms=9, label='Dynamic / Static')
ax.plot(waves_list, line_dyn, '^:',  color='#E8E84C', lw=2, ms=8, label='Line / Dynamic')
ax.axhline(1.0, color='#FF6B6B', lw=1.5, linestyle=':', label='Break-even')

# データポイントラベル
for i, (waves, r1, r2, r3, ds) in enumerate(zip(waves_list, line_sta, dyn_sta, line_dyn, DATASETS)):
    ax.annotate(f"Line={results[ds[0]]['gpu_line']['tot']:.1f}ms\nSta={results[ds[0]]['gpu_chunk']['tot']:.1f}ms\nDyn={results[ds[0]]['gpu_chunk_dynamic']['tot']:.1f}ms",
                (waves, r1), textcoords="offset points", xytext=(8, 10),
                color='white', fontsize=7,
                bbox=dict(boxstyle='round,pad=0.2', facecolor='#1A1D2E', edgecolor='#555', alpha=0.8))

ax.set_xlabel('GPU Line Waves (n_lines / 348,160)', color='white', fontsize=11)
ax.set_ylabel('Execution Time Ratio vs Chunk Static', color='white', fontsize=11)
ax.set_title('Blocked-Scale: Performance Ratios vs GPU Waves\n(blocked structure: short-line + long-line blocks)', color='white', fontsize=12, fontweight='bold')
ax.tick_params(colors='white')
ax.spines['bottom'].set_color('#555'); ax.spines['left'].set_color('#555')
ax.spines['top'].set_visible(False);  ax.spines['right'].set_visible(False)
ax.legend(facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=10)
ax.grid(color='#333', linestyle='--', alpha=0.5)
ax.set_xlim(-0.2, 7)
ax.set_ylim(0.5, 1.2)

fig.text(0.5, 0.01,
    'RTX 5090 | LPC=8 | short lines: 1-15 chars (avg 9) | long lines: 500+ chars (avg 779) | 3-run average',
    ha='center', color='#888', fontsize=8)
plt.tight_layout(rect=[0, 0.04, 1, 1])

path = f'{OUTDIR}/fig7_blocked_scale.png'
plt.savefig(path, dpi=150, bbox_inches='tight', facecolor='#0F1117')
plt.close()
print(f"Saved: {path}")
