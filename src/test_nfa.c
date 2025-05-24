#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <csv.h>
#include <unistd.h> 

#include "config.h"
#include "nfa.h"

// 現在の JST 時刻を "YYYYMMDD_HH_MM" 形式で取得
// buffer変数への書き込みを行う。
void get_jst_timestamp(char *buffer, size_t size) {
    time_t rawtime;
    struct tm *timeinfo;

    time(&rawtime);
    timeinfo = localtime(&rawtime); // システムのタイムゾーン（通常 JST）

    // strftime(buffer, size, "%Y%m%d_%H_%M", timeinfo);
    strftime(buffer, size, "%Y%m%d_%H_%M_%S", timeinfo); 
}

static double now_sec(void)
{
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

void remove_trailing_newline(char *s) {
    char *p = strchr(s, '\n');
    if (p) *p = '\0';
}

// CSVのヘッダーを書き込む
void write_csv_header(FILE *file) {
    fprintf(file, "正規表現,検索対象,マッチ結果,実行時間(秒)\n");
}

// CSVのファイル名を生成
void generate_csv_filename(char *filename, size_t size) {
    // 現在の JST 時刻をtimestamp変数に格納
    char timestamp[20];
    get_jst_timestamp(timestamp, sizeof(timestamp));

    /* ----- GPU 版判定： -DGPU_RUN 付きでビルドした場合だけ "_gpu" ----- */
    const char *gpu_suffix = "";
    #ifdef GPU_RUN //実行時に定義された引数を拾う
        gpu_suffix = "_gpu";
    #endif

    // ファイル名を動的に作成し、filenameに格納
    // char output_csv[50];
    snprintf(filename, size,
             OUTPUT_CSV_TEMPLATE, timestamp, gpu_suffix);
}

// 与えられた文字列lineを区切ってtokens配列に格納
size_t split_csv_static(char *line, char *regex, char *target, size_t buflen) {
    size_t n = 0;
    char *tok;
    /* line 内で ',' を '\0' に書き換えつつ空トークンも取得 */
    for (tok = strtok(line, ",");
         tok != NULL;
         tok = strtok(NULL, ","))      /* ← ここで NULL */
    {
        n++;

        if (n == 1) {
            strncpy(regex, tok, buflen - 1);
            regex[buflen - 1] = '\0';
        } else if (n == 2) {
            strncpy(target, tok, buflen - 1);
            target[buflen - 1] = '\0';
        }
    }
    return n;        
}

// 文字列を.で区切ってarrayに格納
size_t split_str_to_array(const char *src, char lines[][MAX_LINE_LENGTH]) {
    // nullがinputされた場合は何もしない
    if (!src || !lines) return 0;

    /* strsep を使うために書き換え可能なバッファを作る */
    char *work = strdup(src); //確保から書き込みまで
    if (!work) return 0;

    size_t n = 0;
    char *p   = work;
    char *tok;

    while (n < MAX_LINE_LENGTH && (tok = strsep(&p, ".")) != NULL) {
        /* 255 文字までコピーして必ず終端する */
        strncpy(lines[n], tok, MAX_LINE_LENGTH - 1);
        lines[n][MAX_LINE_LENGTH - 1] = '\0';
        ++n;
    }

    free(work);
    return n;
}

void join_matches(char *result, size_t cap,
                  const char list[][MAX_LINE_LENGTH],
                  const size_t *idx, size_t n)
{
    result[0] = '\0';
    for (size_t i = 0; i < n; ++i) {
        /* 先頭以降はドットを追加 */
        if (i > 0) {
            strncat(result, ".", cap - strlen(result) - 1);
        }
        /* マッチ文字列を追加 */
        strncat(result, list[idx[i]], cap - strlen(result) - 1);
    }
}

int main() {
    FILE *file = fopen("./data/test_cases.csv", "r");

    char output_csv[50];
    generate_csv_filename(output_csv, sizeof output_csv);
    
    FILE *csv_out = fopen(output_csv, "w");
    write_csv_header(csv_out); // ヘッダー行を追加

    char line[MAX_LINE_LENGTH];
    char regex[MAX_LINE_LENGTH] = "";
    char target[MAX_LINE_LENGTH]; //正規表現マッチの検索対象文字列
    char target_list[MAX_SENTENCE_LENGTH][MAX_LINE_LENGTH]; //検索対象を\nで分割し、リストにしたもの。
    char result[MAX_LINE_LENGTH];

    // char csv_record[NUM_COL][MAX_LINE_LENGTH];

    // double start_time = now_sec(); 
    double case_start;
    double total_time = 0.0;
    
    int first_line = 1;

    // fgetsは呼び出しのたびにファイルストリームの行を読み込む。
    // 最終行を読み込もうとするとnullになるので、while roopを抜ける。
    while (fgets(line, sizeof(line), file)) {
        

        // 1行目はヘッダーなのでスキップしたい。
        if (first_line) {
            first_line = 0;
            continue;
        }

        split_csv_static(line, regex, target, sizeof(regex));
        remove_trailing_newline(target);
        printf("regex: %s\n", regex);
        printf("target: %s\n", target);

        size_t n = split_str_to_array(target, target_list);
        printf("n: %zu\n", n);

        case_start = now_sec();

        // ここからNFA実行
        NFA *nfa = nfa_compile(regex);
        size_t hit_idx[MAX_SENTENCE_LENGTH];
        size_t k = nfa_grep_idx_arr(nfa, target_list, n, hit_idx);

        double case_time = (double)(now_sec() - case_start);
        // ここでNFA完了

        printf("Query: %s\n", regex);
        printf("Target: %s\n", target);
        // printf("Matched: %zu\n", k);
        printf("Execution Time: %.6f sec\n", case_time);
        printf("------------------------\n");

        join_matches(result, sizeof(result),
             target_list, hit_idx, k);
        fprintf(csv_out, "\"%s\",\"%s\",\"%s\",%.6f\n", regex, target, result, case_time);

        total_time += case_time;
    }

    fclose(file);
    fclose(csv_out);

    return 0;
}