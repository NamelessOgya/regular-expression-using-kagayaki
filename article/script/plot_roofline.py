#!/usr/bin/env python3
"""
article/script/plot_roofline.py
Visual performance model (Roofline Model) generation script with dummy benchmark points.
"""
import os
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# 出力先ディレクトリ
os.makedirs("article/figures", exist_ok=True)
OUT_PATH = "article/figures/roofline_concept.png"

# ハードウェアパラメータ (NVIDIA RTX 5090 Blackwell 相当)
PEAK_COMPUTE = 100.0    # Peak Compute: 100 TFLOPS / TIPS
PEAK_BANDWIDTH = 1.792  # Peak Bandwidth: 1.792 TB/s (1,792 GB/s)

# 屈曲点 (Knee Point / Ridge Point)
I_KNEE = PEAK_COMPUTE / PEAK_BANDWIDTH  # ~55.8 Ops/Byte

# 演算強度のレンジ (横軸: 0.1 ~ 1000 Ops/Byte)
intensity = np.logspace(-1, 3, 500)

# Roofline 計算
performance_roof = np.minimum(PEAK_COMPUTE, PEAK_BANDWIDTH * intensity)

# --- プロット描画 ---
plt.rcParams['font.sans-serif'] = ['DejaVu Sans', 'Arial', 'Helvetica']
fig, ax = plt.subplots(figsize=(11, 7), dpi=300)
fig.patch.set_facecolor('#FFFFFF')
ax.set_facecolor('#FAFAFC')

# 1. 背景の領域色分け
ax.axvspan(0.1, I_KNEE, color='#EBF5FB', alpha=0.75, zorder=1)
ax.axvspan(I_KNEE, 1000, color='#FEF9E7', alpha=0.75, zorder=1)

# 2. Roofline（屋根）の描画
intensity_mem = intensity[intensity <= I_KNEE]
ax.plot(intensity_mem, PEAK_BANDWIDTH * intensity_mem, color='#1F618D', linewidth=3.5,
        label=f'Memory Bandwidth Ceiling (Slope = {PEAK_BANDWIDTH} TB/s)', zorder=4)

intensity_comp = intensity[intensity >= I_KNEE]
ax.plot(intensity_comp, np.full_like(intensity_comp, PEAK_COMPUTE), color='#BA4A00', linewidth=3.5,
        label=f'Peak Compute Ceiling ({PEAK_COMPUTE} TFLOPS / TIPS)', zorder=4)

# 3. 屈曲点 (Knee Point) の強調
ax.plot(I_KNEE, PEAK_COMPUTE, 'o', color='#C0392B', markersize=10, zorder=5)
ax.axvline(I_KNEE, color='#C0392B', linestyle='--', linewidth=1.5, alpha=0.7, zorder=2)
ax.text(I_KNEE * 1.15, PEAK_COMPUTE * 0.72,
        f'Knee Point (Ridge Point)\nI_knee = {I_KNEE:.1f} Ops/Byte\n(Boundary between Memory & Compute)',
        fontsize=9.5, fontweight='bold', color='#922B21',
        bbox=dict(boxstyle='round,pad=0.5', facecolor='#FDEDEC', edgecolor='#C0392B', alpha=0.9),
        zorder=5)

# 4. ダミーデータ点（実測点）のプロット
# 点 A: メモリ律速 (単純コピー / ベクトル加算)
pt_A_x, pt_A_y = 1.0, 1.6
ax.plot(pt_A_x, pt_A_y, 'o', color='#2E86C1', markersize=10, zorder=6)
ax.text(pt_A_x * 0.9, pt_A_y * 0.45,
        'Point A: Vector Add / Copy\n(Memory-bound, near bandwidth limit)',
        fontsize=8.5, color='#1B4F72', fontweight='bold', ha='center',
        bbox=dict(boxstyle='square,pad=0.3', facecolor='white', edgecolor='#AED6F1', alpha=0.9),
        zorder=6)

# 点 B1: 最適化前 (キャッシュミスが多い)
pt_B1_x, pt_B1_y = 20.0, 4.0
ax.plot(pt_B1_x, pt_B1_y, 's', color='#7F8C8D', markersize=9, zorder=6)
ax.text(pt_B1_x * 0.45, pt_B1_y * 0.85,
        'Point B1: Unoptimized (e.g. Line-Parallel)\nCold cache, thread creation overhead',
        fontsize=8.5, color='#424949', ha='right',
        bbox=dict(boxstyle='square,pad=0.3', facecolor='white', edgecolor='#BDC3C7', alpha=0.9),
        zorder=6)

# 点 B2: 最適化後 (Chunk化による時間的局所性の向上)
pt_B2_x, pt_B2_y = 20.0, 28.0
ax.plot(pt_B2_x, pt_B2_y, '^', color='#27AE60', markersize=11, zorder=6)
ax.text(pt_B2_x * 0.75, pt_B2_y * 1.15,
        'Point B2: Optimized (Chunked-Static)\nTemporal Locality (Cache Warmth) lifts speed!',
        fontsize=8.5, color='#1E8449', fontweight='bold', ha='right',
        bbox=dict(boxstyle='round,pad=0.3', facecolor='#E8F8F5', edgecolor='#27AE60', alpha=0.9),
        zorder=6)

# 最適化矢印 (B1 -> B2)
ax.annotate('', xy=(pt_B2_x, pt_B2_y * 0.9), xytext=(pt_B1_x, pt_B1_y * 1.25),
            arrowprops=dict(facecolor='#27AE60', edgecolor='#27AE60', width=2.5, headwidth=8),
            zorder=5)

# 点 C: 演算律速 (多分岐正規表現、GEMM行列積)
pt_C_x, pt_C_y = 200.0, 85.0
ax.plot(pt_C_x, pt_C_y, 'D', color='#8E44AD', markersize=10, zorder=6)
ax.text(pt_C_x * 1.15, pt_C_y * 0.8,
        'Point C: Multi-branch Regex / GEMM\n(Compute-bound, near Peak Compute)',
        fontsize=8.5, color='#512E5F', fontweight='bold',
        bbox=dict(boxstyle='square,pad=0.3', facecolor='white', edgecolor='#D2B4DE', alpha=0.9),
        zorder=6)

# 5. 領域注釈
ax.text(0.5, 45,
        'MEMORY-BOUND REGION\n- Bottleneck: DRAM Bandwidth\n- More cores will NOT speed up\n- Remedy: Reduce memory traffic / cache',
        fontsize=9, color='#1B4F72', fontweight='bold',
        bbox=dict(boxstyle='round,pad=0.5', facecolor='#D4E6F1', edgecolor='#2980B9', alpha=0.85),
        zorder=3)

ax.text(120, 20,
        'COMPUTE-BOUND REGION\n- Bottleneck: Arithmetic Units / Clock\n- Bandwidth has plenty of headroom\n- Remedy: SIMD, FMA, ILP parallelism',
        fontsize=9, color='#7D6608', fontweight='bold',
        bbox=dict(boxstyle='round,pad=0.5', facecolor='#FCF3CF', edgecolor='#F39C12', alpha=0.85),
        zorder=3)

# 軸と目盛り (両対数)
ax.set_xscale('log')
ax.set_yscale('log')
ax.set_xlim(0.1, 1000)
ax.set_ylim(0.2, 180)

ax.set_xlabel('Operational Intensity  I  [Ops / Byte]  (Algorithm Characteristic)', fontsize=11, fontweight='bold', labelpad=8)
ax.set_ylabel('Attainable Performance  P  [TFLOPS / TIPS]  (Speed)', fontsize=11, fontweight='bold', labelpad=8)
ax.set_title('Visual Anatomy of the Roofline Model', fontsize=14, fontweight='bold', pad=15)

ax.grid(True, which='both', color='#D5D8DC', linestyle='--', linewidth=0.6, alpha=0.7)
ax.legend(loc='lower right', fontsize=9.5, framealpha=0.95, edgecolor='#BDC3C7')

plt.tight_layout()
plt.savefig(OUT_PATH, dpi=300, bbox_inches='tight')
print(f"Successfully generated: {OUT_PATH}")
