# Sprint 001: なぜ Chunk-Parallel Dynamic は Static より遅いのか

## リサーチテーマ

Chunk-Parallel Dynamic は Static よりも負荷分散の精度が高い設計であるにもかかわらず、
`results/latest` のベンチマーク結果では Dynamic の方が Static より遅い傾向が観察された。
本スプリントではその原因を特定する。

## 観測された事実

`results/latest`（enwik8, 95,909,488文字, 3回平均）において:

| 手法 | 平均実行時間(秒) |
|---|---|
| GPU Line-Parallel | 0.0640 |
| GPU Chunk-Parallel Static | 0.0635 |
| **GPU Chunk-Parallel Dynamic** | **0.0714** |

- Static は Line とほぼ同等
- Dynamic は Static より約 **12% 遅い**
- Dynamic の CPU 前処理時間が相対的に長い傾向がある

## Dynamic と Static の実装上の違い

両者は同一の CUDA カーネル `gpu_chunk_match_kernel` を使用しており、
GPU 実行部分のロジックは同一である。

唯一の違いは **CPU 側のチャンク分割ロジック**（`nfa_gpu_chunk.cu`）:

| | Static | Dynamic |
|---|---|---|
| 分割方針 | 行数ベースで均等分割 (`行数 ÷ LPC`) | 文字数ベースで均等分割 |
| CPU 前処理 | 単純な整数除算のみ | 全行をスキャンして累積文字数を計算 |
| 計算量 | O(1) | O(n_lines) |

## リサーチクエスチョン

1. **Dynamic の遅さは CPU 前処理（チャンク境界計算）のコストに起因するのか？**
2. enwik8 のような「行が短く・均一」なデータでは Dynamic の恩恵（負荷分散）が発揮されないのか？
3. 行長のばらつきが大きいデータでは Dynamic が Static を逆転するか？

## 調査方針

1. CPU 前処理時間と GPU 実行時間を Static / Dynamic で定量比較する
2. 人工的に行長ばらつきを変えたデータセットで実験し、Dynamic の優位性が生じる条件を探る
3. enwik8 の行長分布を可視化する

## 関連ファイル

- 実装: [`src/gpu/chunk_parallel/nfa_gpu_chunk.cu`](../../src/gpu/chunk_parallel/nfa_gpu_chunk.cu)
- ベンチマーク結果: `results/latest/`
- 仮説: [`hypothesis.md`](hypothesis.md)
