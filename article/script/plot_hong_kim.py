#!/usr/bin/env python3
"""
article/script/plot_hong_kim.py
Hong & Kim GPU Performance Model: Visualizing Latency Hiding and Warp Parallelism.
"""
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as patches

os.makedirs("article/figures", exist_ok=True)
OUT_PATH = "article/figures/hong_kim_concept.png"

fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 7), dpi=300)
fig.patch.set_facecolor('#FFFFFF')

def draw_timeline(ax, title, warps_data, show_idle=False):
    ax.set_facecolor('#FAFAFC')
    ax.set_title(title, fontsize=12, fontweight='bold', pad=10, loc='left')
    
    y_labels = []
    y_pos = []
    
    for idx, (warp_name, segments) in enumerate(warps_data):
        y = len(warps_data) - 1 - idx
        y_labels.append(warp_name)
        y_pos.append(y)
        
        for (start, duration, seg_type) in segments:
            if seg_type == 'comp':
                color = '#27AE60' # Compute (Active)
                edge = '#1E8449'
                label = 'Computation'
            elif seg_type == 'mem':
                color = '#F39C12' # Memory Access Wait
                edge = '#D68910'
                label = 'Memory Wait'
            else: # idle
                color = '#BDC3C7' # Stalled
                edge = '#95A5A6'
                label = 'SM Idle (Stalled)'
                
            rect = patches.Rectangle((start, y - 0.3), duration, 0.6,
                                     linewidth=1.2, edgecolor=edge, facecolor=color, alpha=0.9)
            ax.add_patch(rect)
            
    ax.set_yticks(y_pos)
    ax.set_yticklabels(y_labels, fontsize=10, fontweight='bold')
    ax.set_xlim(0, 100)
    ax.set_ylim(-0.6, len(warps_data) - 0.4)
    ax.set_xlabel('Time (Execution Cycles)', fontsize=10.5, fontweight='bold')
    ax.grid(axis='x', linestyle='--', alpha=0.5, color='#BDC3C7')

# ケース 1: ワープ不足 (N_warps < CWP) -> レイテンシ隠蔽失敗、ストール発生
# CWP = 4 だが、ワープが 2 本しかない場合
warps_case1 = [
    ('Warp 0', [(0, 10, 'comp'), (10, 30, 'mem'), (40, 10, 'comp'), (50, 30, 'mem')]),
    ('Warp 1', [(10, 10, 'comp'), (20, 30, 'mem'), (50, 10, 'comp'), (60, 30, 'mem')]),
]
draw_timeline(ax1, 'Case 1: Insufficient Warps (N_warps < CWP) -> Latency Hiding FAILS\nMemory wait latency is EXPOSED; SM stalls and wastes execution cycles.', warps_case1)

# アノテーション (Idle の明示)
ax1.annotate('SM STALLED (No active warps ready to compute)\nExposed Memory Latency!',
             xy=(25, -0.1), xytext=(22, 1.3),
             arrowprops=dict(facecolor='#C0392B', edgecolor='#C0392B', width=2, headwidth=7),
             fontsize=9.5, fontweight='bold', color='#C0392B',
             bbox=dict(boxstyle='round,pad=0.4', facecolor='#FDEDEC', edgecolor='#C0392B'))

# ケース 2: ワープ十分 (N_warps >= CWP) -> レイテンシ隠蔽成功！
# ワープが 4 本あり、常にどれかのワープが計算している
warps_case2 = [
    ('Warp 0', [(0, 10, 'comp'), (10, 30, 'mem'), (40, 10, 'comp'), (50, 30, 'mem')]),
    ('Warp 1', [(10, 10, 'comp'), (20, 30, 'mem'), (50, 10, 'comp'), (60, 30, 'mem')]),
    ('Warp 2', [(20, 10, 'comp'), (30, 30, 'mem'), (60, 10, 'comp'), (70, 30, 'mem')]),
    ('Warp 3', [(30, 10, 'comp'), (40, 30, 'mem'), (70, 10, 'comp'), (80, 30, 'mem')]),
]
draw_timeline(ax2, 'Case 2: Sufficient Warps (N_warps >= CWP) -> Latency Hiding SUCCEEDS!\nWhile Warps 0-2 wait for memory, Warp 3 computes. Zero idle time on compute units.', warps_case2)

# 凡例
legend_elements = [
    patches.Patch(facecolor='#27AE60', edgecolor='#1E8449', label='Computation (ALU/FPU active)'),
    patches.Patch(facecolor='#F39C12', edgecolor='#D68910', label='Memory Access Wait (DRAM latency)'),
]
fig.legend(handles=legend_elements, loc='upper right', bbox_to_anchor=(0.95, 0.98),
           fontsize=9.5, framealpha=0.95, edgecolor='#BDC3C7')

plt.tight_layout(rect=[0, 0, 1, 0.96])
plt.savefig(OUT_PATH, dpi=300, bbox_inches='tight')
print(f"Generated: {OUT_PATH}")
