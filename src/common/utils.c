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


