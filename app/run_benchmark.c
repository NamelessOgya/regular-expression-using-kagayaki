#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <unistd.h> 

#include "config.h"
#include "nfa.h"
#include "utils.h"

/* 
 * 以下の配列は非常にサイズが大きいため（MAX_SENTENCE_LENGTH = 100,000など）、
 * main関数の中（ローカル変数）に作ると「スタックオーバーフロー」というエラーでクラッシュする可能性があります。
 * それを防ぐため、安全なメモリ領域（BSSというデータ領域）に確保される「グローバル変数」として定義しています。
 */
char line[MAX_LINE_LENGTH];
char regex[MAX_LINE_LENGTH] = "";
char target[MAX_LINE_LENGTH]; //正規表現マッチの長大な検索対象文字列

int main(int argc, char *argv[]) {
    // デフォルトの設定
    const char *text_path = TARGET_TEXT_PATH;
    size_t subset_char_limit = DEFAULT_SUBSET_SIZE;

    // コマンドライン引数の解析
    if (argc >= 2) {
        text_path = argv[1];
    }
    if (argc >= 3) {
        int val = atoi(argv[2]);
        if (val > 0) {
            subset_char_limit = (size_t)val;
        } else {
            fprintf(stderr, "[Warning] Invalid subset size '%s'. Using default: %zu\n", argv[2], subset_char_limit);
        }
    }

    // 大容量テキストデータの読み込み
    FILE *text_file = fopen(text_path, "r");
    if (!text_file) {
        fprintf(stderr, "[Error] Failed to open target text file: %s\n", text_path);
        return 1;
    }

    
    // 一旦ファイル全体（またはバッファ一杯）を読み込むためのバッファ
    char *large_text_buffer = malloc(MAX_SENTENCE_LENGTH);
    if (!large_text_buffer) {
        perror("Failed to allocate memory for large text buffer");
        fclose(text_file);
        return 1;
    }
    
    size_t read_bytes = fread(large_text_buffer, 1, MAX_SENTENCE_LENGTH - 1, text_file);
    large_text_buffer[read_bytes] = '\0';
    fclose(text_file);

    // 文字数（UTF-8）に基づくサブセットバイト長の計算
    size_t subset_bytes = 0;
    size_t char_count = 0;
    while (large_text_buffer[subset_bytes] != '\0' && char_count < subset_char_limit) {
        unsigned char c = (unsigned char)large_text_buffer[subset_bytes];
        if (c < 0x80) {
            subset_bytes += 1;
        } else if ((c & 0xE0) == 0xC0) {
            subset_bytes += 2;
        } else if ((c & 0xF0) == 0xE0) {
            subset_bytes += 3;
        } else if ((c & 0xF8) == 0xF0) {
            subset_bytes += 4;
        } else {
            subset_bytes += 1; // 不正なバイトの場合
        }
        char_count++;
    }
    
    char *target_subset = malloc(subset_bytes + 1);
    if (!target_subset) {
        perror("Failed to allocate memory for target subset");
        free(large_text_buffer);
        return 1;
    }
    memcpy(target_subset, large_text_buffer, subset_bytes);
    target_subset[subset_bytes] = '\0';
    
    // 元の大容量バッファは不要になったので解放
    free(large_text_buffer);

    printf("======================================\n");
    printf(" Loaded dataset: %s (%zu bytes)\n", text_path, read_bytes);
    printf(" Extracted subset: %zu characters (%zu bytes)\n", char_count, subset_bytes);
    printf(" Subset preview (first 100 chars):\n");
    printf(" \"");
    for (size_t i = 0, cc = 0; target_subset[i] != '\0' && cc < 100; cc++) {
        unsigned char c = (unsigned char)target_subset[i];
        if (c < 0x80) {
            putchar(target_subset[i]);
            i += 1;
        } else if ((c & 0xE0) == 0xC0) {
            printf("%.2s", &target_subset[i]);
            i += 2;
        } else if ((c & 0xF0) == 0xE0) {
            printf("%.3s", &target_subset[i]);
            i += 3;
        } else if ((c & 0xF8) == 0xF0) {
            printf("%.4s", &target_subset[i]);
            i += 4;
        } else {
            putchar(target_subset[i]);
            i += 1;
        }
    }
    printf("...\"\n");
    printf("======================================\n\n");

    FILE *file = fopen("./data/test_cases.csv", "r");
    if (!file) {
        perror("Failed to open ./data/test_cases.csv");
        free(target_subset);
        return 1;
    }

    char output_csv[50];
    generate_csv_filename(output_csv, sizeof output_csv);
    
    FILE *csv_out = fopen(output_csv, "w");
    write_csv_header(csv_out); // ヘッダー行を追加

    double case_start;
    double total_time = 0.0;
    
    int first_line = 1;

    // fgetsは呼び出しのたびにファイルストリームの行を読み込む。
    while (fgets(line, sizeof(line), file)) {
        // 1行目はヘッダーなのでスキップしたい。
        if (first_line) {
            first_line = 0;
            continue;
        }

        char dummy_target[MAX_LINE_LENGTH];
        if (split_csv_static(line, regex, dummy_target, sizeof(regex)) == (size_t)-1) {
            fprintf(stderr, "[Fatal Error] Benchmark aborted: Failure to parse CSV line.\n");
            exit(EXIT_FAILURE);
        }
        
        // CSVの検索対象列は無視し、切り出した大量テキストのサブセットを対象にする
        if (subset_bytes >= sizeof(target)) {
            fprintf(stderr, "[Error] Subset size in bytes (%zu) exceeds target buffer size (%zu).\n", subset_bytes, sizeof(target));
            exit(EXIT_FAILURE);
        }
        strcpy(target, target_subset);

        printf("regex: %s\n", regex);
        case_start = now_sec();

        // ここからNFA実行 (コンパイル含む)
        NFA *nfa = nfa_compile(regex);
        int hit = 0;
        if (nfa) {
            hit = nfa_search(nfa, target);
        }

        double case_time = (double)(now_sec() - case_start);
        // ここでNFA完了

        printf("Query: %s\n", regex);
        printf("Target (subset): [Length: %zu chars (%zu bytes)]\n", char_count, subset_bytes);
        printf("Matched: %s\n", hit ? "Yes" : "No");
        printf("Execution Time: %.6f sec\n", case_time);
        printf("------------------------\n");

        fprintf(csv_out, "\"%s\",\"[Subset %zu chars]\",\"%d\",%.6f\n", regex, char_count, hit, case_time);

        
        if (nfa) {
            nfa_free(nfa);
        }

        total_time += case_time;
    }

    fclose(file);
    fclose(csv_out);
    free(target_subset);

    printf("Benchmark finished! Total Execution Time: %.6f sec\n", total_time);
    return 0;
}