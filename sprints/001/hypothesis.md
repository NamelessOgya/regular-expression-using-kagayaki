# 仮説: Dynamic の遅さは CPU 前処理のボトルネックに起因する

## 仮説の概要

enwik8 のような**「文字数が短く均一な行」で構成されるデータセット**では、
Chunk-Parallel Dynamic の CPU 前処理（全行の文字数を走査してチャンク境界を動的に計算する処理）が
Static に対するオーバーヘッドとなり、Dynamic の総実行時間が Static を上回る。

## 仮説の根拠

### 1. enwik8 の行長分布の性質

enwik8（Wikipedia プレーンテキスト）は以下の特性を持つ:
- 総行数: 約 83 万行
- 各行は短く（数十〜100 バイト程度）均一

行長が均一であれば、**「行数ベース均等分割（Static）」≒「文字数ベース均等分割（Dynamic）」** となる。
つまり Dynamic の精密な分割が Static に対して実質的なアドバンテージをもたらさない。

### 2. Dynamic の CPU 前処理コストの増大

`nfa_gpu_chunk.cu` の実装を比較すると:

```
Static の前処理 (O(1)):
  n_chunks = (n_lines + LPC - 1) / LPC
  for c in range(n_chunks):
      chunk_ls[c] = c * LPC
      chunk_le[c] = min((c+1) * LPC, n_lines)

Dynamic の前処理 (O(n_lines)):
  total_chars = sum(h_len[i] for i in n_lines)   ← 全行スキャン
  target_chars = total_chars / n_chunks_target
  ← 累積文字数で境界を決定するループ
```

n_lines ≈ 83 万行という規模では、このループコストが無視できない。

### 3. GPU 実行部分は同一

両者は同一カーネル `gpu_chunk_match_kernel` を使用しており、GPU 実行時間の差は
チャンク分割の「均一性」から生じる。行が均一なら GPU 実行時間も同程度になる。

## 仮説の予測

| 条件 | 予測 |
|---|---|
| 行長が短く均一（enwik8 相当） | Dynamic ≈ Static（CPU 前処理の差が支配的） |
| 行長のばらつきが大きいデータ | Dynamic < Static（負荷分散の恩恵が前処理コストを上回る） |
| テキストサイズが小さい | Dynamic > Static（GPU 実行時間が短く、前処理比率が高まる） |

## 検証方法

### 実験 A: CPU 前処理時間の直接比較

ベンチマーク結果の `CPU前処理(秒)` 列を比較する。

```
期待される結果:
  Static の CPU 前処理時間 < Dynamic の CPU 前処理時間
  GPU 実行時間は両者でほぼ同等
```

### 実験 B: 人工データでの検証

行長のばらつきを変えた人工テキストを用意して比較する:

1. **均一データ**: 全行が同じ長さ（例: 50文字）
2. **ばらつきデータ**: 短行（5文字）と長行（500文字）が混在

Dynamic がばらつきデータで Static を逆転すれば、仮説が支持される。

## 仮説が正しい場合の含意

- Dynamic は「行長の分散が大きく」かつ「テキストが十分大きい」場合にのみ有効
- enwik8 のような均一データに対しては Static（あるいは Line-Parallel）の方が適切
- Dynamic の CPU 前処理を CUDA 上に移植（GPU-side preprocessing）することで改善できる可能性がある
