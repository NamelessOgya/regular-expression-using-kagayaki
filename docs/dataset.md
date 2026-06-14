# 実験データの詳細

本プロジェクトのベンチマーク実験で使用したデータセットと前処理手順について説明します。

---

## 1. 使用データセット

### データセット名: enwik8（Wikipedia 英語版 ダンプ抜粋）

| 項目 | 内容 |
|---|---|
| **ソース** | [Matt Mahoney's Large Text Compression Benchmark](http://mattmahoney.net/dc/text.html) |
| **ダウンロード元** | `http://mattmahoney.net/dc/enwik8.zip` |
| **形式** | Wikipedia の XML ダンプデータ（UTF-8） |
| **元ファイルサイズ** | 約 100 MB（enwik8 = 10^8 bytes = 100,000,000 bytes） |
| **zip 圧縮サイズ** | 約 36 MB |
| **内容** | Wikipedia 英語版の先頭 100MB 分の記事本文（XML マークアップを含む） |

---

## 2. 前処理手順

前処理は [`setup_dataset.sh`](file:///home/ubuntu/regular-expression-using-kagayaki/setup_dataset.sh) から [`scripts/clean_wiki.py`](file:///home/ubuntu/regular-expression-using-kagayaki/scripts/clean_wiki.py) を呼び出す形で実行されます。

### ステップ 1: ダウンロード
```bash
curl -sS -o enwik8.zip http://mattmahoney.net/dc/enwik8.zip
```

### ステップ 2: 解凍
```python
import zipfile
zipfile.ZipFile('enwik8.zip').extractall('temp_dataset/')
```

### ステップ 3: XML タグの除去とクリーニング（`clean_wiki.py`）

以下の処理を1行ずつ適用します。

```python
tag_re = re.compile(r'<[^>]+>')   # XMLタグにマッチする正規表現

for line in infile:
    clean_line = tag_re.sub('', line)   # XMLタグを除去
    clean_line = clean_line.strip()     # 前後の空白・改行を除去
    if clean_line:                      # 空行を除外
        outfile.write(clean_line + '\n')
```

| 処理 | 詳細 |
|---|---|
| **XML タグ除去** | `<page>`, `<title>`, `<text>` 等すべての XML タグを空文字に置換 |
| **strip** | 行頭・行末の空白文字（スペース、タブ、改行）を除去 |
| **空行除外** | クリーニング後に内容が空になった行は出力しない |

### ステップ 4: 一時ファイルの削除
処理完了後、ダウンロードした `enwik8.zip` および中間ファイルは自動的に削除されます。

### 出力ファイル
```
data/wiki_plain.txt   ← ベンチマーク実験で使用するテキストデータ
```

---

## 3. 前処理後のデータ統計

以下は `data/wiki_plain.txt` の統計情報です。

| 項目 | 値 |
|---|---|
| **総行数** | 837,111 行 |
| **総文字数** | 95,072,377 文字（約 9,500 万文字） |
| **総ファイルサイズ** | 96,287,636 bytes（約 96 MB） |
| **最短行長** | 1 文字 |
| **最長行長** | 4,173 文字 |
| **平均行長** | 113.6 文字 |

### 行長の分布

| 行長の範囲 | 行数 | 割合 |
|---|---|---|
| 1 文字以下 | 2,816 行 | 0.3% |
| 2〜10 文字 | 96,686 行 | 11.5% |
| 11〜100 文字 | 536,453 行 | 64.1% |
| 101〜500 文字 | 149,280 行 | 17.8% |
| 501〜1,000 文字 | 43,334 行 | 5.2% |
| 1,001 文字以上 | 8,542 行 | 1.0% |

> [!NOTE]
> 全行の **75.6%（64.1% + 11.5%）が 100 文字以下**の短い行で構成されています。
> この特性が、Line-Parallel（1スレッド = 1行）が Chunk-Parallel よりも高速になる主要因です。
> 詳細は [gpu_parallelism.md](file:///home/ubuntu/regular-expression-using-kagayaki/docs/gpu_parallelism.md) を参照してください。

---

## 4. ベンチマーク入力サイズの設定

実験では、データセット全体を一度に使うのではなく、**文字数（UTF-8）を基準とした複数のサイズのサブセット**を切り出して各正規表現に対してベンチマークを実施しています。

サイズは 10 倍刻みで設定されます（[`run_sweep.sh`](file:///home/ubuntu/regular-expression-using-kagayaki/run_sweep.sh#L47-L54) 参照）：

| サブセット | 文字数 | 全体に対する割合 |
|---|---|---|
| サイズ 1 | 100 文字 | 〜0.0001% |
| サイズ 2 | 1,000 文字 | 〜0.001% |
| サイズ 3 | 10,000 文字 | 〜0.011% |
| サイズ 4 | 100,000 文字 | 〜0.11% |
| サイズ 5 | 1,000,000 文字 | 〜1.1% |
| サイズ 6 | 10,000,000 文字 | 〜10.5% |
| サイズ 7 | 約 95,072,377 文字（全体） | 100% |

サブセットはファイル先頭から文字数をカウントして切り出します（[`run_benchmark.c` L89-L105](file:///home/ubuntu/regular-expression-using-kagayaki/app/run_benchmark.c#L89-L105) 参照）。

---

## 5. ベンチマーク正規表現パターン

[`data/test_cases.csv`](file:///home/ubuntu/regular-expression-using-kagayaki/data/test_cases.csv) に定義された 30 パターンを使用します。

| カテゴリ | パターン例 | 意図 |
|---|---|---|
| **単純リテラル** | `the`, `Wikipedia`, `http` | 頻出単語・URL プレフィックス |
| **量化子** | `a*b`, `go*gle`, `.+ing`, `.+ly` | `*`（0回以上）、`+`（1回以上）の組み合わせ |
| **選択** | `cat\|dog`, `(the\|and)`, `(one\|two\|three\|four\|five)` | 単純な OR マッチ |
| **複合パターン** | `the .+`, `.+ of .+`, `http.+wiki` | 前後の文脈を含む複合表現 |
| **スケーラビリティ検証** | `(the\|and)` → `(the\|and\|...\|can)` まで段階的に OR を増やす系列 | 選択肢の数が NFA の状態数・実行時間に与える影響を検証 |

---

## 6. 再現手順

```bash
# 1. データセットのダウンロードと前処理
./setup_dataset.sh

# 2. ベンチマーク実行（CPU + GPU + LPC スイープ）
./run_all.sh

# 3. グラフ確認
ls results/latest/plots/
```
