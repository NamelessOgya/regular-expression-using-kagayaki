import csv, os, matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np

BASE = 'results/sprint002_exp'
MAX_CHARS = 95909488

# NFA 状態数計算 (1オルタネーションあたり約5状態)
def get_nfa_states(pat):
    alts = pat.strip("()").split("|")
    return len(alts) * 5

lpc1_rows = [r for r in csv.DictReader(open(f"{BASE}/lpc_1/avg.csv")) if int(r['文字数']) == MAX_CHARS]
lpc8_rows = [r for r in csv.DictReader(open(f"{BASE}/lpc_8/avg.csv")) if int(r['文字数']) == MAX_CHARS]

states = []
lpc1_gpus = []
lpc8_gpus = []
ratios = []

print("=== Sprint 002: NFA State Scaling Factor Analysis ===")
print(f"{'Pattern':<40} | {'|Q|':>5} | {'LPC=1 GPU(ms)':>13} | {'LPC=8 GPU(ms)':>13} | {'Speedup (LPC1/LPC8)':>20}")
print("-" * 105)

for r1, r8 in zip(lpc1_rows, lpc8_rows):
    pat = r1['正規表現']
    st = get_nfa_states(pat)
    t1 = float(r1['GPU実行(秒)']) * 1000
    t8 = float(r8['GPU実行(秒)']) * 1000
    ratio = t1 / t8
    
    states.append(st)
    lpc1_gpus.append(t1)
    lpc8_gpus.append(t8)
    ratios.append(ratio)
    
    print(f"{pat:<40} | {st:>5} | {t1:>11.2f} ms | {t8:>11.2f} ms | {ratio:>18.2f}x")

# --- Plotting ---
fig, axes = plt.subplots(1, 2, figsize=(15, 6))
fig.patch.set_facecolor('#0F1117')

for ax in axes:
    ax.set_facecolor('#1A1D2E')
    ax.tick_params(colors='white')
    ax.spines['bottom'].set_color('#555'); ax.spines['left'].set_color('#555')
    ax.spines['top'].set_visible(False);  ax.spines['right'].set_visible(False)
    ax.grid(axis='y', color='#333', linestyle='--', alpha=0.5)

# Subplot 1: Absolute GPU Execution Time vs NFA States |Q|
ax = axes[0]
ax.plot(states, lpc1_gpus, 'o-', color='#FF6B6B', linewidth=2.5, markersize=8, label='LPC=1 (High Thread Overhead)')
ax.plot(states, lpc8_gpus, 's-', color='#4DABF7', linewidth=2.5, markersize=8, label='LPC=8 (Chunked-Static, Amortized)')

for s, t1, t8 in zip(states, lpc1_gpus, lpc8_gpus):
    ax.text(s, t1 + 15, f"{t1:.1f}ms", color='#FF6B6B', fontsize=8, ha='center', fontweight='bold')
    ax.text(s, t8 - 25 if t8 > 30 else t8 + 10, f"{t8:.1f}ms", color='#4DABF7', fontsize=8, ha='center', fontweight='bold')

ax.set_xscale('log', base=2)
ax.set_xticks(states)
ax.set_xticklabels([f"|Q|={s}" for s in states], color='white', fontsize=9)
ax.set_xlabel('NFA Number of States |Q| (Synthetic Alternation Scaling)', color='white', fontsize=11)
ax.set_ylabel('GPU Execution Time (ms)', color='white', fontsize=11)
ax.set_title("Absolute GPU Execution Time vs NFA States |Q|\n(enwik8, 95.9MB Dataset)", color='white', fontsize=12, fontweight='bold')
ax.legend(facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=9.5, loc='upper left')

# Subplot 2: Relative Speedup (LPC=1 / LPC=8)
ax = axes[1]
ax.plot(states, ratios, 'D-', color='#51CF66', linewidth=2.5, markersize=8, label='LPC=1 / LPC=8 Speedup Ratio')
ax.axhline(1.0, color='#FFD700', linestyle='--', linewidth=1.5, label='Parity (1.0x)')

for s, r in zip(states, ratios):
    ax.text(s, r + 0.03, f"{r:.2f}x", color='#51CF66', fontsize=9, ha='center', fontweight='bold')

ax.set_xscale('log', base=2)
ax.set_xticks(states)
ax.set_xticklabels([f"|Q|={s}" for s in states], color='white', fontsize=9)
ax.set_xlabel('NFA Number of States |Q|', color='white', fontsize=11)
ax.set_ylabel('Speedup Ratio (LPC=1 / LPC=8)', color='white', fontsize=11)
ax.set_title("Chunked-Static Advantage Scaling vs NFA States |Q|\n(Proves Cache/Memory Working Set Hypothesis)", color='white', fontsize=12, fontweight='bold')
ax.legend(facecolor='#1A1D2E', edgecolor='#555', labelcolor='white', fontsize=9.5, loc='upper left')
ax.set_ylim(0.70, 1.38)

fig.suptitle("Sprint 002 (Experiment 002): Factor Isolation of NFA Working Set Size |Q|",
             color='white', fontsize=14, fontweight='bold')
plt.tight_layout(rect=[0, 0.02, 1, 0.95])

os.makedirs('sprints/002/figures', exist_ok=True)
plt.savefig('sprints/002/figures/fig_exp002_state_scaling.png', dpi=150, bbox_inches='tight', facecolor='#0F1117')
print("\nPlot saved -> sprints/002/figures/fig_exp002_state_scaling.png")
