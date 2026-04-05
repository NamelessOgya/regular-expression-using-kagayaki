#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "config.h"
#include "utils.h"

// 現在の JST 時刻を "YYYYMMDD_HH_MM_SS" 形式で取得
void get_jst_timestamp(char *buffer, size_t size) {
    time_t rawtime;
    struct tm *timeinfo;

    time(&rawtime);
    timeinfo = localtime(&rawtime); // システムのタイムゾーン（通常 JST）

    strftime(buffer, size, "%Y%m%d_%H_%M_%S", timeinfo); 
}

double now_sec(void)
{
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

void remove_trailing_newline(char *s) {
    char *p = strchr(s, '\n');
    if (p != NULL) {
        *p = '\0';
    }
}

// CSVのヘッダーを書き込む
void write_csv_header(FILE *file) {
    fprintf(file, "正規表現,検索対象,マッチ結果,実行時間(秒)\n");
}

// CSVのファイル名を生成
void generate_csv_filename(char *filename, size_t size) {
    char timestamp[20];
    get_jst_timestamp(timestamp, sizeof(timestamp));

    const char *gpu_suffix = "";
    #ifdef GPU_RUN
        gpu_suffix = "_gpu";
    #endif

    snprintf(filename, size, OUTPUT_CSV_TEMPLATE, timestamp, gpu_suffix);
}

// 与えられた文字列lineをカンマ(,)で区切って変数に格納
size_t split_csv_static(char *line, char *regex, char *target, size_t buflen) {
    size_t n = 0;
    
    // strtokは呼び出すたびに、区切り文字までを切り出して先頭のポインタを返してくれる便利な関数です
    char *tok = strtok(line, ",");
    while (tok != NULL) {
        n++;
        if (n == 1) {
            strncpy(regex, tok, buflen - 1);
            regex[buflen - 1] = '\0';
        } else if (n == 2) {
            strncpy(target, tok, buflen - 1);
            target[buflen - 1] = '\0';
        }
        
        // NULLを渡すと「さっきの続きから」という意味になります
        tok = strtok(NULL, ",");
    }
    return n;        
}

// 文字列を.で区切ってarrayに格納
size_t split_str_to_array(const char *src, char lines[][MAX_LINE_LENGTH]) {
    if (!src || !lines) return 0;

    char *work = strdup(src);
    if (!work) return 0;

    size_t n = 0;
    char *p = work;
    // strsepは文字列を区切って、次のポインタへ進めてくれる関数です
    char *tok;
    while (n < MAX_SENTENCE_LENGTH) {
        tok = strsep(&p, ".");
        if (tok == NULL) {
            break; // これ以上区切れる文字列がない場合は終了
        }
        
        strncpy(lines[n], tok, MAX_LINE_LENGTH - 1);
        lines[n][MAX_LINE_LENGTH - 1] = '\0';
        ++n;
    }

    free(work);
    return n;
}

void join_matches(char *result, size_t cap, const char list[][MAX_RESULT_LENGTH], const size_t *idx, size_t n) {
    result[0] = '\0';
    for (size_t i = 0; i < n; ++i) {
        if (i > 0) {
            strncat(result, ".", cap - strlen(result) - 1);
        }
        printf("%s", list[idx[i]]);
        strncat(result, list[idx[i]], cap - strlen(result) - 1);
    }
}
