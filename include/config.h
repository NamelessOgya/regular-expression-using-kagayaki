/* config.h */
#pragma once

// プログラム全体で使う設定値（定数）
#define MAX_LINE_LENGTH    10000   // 1行あたりの最大文字数
#define MAX_SENTENCE_LENGTH 100000 // 区切られた文（センテンス）の最大数
#define MAX_RESULT_LENGTH  10000   // マッチ結果をまとめた文字列の最大文字数

#define NUM_COL 2                  // CSVデータの列数（正規表現と検索対象の2列）

// 出力 CSV ファイル名のテンプレート（%s = タイムスタンプ, %s = GPUサフィックス）
#define OUTPUT_CSV_TEMPLATE "./results/results_%s%s.csv"

#define NFA_EXECUTABLE "./nfa.out" // 実行ファイルの名前

// データセット関連の設定
#define DEFAULT_SUBSET_SIZE 500              // テキストから切り出すデフォルト文字数（UTF-8文字数）
#define TARGET_TEXT_PATH "./data/wiki_plain.txt" // ベンチマーク対象テキストファイルのパス

// タイムアウト設定
#define BENCHMARK_TIMEOUT_SEC 300           // 1クエリあたりの上限時間（秒）。超えたら打ち切り

// マッチ結果の保存上限
// 全マッチのカウントは続けるが、行の内容ストアはこの件数まで（O(n²)問題の防止）
#define MAX_STORED_MATCHES 5