#!/usr/bin/env python3
"""
sprint 001 experiment result graph generator (corrected)
Uses avg.csv where available, summary.csv as fallback (single run).
"""
import csv, os, statistics
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

OUT_DIR = "sprints/001/figures"
os.makedirs(OUT_DIR, exist_ok=True)

plt.rcParams.update({
    'axes.spines.top': False, 'axes.spines.right': False,
    'axes.grid': True, 'grid.alpha': 0.3,
    'font.size': 10,
})

# ─── Data loading ──────────────────────────────────────────────
def load_rows(base, method):
    """Load avg.csv if present, else summary.csv (single run)."""
    for fname in ['avg.csv', 'summary.csv']:
        path = f'{base}/{method}/{fname}'
        if os.path.exists(path):
            rows = list(csv.DictReader(open(path)))
            return rows, fname
    return [], None

def get_stats(base, method, max_only=True):
    rows, src = load_rows(base, method)
    if not rows: return None, None
    if max_only:
        max_s = max(int(r['文字数']) for r in rows)
        rows = [r for r in rows if int(r['文字数']) == max_s]
    tot = statistics.mean(float(r['実行時間(秒)']) for r in rows)
    pre = statistics.mean(float(r['CPU前処理(秒)']) for r in rows)
    gpu = statistics.mean(float(r['GPU実行(秒)']) for r in rows)
    size = max(int(r['文字数']) for r in rows)
    return {'total': tot, 'pre': pre, 'gpu': gpu, 'size': size, 'src': src}, len(rows)

# ─── Datasets ──────────────────────────────────────────────────
# enwik8 results (avg.csv, 3 runs) are the reference for large scale
DATASETS = [
    ("enwik8\n(831K lines)",  "results/run_20260807_09_30_15",      407.0),
    ("Uniform\n(157K lines)", "results/sprint001_redo_uniform",      8.6  ),
    ("Varied\n(25K lines)",   "results/run_20260807_11_01_47",       434.1),
    ("Extreme\n(7.6K lines)", "results/sprint001_redo_extreme2",     1355.5),
    ("Blocked\n(196K lines)", "results/sprint001_redo_blocked",      146.2),
]

METHODS   = ['gpu_line', 'gpu_chunk', 'gpu_chunk_dynamic']
MLABELS   = ['GPU Line', 'Chunk Static', 'Chunk Dynamic']
COLORS    = ['#4e79a7', '#59a14f', '#e15759']

# ═══════════════════════════════════════════════════════════════
# Fig 1: Total execution time — all datasets × 3 methods
# ═══════════════════════════════════════════════════════════════
fig, axes = plt.subplots(1, 5, figsize=(20, 5))
fig.suptitle("Total Execution Time by Method and Dataset\n(max text size per dataset, avg of 30 patterns)",
             fontsize=12, y=1.01)

for ax, (label, base, sd) in zip(axes, DATASETS):
    totals = []
    for m in METHODS:
        s, _ = get_stats(base, m)
        totals.append(s['total'] if s else 0)

    x = np.arange(len(METHODS))
    bars = ax.bar(x, totals, 0.6, color=COLORS, alpha=0.85, edgecolor='white')
    ax.set_xticks(x)
    ax.set_xticklabels(MLABELS, fontsize=8, rotation=15, ha='right')
    ax.set_title(label, fontsize=9)
    ax.set_ylabel("Time (s)" if ax == axes[0] else "", fontsize=9)
    for bar, val in zip(bars, totals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(totals)*0.01,
                f'{val*1000:.1f}ms', ha='center', va='bottom', fontsize=8, fontweight='bold')

plt.tight_layout()
plt.savefig(f"{OUT_DIR}/fig1_total_time.png", dpi=150, bbox_inches='tight')
print("[1/4] Saved: fig1_total_time.png")
plt.close()

# ═══════════════════════════════════════════════════════════════
# Fig 2: Dyn/Sta ratio + CPU preprocess breakdown
# ═══════════════════════════════════════════════════════════════
fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))
fig.suptitle("Static vs Dynamic: Performance Ratio and Preprocessing Cost", fontsize=12)

labels_short = [d[0].replace('\n', ' ') for d in DATASETS]
dyn_sta_ratios, pre_static, pre_dynamic = [], [], []

for label, base, sd in DATASETS:
    sc, _ = get_stats(base, 'gpu_chunk')
    gd, _ = get_stats(base, 'gpu_chunk_dynamic')
    if sc and gd:
        dyn_sta_ratios.append(gd['total'] / sc['total'])
        pre_static.append(sc['pre'] * 1000)
        pre_dynamic.append(gd['pre'] * 1000)
    else:
        dyn_sta_ratios.append(1.0)
        pre_static.append(0); pre_dynamic.append(0)

x = np.arange(len(DATASETS))
w = 0.4

# Dyn/Sta ratio bar
colors_ratio = ['#e15759' if r > 1 else '#59a14f' for r in dyn_sta_ratios]
bars = ax1.bar(x, dyn_sta_ratios, 0.6, color=colors_ratio, alpha=0.85, edgecolor='white')
ax1.axhline(1.0, color='gray', linestyle='--', lw=1.5, label='Dyn = Sta')
ax1.set_xticks(x); ax1.set_xticklabels(labels_short, fontsize=8.5)
ax1.set_ylabel("Dyn/Sta Ratio  (< 1.0 = Dynamic faster)", fontsize=9)
ax1.set_title("Dynamic / Static Total Time Ratio", fontsize=11)
for bar, val in zip(bars, dyn_sta_ratios):
    va = 'bottom' if val >= 1.0 else 'top'
    off = 0.02 if val >= 1.0 else -0.02
    ax1.text(bar.get_x()+bar.get_width()/2, val+off,
             f'{val:.3f}x', ha='center', va=va, fontsize=9, fontweight='bold')
ax1.legend(fontsize=9)

# CPU preprocess comparison
b1 = ax2.bar(x - w/2, pre_static,  w, label='Chunk Static',  color='#59a14f', alpha=0.85)
b2 = ax2.bar(x + w/2, pre_dynamic, w, label='Chunk Dynamic', color='#e15759', alpha=0.85)
ax2.set_xticks(x); ax2.set_xticklabels(labels_short, fontsize=8.5)
ax2.set_ylabel("CPU Preprocess Time (ms)", fontsize=9)
ax2.set_title("CPU Preprocessing Cost\n(O(n_lines) scan overhead of Dynamic)", fontsize=11)
ax2.legend(fontsize=9)
for bar in [*b1, *b2]:
    if bar.get_height() > 0.01:
        ax2.text(bar.get_x()+bar.get_width()/2, bar.get_height()*1.02,
                 f'{bar.get_height():.1f}ms', ha='center', va='bottom', fontsize=8)

plt.tight_layout()
plt.savefig(f"{OUT_DIR}/fig2_ratio_and_preprocess.png", dpi=150, bbox_inches='tight')
print("[2/4] Saved: fig2_ratio_and_preprocess.png")
plt.close()

# ═══════════════════════════════════════════════════════════════
# Fig 3: GPU execution time breakdown (preprocess vs gpu exec)
# ═══════════════════════════════════════════════════════════════
fig, axes = plt.subplots(1, 5, figsize=(20, 5))
fig.suptitle("Execution Time Breakdown: CPU Preprocess vs GPU Exec\n(Static vs Dynamic per dataset)",
             fontsize=12, y=1.01)

for ax, (label, base, sd) in zip(axes, DATASETS):
    sc, _ = get_stats(base, 'gpu_chunk')
    gd, _ = get_stats(base, 'gpu_chunk_dynamic')
    if not sc or not gd: continue

    methods = ['Static', 'Dynamic']
    pre_v = [sc['pre']*1000, gd['pre']*1000]
    gpu_v = [sc['gpu']*1000, gd['gpu']*1000]

    x = np.arange(2)
    ax.bar(x, pre_v, 0.5, label='CPU Pre', color='#f28e2b', alpha=0.85)
    ax.bar(x, gpu_v, 0.5, bottom=pre_v, label='GPU Exec', color='#4e79a7', alpha=0.85)
    ax.set_xticks(x); ax.set_xticklabels(methods, fontsize=10)
    ax.set_title(label, fontsize=10)
    ax.set_ylabel("Time (ms)" if ax == axes[0] else "", fontsize=9)

    for i, (p, g) in enumerate(zip(pre_v, gpu_v)):
        ax.text(i, p+g + max(pre_v+gpu_v)*0.02, f'{p+g:.1f}ms',
                ha='center', fontsize=9, fontweight='bold')

    if ax == axes[0]:
        ax.legend(fontsize=9, loc='upper right')

plt.tight_layout()
plt.savefig(f"{OUT_DIR}/fig3_breakdown.png", dpi=150, bbox_inches='tight')
print("[3/4] Saved: fig3_breakdown.png")
plt.close()

# ═══════════════════════════════════════════════════════════════
# Fig 4: Line count vs Dyn/Sta ratio (scatter)
# ═══════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(7, 5))

line_counts = [831543, 157538, 25260, 7632, 196015]  # approximate n_lines per dataset
dataset_labels_sc = ['enwik8\n(831K)', 'Uniform\n(157K)', 'Varied\n(25K)', 'Extreme\n(7.6K)', 'Blocked\n(196K)']
point_colors = ['#4e79a7', '#59a14f', '#f28e2b', '#e15759', '#b07aa1']

for lc, ratio, lbl, col in zip(line_counts, dyn_sta_ratios, dataset_labels_sc, point_colors):
    ax.scatter(lc, ratio, s=140, color=col, zorder=5, edgecolors='white', linewidth=1.5)
    va = 'bottom' if ratio >= 1.0 else 'top'
    ax.annotate(f'{lbl}\n({ratio:.3f}x)', xy=(lc, ratio),
                xytext=(lc, ratio + (0.04 if ratio >= 1.0 else -0.04)),
                fontsize=8.5, ha='center', va=va, color=col)

ax.axhline(1.0, color='gray', linestyle='--', lw=1.5, label='Dyn = Sta (equal)')
ax.fill_between([0, max(line_counts)*1.1], [1,1], [0.8]*2, alpha=0.07, color='#59a14f', label='Dynamic faster zone')
ax.fill_between([0, max(line_counts)*1.1], [1,1], [2.5]*2, alpha=0.07, color='#e15759', label='Static faster zone')
ax.set_xscale('log')
ax.set_xlabel("Number of Lines (log scale)", fontsize=11)
ax.set_ylabel("Dyn/Sta Ratio  (< 1.0 = Dynamic faster)", fontsize=11)
ax.set_title("Line Count vs Dynamic/Static Performance Ratio\n(CPU preprocess cost grows with n_lines)", fontsize=12)
ax.legend(fontsize=9)
ax.set_xlim(3000, 2_000_000)
ax.set_ylim(0.85, 2.4)

plt.tight_layout()
plt.savefig(f"{OUT_DIR}/fig4_linecount_vs_ratio.png", dpi=150, bbox_inches='tight')
print("[4/4] Saved: fig4_linecount_vs_ratio.png")
plt.close()

print(f"\nAll figures saved to {OUT_DIR}/")
