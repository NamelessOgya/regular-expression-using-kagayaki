# 実験詳細: Dynamic vs Static チャンク分割の性能比較

## 実験目的

Chunk-Parallel Dynamic が Chunk-Parallel Static より遅い原因を特定する。  
仮説: **CPU 前処理のボトルネック**（詳細は [hypothesis.md](hypothesis.md) を参照）

---

## 実験 A: CPU 前処理時間の直接比較

### 概要

既存の `results/latest/` の結果から `CPU前処理(秒)` 列を抽出し、
Static と Dynamic の内訳を比較する。

### 期待する結果

```
GPU 実行時間: Static ≈ Dynamic（同一カーネルを使用）
CPU 前処理時間: Dynamic > Static（O(n_lines) のスキャンが余分）
```

### 使用データ

| 項目 | 値 |
|---|---|
| データセット | `data/wiki_plain.txt` (enwik8) |
| テキストサイズ | 95,909,488 文字（全体） |
| 行数 | 約 83 万行 |
| 行長（平均 / 標準偏差） | 115.3 文字 / 406.9 |

### 結果の確認方法

```bash
# avg.csv の CPU前処理(秒) / GPU実行(秒) を確認
python3 - <<'EOF'
import csv

def show(path, label):
    pre_times, gpu_times = [], []
    with open(path) as f:
        for row in csv.DictReader(f):
            if int(row['文字数']) == 95909488:
                pre_times.append(float(row['CPU前処理(秒)']))
                gpu_times.append(float(row['GPU実行(秒)']))
    print(f"{label}: CPU前処理={sum(pre_times)/len(pre_times):.6f}s  GPU実行={sum(gpu_times)/len(gpu_times):.6f}s")

show('results/latest/gpu_chunk/avg.csv',         'Static ')
show('results/latest/gpu_chunk_dynamic/avg.csv', 'Dynamic')
EOF
```

---

## 実験 B: データセット別の性能比較

### 概要

行長のばらつきを意図的に変えた2種類のデータセットで GPU 3 手法をベンチマークし、
「行長均一 → Dynamic 不利」「行長ばらつき大 → Dynamic 有利」の逆転を確認する。

### データセット

データ生成スクリプト: [`generate_experiment_data.py`](generate_experiment_data.py)

| データセット | ファイル | 行数 | 平均行長 | 標準偏差 | 設計意図 |
|---|---|---|---|---|---|
| **均一** | `data/experiment/uniform.txt` | 157,538 行 | 41.9 文字 | 8.6 | Static ≈ Dynamic（仮説の「恩恵なし」条件） |
| **ばらつき大** | `data/experiment/varied.txt` | 25,260 行 | 395.9 文字 | 434.1 | Dynamic < Static（短行と長行を交互配置） |

> **注**: いずれも `wiki_plain.txt` の実際の行を使用し、文字の分布・種類を保持している。

### 実行コマンド

```bash
# データ生成（初回のみ）
python3 sprints/001/generate_experiment_data.py

# 均一データでスイープ
./run_sweep_gpu.sh data/experiment/uniform.txt \
  --out results/sprint001_uniform

# ばらつきデータでスイープ
./run_sweep_gpu.sh data/experiment/varied.txt \
  --out results/sprint001_varied
```

### 期待する結果

| データセット | 仮説の予測 | 根拠 |
|---|---|---|
| **uniform.txt** | Dynamic ≈ Static | 行長が均一 → 文字数ベースと行数ベースの分割結果がほぼ同一。Dynamic の CPU 前処理コストだけが余分 |
| **varied.txt** | Dynamic < Static | 行長が不均一 → Static は長行の偏りで一部スレッドがボトルネック。Dynamic は文字数で均等分割できる |

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
├── sprint001_uniform/         ← 実験 B: 均一データ
├── sprint001_varied/          ← 実験 B: ばらつきデータ
└── sprint001_lpc_varied/      ← 実験 C: LPC スイープ（ばらつきデータ）
```

実験完了後、結果を [results.md](results.md) に記録する。
