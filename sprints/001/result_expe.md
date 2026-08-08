# 実験 E 個別レポート: 行数スケール（GPU Wave数）に伴う手法間性能比較の検証

**日付**: 2026-08-08  
**対象データセット**: `dynamic-small` (25K行), `dynamic-medium` (500K行), `dynamic-large` (2,000K行)  
**実行環境**: Docker コンテナ内 (`re_exp_env_gpu`, NVIDIA CUDA 11.8 / RTX 5090)  
**計測条件**: 30 種の正規表現パターン × 3 回実行の平均値（均一行長 30〜60 文字, LPC = 8）  

---

## 1. 概要と実験目的

本実験（実験 E）では、テキスト全体の行数（データ規模）が増加した際に、**各手法の性能関係がどのように変化するか**を検証した。

GPU Line は 1 行 = 1 スレッドで処理するため、行数に比例して必要なスレッド数が増加する。GPU の最大同時実行スレッド数（RTX 5090 では 348,160 スレッド）を超えると、処理が複数ラウンド（**GPU Wave**）に分割される。

本実験の目的は、**この GPU Wave 数が増加した際に Chunked-Static / Chunked-Dynamic が GPU Line に対してどのように振る舞うか**を定量的に実証することである。

---

## 2. データセット仕様と GPU Wave 数

| データセット | 行数 ($n_{lines}$) | 合計文字数 | 行長仕様 | GPU Line の必要 Wave 数 | Chunked-Static の必要 Wave 数 |
|---|---|---|---|---|---|
| **dynamic-small** | 25,000 行 | 1.0 MB | 均一 (30〜60B) | **0.07 波** (1波以内) | 0.01 波 |
| **dynamic-medium** | 500,000 行 | 20.2 MB | 均一 (30〜60B) | **1.44 波** (2波に分割) | 0.18 波 |
| **dynamic-large** | 2,000,000 行 | 80.8 MB | 均一 (30〜60B) | **5.74 波** (6波に分割) | **0.72 波** (1波以内) |

> **GPU Wave 数の計算**: $n_{lines} \div 348,160 \text{ (RTX 5090 同時スレッド数)}$

---

## 3. 計測結果

### 3.1 合計時間および速度比比較 (2,000K行スケール全体計測)

| データセット | GPU Line (ms) | Chunked-Static (ms) | Chunked-Dynamic (ms) | Line/Sta 比 | Line/Dyn 比 | Dyn/Sta 比 | **最速手法** |
|---|---|---|---|---|---|---|---|
| **dynamic-small** | **10.3ms** | 11.6ms | 9.9ms | 0.888x ✅ | 1.040x | 0.853x | **GPU Line ≈ Dynamic** |
| **dynamic-medium** | 22.4ms | **20.7ms** | 22.5ms | **1.082x 🔴** | 0.996x | 1.087x | **Chunked-Static** |
| **dynamic-large** | **84.8ms** | 85.7ms | 87.6ms | 0.990x | 0.968x | 1.022x | **GPU Line** |

### 3.2 CPU 前処理 vs GPU 実行 内訳詳細 (2,000K行スケール)

| データセット | GPU Line Pre | **GPU Line GPU** | Static Pre | **Static GPU** | Dyn Pre | **Dyn GPU** |
|---|---|---|---|---|---|---|
| **dynamic-small** | 0.34ms | 9.96ms | 0.30ms | 11.30ms | 0.34ms | **9.56ms** |
| **dynamic-medium** | 2.53ms | 19.87ms | 2.58ms | **18.12ms** | 2.97ms | 19.53ms |
| **dynamic-large** | 37.50ms | **47.30ms** | 36.80ms | 48.90ms | 38.20ms | 49.40ms |

---

## 4. 視覚化グラフ

### 図1: データセット規模別 実行時間比較
![fig5_linecount_scaling](figures/fig5_linecount_scaling.png)

### 図2: GPU Line Wave 数 vs 性能逆転レシオ
![fig6_gpu_line_waves](figures/fig6_gpu_line_waves.png)

---

## 5. 詳細考察

### 5.1 行数スケールに伴う CPU 前処理時間の膨張
* 行数が 200 万行に達すると、全行のオフセット配列の確保や走査にかかる CPU 前処理時間が **約 37ms**（全体実行時間の 44%）まで大きく膨れ上がる。
* チャンク化手法（Static/Dynamic）であっても、全行からのチャンク境界構築処理で全行走査が必要なため、前処理時間の短縮には至らない。

### 5.2 均一短行データにおける GPU Line の堅牢性
* `dynamic-large` のように 1 行が 30〜60 文字と短行である場合、GPU Line が 5.74 波に分割されても 1 波あたりの実行時間は極めて短時間で終了する。
* したがって、スレッド交替に伴うオーバーヘッドは限定的であり、GPU Line (84.8ms) と Chunked-Static (85.7ms) はほぼ拮抗し、全時間では GPU Line が最速を維持する。

---

## 6. 結論

1. **短行大規模データでの挙動**: 1 行が短いテキストでは、行数が 200 万行規模へ拡大しても GPU Line の完全並列度が強固であり、合計パフォーマンスで Chunked-Static が上回ることは困難である。
2. **CPU 前処理の課題**: 大規模行数において前処理時間（約 37ms）が全体のボトルネックとなるため、前処理の GPU 化（Prefix Sum 並列化など）が今後の不可欠な改善課題となる。
