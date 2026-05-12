#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h> 

#include "config.h"
#include "nfa.h"

// ============================================================================
// グローバル変数（プログラム全体で共有される変数）
// ============================================================================
// 注意：target_list のような巨大な配列（約1GB）を関数の中（ローカル変数）で作ると、
// メモリの作業スペースが足りなくなりプログラムが強制終了（スタックオーバーフロー）
// してしまいます。それを防ぐために、あえて関数の外（グローバル領域）に置いています。

char line[MAX_LINE_LENGTH];                               // CSVファイルから読み込んだ1行の文字列
char regex[MAX_LINE_LENGTH] = "";                         // 検索に使う正規表現の文字列
char target[MAX_LINE_LENGTH];                             // 正規表現で検索される対象の文字列
char target_list[MAX_SENTENCE_LENGTH][MAX_LINE_LENGTH];   // 検索対象を「.（ピリオド）」で分割したリスト
char result[MAX_RESULT_LENGTH];                           // マッチした結果を結合した文字列


// ============================================================================
// 便利な道具箱（ヘルパー関数）
// ============================================================================

// 現在の時刻を「20260513_12_34_56」のような形式の文字列にして buffer に書き込みます。
void get_jst_timestamp(char *buffer, size_t size) {
    time_t rawtime;
    struct tm *timeinfo;

    time(&rawtime);
    timeinfo = localtime(&rawtime); // パソコンの現在の時刻を取得

    strftime(buffer, size, "%Y%m%d_%H_%M_%S", timeinfo); 
}

// 現在の時刻を秒単位（小数）で取得します。処理時間を測るためのストップウォッチとして使います。
static double now_sec(void) {
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

// 文字列の最後についている「改行コード（エンターキーの跡）」を取り除きます。
void remove_trailing_newline(char *s) {
    char *p = strchr(s, '\n');
    if (p) {
        *p = '\0'; // 改行を見つけたら、そこを文字列の終わりに書き換える
    }
}

// CSVファイルの一番上（ヘッダー行）に、列の名前を書き込みます。
void write_csv_header(FILE *file) {
    fprintf(file, "正規表現,検索対象,マッチ結果,実行時間(秒)\n");
}

// 結果を保存するための新しいCSVファイルの名前を自動で作ります。
void generate_csv_filename(char *filename, size_t size) {
    char timestamp[20];
    get_jst_timestamp(timestamp, sizeof(timestamp)); // 現在の時刻を取得

    // GPUで動かしている場合はファイル名に「_gpu」を付け足します。
    const char *gpu_suffix = "";
    #ifdef GPU_RUN
        gpu_suffix = "_gpu";
    #endif

    // config.h で決めたひな形に、時刻と "_gpu" の文字を当てはめます。
    snprintf(filename, size, OUTPUT_CSV_TEMPLATE, timestamp, gpu_suffix);
}

// CSVの1行（カンマ区切り）を読み込んで、「正規表現(regex)」と「検索対象(target)」に分けます。
size_t split_csv_static(char *line, char *regex, char *target, size_t buflen) {
    size_t n = 0;
    char *tok;
    
    // カンマ「,」で文字列を区切って順番に取り出します。
    for (tok = strtok(line, ","); tok != NULL; tok = strtok(NULL, ",")) {
        n++;
        if (n == 1) {
            // 1つ目は「正規表現」
            strncpy(regex, tok, buflen - 1);
            regex[buflen - 1] = '\0'; // 安全のために末尾をちゃんと閉じる
        } else if (n == 2) {
            // 2つ目は「検索対象」
            strncpy(target, tok, buflen - 1);
            target[buflen - 1] = '\0';
        }
    }
    return n;        
}

// ひとつの長い文章を、ピリオド「.」ごとに区切って配列（リスト）にまとめます。
size_t split_str_to_array(const char *src, char lines[][MAX_LINE_LENGTH]) {
    if (!src || !lines) return 0;

    // 文字列を区切る処理のために、元の文章のコピー（作業用）を作ります。
    char *work = strdup(src); 
    if (!work) return 0;

    size_t n = 0;
    char *p = work;
    char *tok;

    // ピリオド「.」で区切れるだけ区切っていきます。
    while (n < MAX_SENTENCE_LENGTH && (tok = strsep(&p, ".")) != NULL) {
        strncpy(lines[n], tok, MAX_LINE_LENGTH - 1);
        lines[n][MAX_LINE_LENGTH - 1] = '\0';
        n++;
    }

    free(work); // 作業が終わったらコピーを捨てる（メモリの片付け）
    return n;
}

// マッチした複数の文章を、再びピリオド「.」で繋ぎ合わせて1つの文字列にします。
void join_matches(char *result, size_t cap, const char list[][MAX_LINE_LENGTH], const size_t *idx, size_t n) {
    result[0] = '\0'; // 最初は空っぽにしておく
    
    for (size_t i = 0; i < n; ++i) {
        if (i > 0) {
            strncat(result, ".", cap - strlen(result) - 1); // 2つ目以降はピリオドを挟む
        }
        printf("%s", list[idx[i]]); // 画面にも表示する
        strncat(result, list[idx[i]], cap - strlen(result) - 1); // 結果の文字列にくっつける
    }
}


// ============================================================================
// メインプログラム（ここから実行が始まります）
// ============================================================================
int main() {
    // 1. テスト用のデータが入っているファイルを開きます。
    FILE *file = fopen("./data/test_cases.csv", "r");
    if (!file) {
        printf("エラー: テストデータ(./data/test_cases.csv)が見つかりません。\n");
        return 1;
    }

    // 2. 結果を書き込むための新しいファイルを用意します。
    char output_csv[50];
    generate_csv_filename(output_csv, sizeof(output_csv));
    FILE *csv_out = fopen(output_csv, "w");
    write_csv_header(csv_out);

    double total_time = 0.0; // 全部でかかった時間を記録する変数
    int is_first_line = 1;   // 最初の行（ヘッダー行）かどうかを見分けるフラグ

    // 3. ファイルから1行ずつ読み込んで、ファイルの最後まで繰り返します。
    while (fgets(line, sizeof(line), file)) {
        
        // 最初の1行目はデータの名前（ヘッダー）なので読み飛ばします。
        if (is_first_line) {
            is_first_line = 0;
            continue;
        }

        // CSVから「正規表現」と「検索対象」を取り出し、不要な改行を消します。
        split_csv_static(line, regex, target, sizeof(regex));
        remove_trailing_newline(target);

        printf("正規表現(Regex): %s\n", regex);
        printf("検索対象(Target): %s\n", target);

        // 検索対象の長い文章を「.」で区切って配列（リスト）にします。
        size_t n = split_str_to_array(target, target_list);
        printf("区切られた文の数(n): %zu\n", n);

        // --------------------------------------------------------
        // ここから NFA（正規表現の検索）の実行と、時間の計測スタート！
        // --------------------------------------------------------
        double case_start = now_sec();

        // 正規表現のルールを読み込ませる（設計図を作る）
        NFA *nfa = nfa_compile(regex);
        size_t hit_idx[MAX_SENTENCE_LENGTH]; // ヒットした文章の番号をメモする配列
        
        // リストの中からマッチするものを探し出す
        size_t k = nfa_grep_idx_arr(nfa, target_list, n, hit_idx);

        // かかった時間を計算（ストップウォッチの時間をチェック）
        double case_time = (double)(now_sec() - case_start);
        
        nfa_free(nfa); // 使い終わったNFAの設計図を捨てる（メモリの片付け）
        // --------------------------------------------------------

        printf("検索クエリ(Query): %s\n", regex);
        printf("ターゲット(Target): %s\n", target);
        printf("マッチした数(Matched): %zu\n", k);
        printf("実行時間(Execution Time): %.6f 秒\n", case_time);
        printf("------------------------\n");

        // 見つかった文章をピリオドで繋ぎ合わせて、結果の文字列を作ります。
        join_matches(result, sizeof(result), target_list, hit_idx, k);
        
        // 結果をCSVファイルに書き込みます。
        fprintf(csv_out, "\"%s\",\"%s\",\"%s\",%.6f\n", regex, target, result, case_time);

        total_time += case_time; // トータルの実行時間に足し合わせる
    }

    // 使い終わったファイルはちゃんと閉じます。
    fclose(file);
    fclose(csv_out);

    return 0;
}