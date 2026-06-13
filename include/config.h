/* config.h */
#pragma once

// ここでは、プログラム全体で使う「設定値（定数）」を決めています。
// 例えば、読み込む文字の最大数などをあらかじめ決めておくことで、メモリ（作業スペース）の使いすぎを防ぎます。

#define MAX_LINE_LENGTH 10000      // 1行あたりの最大の文字数
#define MAX_SENTENCE_LENGTH 100000 // 区切られた文（センテンス）の最大数
#define MAX_RESULT_LENGTH 10000    // 検索にヒットした結果をまとめた文字列の最大文字数

#define NUM_COL 2                  // CSVデータの列数（正規表現と検索対象の2列）

// 出力するCSVファイルの名前のひな形です。
// %sの部分には、後でプログラムが「日付・時刻」や「GPUの使用有無」を自動的に当てはめます。
#define OUTPUT_CSV_TEMPLATE "./results/results_%s%s.csv"

#define NFA_EXECUTABLE "./nfa.out" // 実行ファイルの名前

// データセット関連の設定
#define DEFAULT_SUBSET_SIZE 500    // 大量テキストから切り出すデフォルトの文字数（UTF-8文字数）
#define TARGET_TEXT_PATH "./data/target_text.txt" // 検索対象テキストファイルのパス
