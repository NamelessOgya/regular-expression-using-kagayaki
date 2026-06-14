# アイデア: 文字数ベースの動的チャンク分割（Chunk-Parallel 改善案）

## 背景・問題意識

現在の `gpu_chunk_parallel` 実装（[`src/gpu/chunk_parallel/nfa_gpu_chunk.cu`](file:///home/ubuntu/regular-expression-using-kagayaki/src/gpu/chunk_parallel/nfa_gpu_chunk.cu)）では、チャンクの分割が以下のように**行番号順に LINES_PER_CHUNK 行ずつ機械的に切り分ける**方式です。

```c
// 現在の実装（固定N行分割）
for (int c = 0; c < n_chunks; c++) {
    h_chunk_ls[c] = c * LINES_PER_CHUNK;
    h_chunk_le[c] = std::min((c + 1) * LINES_PER_CHUNK, n_lines);
}
```

この方式では、各チャンクの**合計文字数（＝処理量）が均等になる保証がない**。
行長のばらつきが大きいデータセットの場合、一部のスレッドが他のスレッドよりも大幅に重い仕事を担うことになり、
`cudaDeviceSynchronize()` で全スレッドの完了を待つため、軽いスレッドが長時間 Idle になる。

---

## 提案: 文字数ベースの動的チャンク分割

### アルゴリズムの概要

1. 全行の文字数の合計 `total_chars` を求める
2. スレッド（チャンク）数 `n_chunks` を決定する（現在はスレッド数から逆算）
3. 目標とする1チャンクあたりの文字数 `target_chars_per_chunk = total_chars / n_chunks` を計算する
4. 行を先頭から順番にスキャンし、累積文字数が `target_chars_per_chunk` を超えた時点でチャンクを区切る

```
例: 8行、target = 15 文字/チャンク

Line 1: 12文字  累積=12  < 15 → Chunk 0 に追加
Line 2:  4文字  累積=16  ≥ 15 → Chunk 0 を閉じ、Chunk 1 を開始
Line 3: 10文字  累積=10  < 15 → Chunk 1 に追加
Line 4:  2文字  累積=12  < 15 → Chunk 1 に追加
Line 5:  8文字  累積=20  ≥ 15 → Chunk 1 を閉じ、Chunk 2 を開始
...
```

---

## 実装方針

### 変更対象ファイル

#### [MODIFY] [`src/gpu/chunk_parallel/nfa_gpu_chunk.cu`](file:///home/ubuntu/regular-expression-using-kagayaki/src/gpu/chunk_parallel/nfa_gpu_chunk.cu)

ホスト側の `gpu_chunk_parallel()` 関数内にある「チャンク分割」部分（L118〜124）を以下のように置き換える。

```cpp
// --- 提案: 文字数ベースの動的チャンク分割 ---

// 1. 全行の合計文字数を計算
long total_chars = 0;
for (int i = 0; i < n_lines; i++) {
    total_chars += h_len[i];
}

// 2. チャンク数は LINES_PER_CHUNK を使わず、固定スレッド数から決定
//    （例: GPU の SM 数 × warp サイズ などに基づいて設定可能）
//    ここでは簡単のため行数 / LINES_PER_CHUNK と同じスレッド数を目標とする
int n_chunks_target = (n_lines + LINES_PER_CHUNK - 1) / LINES_PER_CHUNK;
long target_chars   = (total_chars + n_chunks_target - 1) / n_chunks_target;

// 3. 文字数の累積でチャンクを動的に区切る
std::vector<int> h_chunk_ls, h_chunk_le;
int chunk_start    = 0;
long running_chars = 0;

for (int i = 0; i < n_lines; i++) {
    running_chars += h_len[i];
    bool is_last = (i == n_lines - 1);

    if (running_chars >= target_chars || is_last) {
        h_chunk_ls.push_back(chunk_start);
        h_chunk_le.push_back(i + 1);  // exclusive
        chunk_start    = i + 1;
        running_chars  = 0;
    }
}

int n_chunks = (int)h_chunk_ls.size();
```

### カーネル側の変更

カーネル (`gpu_chunk_match_kernel`) 自体は変更不要。  
すでに `d_chunk_line_start[tid]` と `d_chunk_line_end[tid]` を受け取る汎用的な設計になっているため、チャンク数と配列の内容を変えるだけで動作する。

---

## コンパイルフラグ / 切り替え方法

新しい分割方式を既存の固定N行方式と共存・切り替え可能にするため、コンパイルフラグで制御する案：

```c
// -DCHUNK_DYNAMIC で動的分割を有効化
#ifndef CHUNK_DYNAMIC
#define CHUNK_DYNAMIC 0
#endif
```

または、関数名を分けて別バイナリとして計測する方法でもよい（sweep スクリプトで対応しやすい）。

---

## 期待される効果とデメリット

| 項目 | 固定N行分割（現在） | 文字数ベース動的分割（提案） |
|---|---|---|
| **分割の均一性** | 行長バラつきがあると不均等 | 各チャンクの処理量がほぼ均等 |
| **実装の複雑さ** | シンプル | 前処理（文字数集計）が必要 |
| **前処理コスト** | なし | CPU 側で O(N) の追加スキャンが必要 |
| **Idle 時間** | 行長のバラつきに依存 | 最小化される（理論上） |
| **Wikipedia への効果** | 行が短く均一なため差は小さい | 大きな改善は期待しにくい |
| **長行混在データへの効果** | 大幅な不均衡が発生しやすい | 大きな改善が期待できる |

---

## 実験計画（実装後）

1. `run_lpc_sweep.sh` または専用の `run_sweep_gpu.sh` に `--dynamic-chunk` フラグを追加
2. 固定N行分割 vs 文字数ベース分割を同一データで比較計測
3. Wikipediaのような「均一な短行」データと、意図的に長さをばらつかせたダミーデータの両方で比較
4. グラフ: 横軸 = 入力サイズ、縦軸 = 実行時間、系列 = 固定 / 動的

---

## 関連ファイル

- 現在の実装: [`src/gpu/chunk_parallel/nfa_gpu_chunk.cu`](file:///home/ubuntu/regular-expression-using-kagayaki/src/gpu/chunk_parallel/nfa_gpu_chunk.cu#L118-L124)
- ベンチマーク実行: [`app/run_benchmark.c`](file:///home/ubuntu/regular-expression-using-kagayaki/app/run_benchmark.c)
- スイープスクリプト: [`run_lpc_sweep.sh`](file:///home/ubuntu/regular-expression-using-kagayaki/run_lpc_sweep.sh)
