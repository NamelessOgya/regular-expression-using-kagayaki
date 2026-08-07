# 実験詳細: Dynamic vs Static チャンク分割の性能比較

## 実験目的

Chunk-Parallel Dynamic が Chunk-Parallel Static より遅い原因を特定し、  
「どのようなデータ条件で Dynamic が有利になるか」を明らかにする。

仮説の詳細は [hypothesis.md](hypothesis.md) を参照。

---

## 実験 A: CPU 前処理時間の直接比較

### 概要

`CPU前処理(秒)` 列を抽出し、Static と Dynamic の内訳を比較する。

### 使用データ

| 項目 | 値 |
|---|---|
| データセット | `data/wiki_plain.txt` (enwik8) |
| テキストサイズ | 95,909,488 文字（全体） |
| 行数 | 約 83 万行 |
| 行長（平均 / 標準偏差） | 115.3 文字 / 406.9 |

### 確認コマンド

```bash
python3 - <<'EOF'
import csv, statistics

def show(path, label):
    pre_times, gpu_times, total_times = [], [], []
    with open(path) as f:
        for row in csv.DictReader(f):
            if int(row['文字数']) == 95909488:
                pre_times.append(float(row['CPU前処理(秒)']))
                gpu_times.append(float(row['GPU実行(秒)']))
                total_times.append(float(row['実行時間(秒)']))
    avg_pre = sum(pre_times)/len(pre_times)
    avg_gpu = sum(gpu_times)/len(gpu_times)
    avg_tot = sum(total_times)/len(total_times)
    print(f"{label}: CPU前処理={avg_pre:.6f}s  GPU実行={avg_gpu:.6f}s  合計={avg_tot:.6f}s")

show('results/run_20260807_09_30_15/gpu_chunk/avg.csv',         'Static ')
show('results/run_20260807_09_30_15/gpu_chunk_dynamic/avg.csv', 'Dynamic')
EOF
```

### 結果（3回平均）

| 手法 | CPU前処理 | GPU実行 | 合計 |
|---|---|---|---|
| Static | 19.8ms | 42.3ms | 63.5ms |
| Dynamic | 23.2ms | 46.5ms | 71.4ms |

**Dyn/Sta = 1.124x**（Static が速い）

---

## 実験 B: データセット別の性能比較

### 概要

行長のばらつきを意図的に変えた複数のデータセットで GPU 3 手法をベンチマーク。  
「行長均一 → Dynamic 不利」「行長ばらつき大 → Dynamic 有利」の逆転を検証。

### データセット（すべて wiki_plain.txt の実データから生成）

データ生成スクリプト: [`generate_experiment_data.py`](generate_experiment_data.py)

| データセット | ファイル | 行数 | 平均行長 | SD | 設計意図 |
|---|---|---|---|---|---|
| **均一** | `data/experiment/uniform.txt` | 157,538 | 41.9 文字 | 8.6 | 行長均一 → Dynamic の恩恵なし |
| **ばらつき大** | `data/experiment/varied.txt` | 25,260 | 395.9 文字 | 434.1 | 短行/長行を**交互**配置 |
| **極端ばらつき** | `data/experiment/varied_extreme.txt` | 7,632 | 1,311 文字 | 1,355.5 | 超短行/超長行を**交互**配置 |

### 実行コマンド

```bash
# データ生成（初回のみ）
python3 sprints/001/generate_experiment_data.py

# 各データセットで 3 回平均ベンチマーク
bash run_all.sh data/experiment/uniform.txt --runs 3
bash run_all.sh data/experiment/varied.txt --runs 3
bash run_all.sh data/experiment/varied_extreme.txt --runs 3
```

### 結果（3回平均、最大サイズ）

| データセット | GPU Line | Chunk Static | Chunk Dynamic | Dyn/Sta |
|---|---|---|---|---|
| uniform.txt | 11.3ms | 11.1ms | 11.7ms | 1.057x |
| varied.txt | 11.3ms | 14.3ms | 16.6ms | 1.162x |
| varied_extreme.txt | 11.3ms | 16.6ms | 18.8ms | 1.131x |

**仮説「ばらつき大 → Dynamic 有利」は確認できなかった。**

理由：短行と長行が**交互に分散**している場合、Static の連続行割り当て（LPC=8）でも
各チャンクに短行と長行が混在するため、文字数がほぼ自然に均等化される。

---

## 実験 C（補足）: LPC 値を変えた Dynamic の挙動

Dynamic の CPU 前処理コストは目標チャンク数（= `n_lines / LPC`）に依存する。
LPC を変えることで「前処理コスト vs 負荷分散メリット」のトレードオフを観察する。

```bash
./run_lpc_sweep.sh data/experiment/varied.txt \
  --out results/sprint001_lpc_varied \
  --lpc 1 2 4 8 16 32
```

---

## 実験 D: ブロック型データでの検証 【★仮説確認】

### 概要

実験 B の結果から「行長の空間的局在性（ブロック性）」が決め手と再仮説。  
**前半: 短行のみ / 後半: 長行のみ** という連続ブロック型データを生成し検証。

### データセット

| 項目 | 値 |
|---|---|
| ファイル | `data/experiment/blocked.txt` |
| 行数 | 196,015 行 |
| 前半（短行ブロック） | 189,593 行（平均 9.1 文字）|
| 後半（長行ブロック） | 6,422 行（平均 778.6 文字）|
| **標準偏差** | **146.2**（varied より低い！）|
| 合計文字数 | 6,720,710 文字 |

> [!IMPORTANT]
> SD=146 は varied(434) や extreme(1355) より**小さい**にもかかわらず、
> Dynamic が最も有利になった。→ **SD は有利性の指標ではない**

### データ生成

```python
# data/experiment/blocked.txt 生成
import random, os, statistics

WIKI_PATH = "data/wiki_plain.txt"
OUT_PATH  = "data/experiment/blocked.txt"
TARGET_CHARS = 10_000_000
SEED = 42
random.seed(SEED)

with open(WIKI_PATH, encoding='utf-8', errors='ignore') as f:
    all_lines = [line.rstrip('\n') for line in f]

short_pool = [l for l in all_lines if 1 <= len(l) <= 15]
long_pool  = [l for l in all_lines if len(l) >= 500]
random.shuffle(short_pool); random.shuffle(long_pool)

# 前半: 短行のみ、後半: 長行のみ（各 TARGET_CHARS/2 ずつ）
half = TARGET_CHARS // 2
short_block, total = [], 0
for l in short_pool:
    short_block.append(l); total += len(l)
    if total >= half: break
long_block, total = [], 0
for l in long_pool:
    long_block.append(l); total += len(l)
    if total >= half: break

os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
with open(OUT_PATH, 'w', encoding='utf-8') as f:
    for l in short_block + long_block:
        f.write(l + '\n')
```

### 実行コマンド

```bash
bash run_all.sh data/experiment/blocked.txt --runs 3
```

### 結果（3回平均、最大サイズ）

| 手法 | 合計(ms) | CPU前処理(ms) | GPU実行(ms) | Dyn/Sta比 |
|---|---|---|---|---|
| GPU Line | 12.89 | 1.46 | 11.41 | — |
| Chunk Static | 19.15 | 1.40 | 17.74 | 1.000 |
| **Chunk Dynamic** | **12.97** | 1.50 | 11.44 | **0.677x** |

**Dynamic が Static より 32% 速い。仮説確認。**

### メカニズム

| 手法 | 前半チャンク（短行） | 後半チャンク（長行） | 不均衡比 |
|---|---|---|---|
| Static (LPC=8) | 8行 × 9.1文字 ≈ **73 chars** | 8行 × 779文字 ≈ **6,229 chars** | **85倍** |
| Dynamic | 均等化 → **~274 chars/chunk** | 均等化 → **~274 chars/chunk** | **1倍** |

Static では前半チャンクが極端に軽く、後半チャンクが極端に重くなるため、
GPU ワープ内でスレッド完了タイミングが大きくずれる（ワープダイバージェンス）。
Dynamic の文字数均等化がこの不均衡を解消する。

---

## 評価指標

| 指標 | 説明 |
|---|---|
| `CPU前処理(秒)` | チャンク境界計算などの CPU 側処理時間 |
| `GPU実行(秒)` | カーネル起動 〜 `cudaDeviceSynchronize` までの時間 |
| `実行時間(秒)` | 総実行時間（CPU前処理 + GPU実行） |
| Dynamic/Static 比率 | `Dynamic実行時間 / Static実行時間`（< 1.0 で Dynamic 有利） |

---

## 結果の記録先

```
results/
├── run_20260807_09_30_15/       ← 実験 A: enwik8 (3回平均)
├── sprint001_redo_uniform/      ← 実験 B: 均一データ (3回平均)
├── run_20260807_11_01_47/       ← 実験 B: ばらつきデータ (3回平均)
├── sprint001_redo_extreme2/     ← 実験 B: 極端ばらつきデータ (3回平均)
├── sprint001_redo_blocked/      ← 実験 D: ブロック型データ (3回平均)
└── sprint001_lpc_varied/        ← 実験 C: LPC スイープ（ばらつきデータ）
```

実験結果の詳細は [results.md](results.md) を参照。  
グラフは [figures/](figures/) に保存済み（`python3 plot_results.py` で再生成可）。
