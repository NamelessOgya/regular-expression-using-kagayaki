#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "config.h"
#include "utils.h"

/**
 * 現在の JST (日本標準時) 時刻を取得するフォーマット関数。
 * 
 * [担当処理]
 * システムの現在時刻を取得し、ファイル名などに使いやすい "YYYYMMDD_HH_MM_SS" 形式の文字列に変換してバッファに書き込みます。
 * 
 * [想定I/O]
 * - input:  空の文字列バッファ, バッファのサイズ (例: char buf[20], 20)
 * - output: バッファ内に "20260405_15_38_45" のような文字列が格納される
 */
void get_jst_timestamp(char *buffer, size_t size) {
    time_t rawtime;
    struct tm *timeinfo;

    time(&rawtime);
    timeinfo = localtime(&rawtime); // システムのタイムゾーン（通常 JST）

    strftime(buffer, size, "%Y%m%d_%H_%M_%S", timeinfo); 
}

/**
 * 現在時刻を「秒単位」の高精度な小数値（double）で取得する関数。
 * 
 * [担当処理]
 * ベンチマークなどで「実行前後の時間の差分」を測るため、非常に細かい精度（ナノ秒レベル）まで
 * 計測して「秒」として計算・返却します。
 * 
 * [想定I/O]
 * - input:  なし
 * - output: 1712294123.456789 のような現在の秒数(double型)
 */
double now_sec(void)
{
    struct timespec ts;
    timespec_get(&ts, TIME_UTC);
    return ts.tv_sec + ts.tv_nsec * 1e-9;
}

/**
 * 文字列の末尾にある改行文字('\n')を取り除くユーティリティ関数。
 * 
 * [担当処理]
 * ファイルから1行読み込んだ際に末尾についてくる不要な改行を検索し、
 * そこを文字列の終端記号('\0')で上書きすることによって文字を消去します。
 * 
 * [想定I/O]
 * - input:  "hello\n"
 * - output: "hello" に書き換わる
 */
void remove_trailing_newline(char *s) {
    // 文字列の長さを図り、最後の文字が '\n' かどうかだけを判定する
    size_t len = strlen(s);
    if (len > 0 && s[len - 1] == '\n') {
        s[len - 1] = '\0';
    }
}

/**
 * 結果出力用CSVファイルのヘッダー行を書き込む関数。
 * 
 * [担当処理]
 * オープンされたファイルポインタに対し、1行目となるカラム名書き込みを行います。
 * 
 * [想定I/O]
 * - input:  書き込み可能なファイルポインタ (FILE *)
 * - output: ファイルに対して "正規表現,検索対象,マッチ結果,実行時間(秒)\n" が書き込まれる
 */
void write_csv_header(FILE *file) {
    fprintf(file, "正規表現,検索対象,マッチ結果,実行時間(秒)\n");
}

/**
 * 出力用のCSVファイル名を自動生成する関数。
 * 
 * [担当処理]
 * `get_jst_timestamp` を呼び出して現在時刻を取得し、さらに起動時のモード(GPUかCPUか)に
 * 応じてサフィックスを付与したファイル名を作成します。
 * 
 * [想定I/O]
 * - input:  空の文字列バッファ, バッファのサイズ
 * - output: "./result_20260405_15_38_45.csv" や "./result_20260405_15_38_45_gpu.csv" が格納される
 */
void generate_csv_filename(char *filename, size_t size) {
    char timestamp[20];
    get_jst_timestamp(timestamp, sizeof(timestamp));

    const char *gpu_suffix = "";
    #ifdef GPU_RUN
        gpu_suffix = "_gpu";
    #endif

    snprintf(filename, size, OUTPUT_CSV_TEMPLATE, timestamp, gpu_suffix);
}

/**
 * CSVの1行をカンマ(,)で分割し、それぞれの変数に振り分ける処理。
 * 
 * [担当処理]
 * 読み込んだCSVのテキスト("正規表現パターン,検索対象文字列")をカンマで分割し、
 * 引数で渡された `regex` 用の配列と `target` 用の配列にそれぞれコピー（分解）します。
 * 
 * [想定I/O]
 * - input:  line="a(b|c)*d,abcde", それぞれの格納用配列
 * - output: regex="a(b|c)*d", target="abcde" が格納される。戻り値として分割した要素数(2)を返す。
 */
size_t split_csv_static(char *line, char *regex, char *target, size_t buflen) {
    size_t n = 0;
    
    // strtokは呼び出すたびに、区切り文字までを切り出して先頭のポインタを返してくれる便利な関数です
    char *tok = strtok(line, ",");
    while (tok != NULL) {
        n++;
        size_t tok_len = strlen(tok);

        if (tok_len >= buflen) {
            fprintf(stderr, "[Error] split_csv_static: Token length (%zu) exceeds or equals buffer size (%zu). Aborting parse for this line.\n", tok_len, buflen);
            return (size_t)-1;
        }

        if (n == 1) {
            strcpy(regex, tok);
        } else if (n == 2) {
            strcpy(target, tok);
        }
        
        // NULLを渡すと「さっきの続きから」という意味になります
        tok = strtok(NULL, ",");
    }
    return n;        
}

/**
 * 大きなテキストをピリオド(.)で分割し、文章の配列リストに変換する処理。
 * 
 * [担当処理]
 * まとまった英語の文章などを与え、それを文(sentence)ごとに分割して
 * 2次元配列（文字列のリスト）に1つ1つ格納していきます。
 * 
 * [想定I/O]
 * - input:  src="Hello.World.Test", 2次元配列 lines
 * - output: lines[0]="Hello", lines[1]="World", lines[2]="Test" と格納され、戻り値に要素数(3)を返す。
 */
size_t split_str_to_array(const char *src, char lines[][MAX_LINE_LENGTH]) {
    if (!src || !lines) return 0;

    char *work = strdup(src);
    if (!work) return 0;

    size_t n = 0;
    char *p = work;
    char *tok;
    while (1) {
        tok = strsep(&p, ".");
        if (tok == NULL) {
            break; // これ以上区切れる文字列がない場合は終了
        }
        
        if (n >= MAX_SENTENCE_LENGTH) {
            fprintf(stderr, "[Error] split_str_to_array: Number of sentences exceeds MAX_SENTENCE_LENGTH (%d).\n", MAX_SENTENCE_LENGTH);
            free(work);
            return (size_t)-1;
        }

        size_t tok_len = strlen(tok);
        if (tok_len >= MAX_LINE_LENGTH) {
            fprintf(stderr, "[Error] split_str_to_array: Sentence length (%zu) exceeds MAX_LINE_LENGTH (%d).\n", tok_len, MAX_LINE_LENGTH);
            free(work);
            return (size_t)-1;
        }
        
        strcpy(lines[n], tok);
        ++n;
    }

    free(work);
    return n;
}

/**
 * マッチした行（要素）だけを抽出し、再びピリオド(.)で繋いで1つの文字列に復元する処理。
 * 
 * [担当処理]
 * NFAエンジンがマッチしたと判定したインデックス(`idx`配列)をもとに、
 * リストの中からマッチ対象の文字列だけを拾い集め、結合して出力時の結果文字列を作ります。
 * 
 * [想定I/O]
 * - input:  list={"AAA","BBB","CCC"}, idx={0,2}, n=2 (マッチしたのは0番目と2番目)
 * - output: result="AAA.CCC" が結合されて格納される
 */
int join_matches(char *result, size_t cap, const char list[][MAX_RESULT_LENGTH], const size_t *idx, size_t n) {
    if (cap == 0) return -1;
    result[0] = '\0';
    for (size_t i = 0; i < n; ++i) {
        size_t concat_len = strlen(list[idx[i]]) + (i > 0 ? 1 : 0);
        
        if (strlen(result) + concat_len >= cap) {
            fprintf(stderr, "[Error] join_matches: Joined result exceeds buffer capacity (%zu). Aborting.\n", cap);
            return -1;
        }

        if (i > 0) {
            strcat(result, ".");
        }
        
        // 元のプリント機能は維持
        printf("%s", list[idx[i]]);
        strcat(result, list[idx[i]]);
    }
    return 0;
}
