#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <signal.h>
#include <setjmp.h>

#include "config.h"
#include "nfa.h"
#include "utils.h"

// ============================================================
// タイムアウト制御
// ============================================================
static sigjmp_buf  timeout_env;
static volatile sig_atomic_t timed_out = 0;

static void alarm_handler(int sig) {
    (void)sig;
    timed_out = 1;
    siglongjmp(timeout_env, 1); // ループの先頭（sigsetjmpの直後）に飛ぶ
}

/* 
 * 以下の配列は非常にサイズが大きいため（MAX_SENTENCE_LENGTH = 100,000など）、
 * main関数の中（ローカル変数）に作ると「スタックオーバーフロー」というエラーでクラッシュする可能性があります。
 * それを防ぐため、安全なメモリ領域（BSSというデータ領域）に確保される「グローバル変数」として定義しています。
 */
char line[MAX_LINE_LENGTH];
char regex[MAX_LINE_LENGTH] = "";
char target[MAX_LINE_LENGTH]; //正規表現マッチの長大な検索対象文字列

int main(int argc, char *argv[]) {
    // stdout を常にライン・バッファに設定 (リダイレクト先が非端末でも安全)
    setvbuf(stdout, NULL, _IOLBF, 0);

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

    // SIGALRM ハンドラの登録（タイムアウト用）
    struct sigaction sa;
    sa.sa_handler = alarm_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;  // SA_RESTART は付けない（システムコールを再開させない）
    sigaction(SIGALRM, &sa, NULL);

    // 大容量テキストデータの読み込み
    FILE *text_file = fopen(text_path, "r");
    if (!text_file) {
        fprintf(stderr, "[Error] Failed to open target text file: %s\n", text_path);
        return 1;
    }

    // ファイル全体のサイズを取得して動的にメモリを確保する
    fseek(text_file, 0, SEEK_END);
    long file_size = ftell(text_file);
    if (file_size <= 0) {
        file_size = MAX_SENTENCE_LENGTH;
    }
    fseek(text_file, 0, SEEK_SET);

    char *large_text_buffer = malloc(file_size + 1);
    if (!large_text_buffer) {
        perror("Failed to allocate memory for large text buffer");
        fclose(text_file);
        return 1;
    }
    
    size_t read_bytes = fread(large_text_buffer, 1, file_size, text_file);
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

    char output_csv[80];
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

        // fgets は行末の '\n' を含むため、正規表現文字列から除去する
        // ('\r\n' (Windows) にも対応)
        remove_trailing_newline(regex);
        {
            size_t rlen = strlen(regex);
            if (rlen > 0 && regex[rlen - 1] == '\r') regex[rlen - 1] = '\0';
        }

        printf("regex: %s\n", regex);

        // 空のパターンはスキップ（末尾空行対策）
        if (strlen(regex) == 0) continue;

        // ============================================================
        // タイムアウト付き実行
        // alarm() で BENCHMARK_TIMEOUT_SEC 秒後に SIGALRM を送る。
        // SIGALRM が来たら alarm_handler が siglongjmp し、else 節に飛ぶ。
        // ============================================================
        NFA * volatile nfa = NULL;
        SearchResult result = {0};
        double case_time;
        volatile int did_timeout = 0;

        timed_out = 0;
        alarm(BENCHMARK_TIMEOUT_SEC); // タイマースタート

        if (sigsetjmp(timeout_env, 1) == 0) {
            // ---- 通常実行パス ----
            nfa = nfa_compile(regex);

#if defined(GPU_LINE_RUN)
            printf("  [GPU Line] Running Simple Line-Parallel Strategy...\n");
            double start = now_sec();
            result = search_engine_execute("gpu_line_parallel", nfa, target_subset, subset_bytes);
            case_time = now_sec() - start;
#elif defined(GPU_CHUNK_RUN)
            printf("  [GPU Chunk] Running Overlapping Chunk-Parallel Strategy...\n");
            double start = now_sec();
            result = search_engine_execute("gpu_chunk_parallel", nfa, target_subset, subset_bytes);
            case_time = now_sec() - start;
#elif defined(GPU_RUN)
            printf("  [GPU] Running Simple Line-Parallel Strategy...\n");
            double start1 = now_sec();
            result = search_engine_execute("gpu_line_parallel", nfa, target_subset, subset_bytes);
            case_time = now_sec() - start1;

            printf("  [GPU] Running Overlapping Chunk-Parallel Strategy...\n");
            double start2 = now_sec();
            SearchResult result_chunk = search_engine_execute("gpu_chunk_parallel", nfa, target_subset, subset_bytes);
            double chunk_time = now_sec() - start2;
            printf("  [GPU Comparison] Line-Parallel: %.6f sec | Chunk-Parallel: %.6f sec (Chunk matched: %zu)\n",
                   case_time, chunk_time, result_chunk.count);
            free_search_result(&result_chunk);
#else
            case_start = now_sec();
            result = search_engine_execute("cpu_line_sequential", nfa, target_subset, subset_bytes);
            case_time = now_sec() - case_start;
#endif
            alarm(0); // タイマーキャンセル

        } else {
            // ---- タイムアウトパス ----
            did_timeout = 1;
            case_time = (double)BENCHMARK_TIMEOUT_SEC;
            alarm(0); // 念のためキャンセル
            printf("[TIMEOUT] regex '%s' exceeded %d sec. Recording as %.0f sec.\n",
                   regex, BENCHMARK_TIMEOUT_SEC, case_time);
        }
        // ここでNFA実行完了

        // ===== 計測時間外での結果集約およびCSV書き出し (I/O分離) =====
        char *csv_details = NULL;
        if (did_timeout) {
            // タイムアウト時: マッチ情報なし
            csv_details = strdup("TIMEOUT");
            if (!csv_details) { perror("strdup"); exit(EXIT_FAILURE); }
        } else if (result.count > 0) {
            size_t details_capacity = 4096;
            csv_details = malloc(details_capacity);
            if (!csv_details) {
                perror("Failed to allocate memory for CSV details");
                exit(EXIT_FAILURE);
            }
            csv_details[0] = '\0';
            size_t details_len = 0;

            // 最初の MAX_STORED_MATCHES 件のみ内容を出力（それ以降は件数のみ）
            size_t display_count = result.count < MAX_STORED_MATCHES
                                   ? result.count : MAX_STORED_MATCHES;

            for (size_t i = 0; i < display_count; i++) {
                char temp_match[16384];
                int header_len = snprintf(temp_match, sizeof(temp_match), "Line %d: ", result.items[i].line_number);
                int dest_idx = header_len;
                const char *src = result.items[i].line_content;
                while (*src != '\0' && dest_idx < (int)sizeof(temp_match) - 3) {
                    if (*src == '"') {
                        temp_match[dest_idx++] = '"';
                        temp_match[dest_idx++] = '"';
                    } else {
                        temp_match[dest_idx++] = *src;
                    }
                    src++;
                }
                temp_match[dest_idx] = '\0';

                size_t temp_len = strlen(temp_match);
                size_t needed = details_len + temp_len + (i > 0 ? 3 : 0) + 1;
                if (needed > details_capacity) {
                    while (details_capacity < needed) details_capacity *= 2;
                    char *new_details = realloc(csv_details, details_capacity);
                    if (!new_details) { perror("realloc"); exit(EXIT_FAILURE); }
                    csv_details = new_details;
                }
                if (i > 0) {
                    strcat(csv_details, " | ");
                    details_len += 3;
                }
                strcat(csv_details, temp_match);
                details_len += temp_len;
            }

            // 残りの件数を末尾に追記
            if (result.count > MAX_STORED_MATCHES) {
                char more_buf[64];
                snprintf(more_buf, sizeof(more_buf), " | ... and %zu more",
                         result.count - MAX_STORED_MATCHES);
                size_t more_len = strlen(more_buf);
                size_t needed = details_len + more_len + 1;
                if (needed > details_capacity) {
                    csv_details = realloc(csv_details, needed);
                    if (!csv_details) { perror("realloc more_buf"); exit(EXIT_FAILURE); }
                }
                strcat(csv_details, more_buf);
            }
        } else {
            csv_details = strdup("No match");
            if (!csv_details) {
                perror("strdup for No match failed");
                exit(EXIT_FAILURE);
            }
        }

        // ターミナル出力
        printf("Query: %s\n", regex);
        printf("Target (subset): [Length: %zu chars (%zu bytes)]\n", char_count, subset_bytes);
        if (did_timeout) {
            printf("Matched Lines: - (TIMEOUT)\n");
            printf("Execution Time: %.6f sec [TIMEOUT: exceeded %d sec]\n",
                   case_time, BENCHMARK_TIMEOUT_SEC);
        } else {
            printf("Matched Lines: %zu lines\n", result.count);
            printf("Execution Time: %.6f sec\n", case_time);
        }
        printf("------------------------\n");

        // CSVへの書き出し（タイムアウト時はマッチ数を "-" で記録）
        if (did_timeout) {
            fprintf(csv_out, "\"%s\",\"[Subset %zu chars]\",\"-\",\"%s\",%.6f\n",
                    regex, char_count, csv_details, case_time);
        } else {
            fprintf(csv_out, "\"%s\",\"[Subset %zu chars]\",\"%zu\",\"%s\",%.6f\n",
                    regex, char_count, result.count, csv_details, case_time);
        }
        fflush(csv_out);  // クラッシュ時にもディスクへ確実に書き出す

        // メモリ解放（タイムアウト時は SearchResult が未初期化のため free しない）
        free(csv_details);
        if (!did_timeout) free_search_result(&result);
        if (nfa) nfa_free(nfa);

        total_time += case_time;
    }

    fclose(file);
    fclose(csv_out);
    free(target_subset);

    printf("Benchmark finished! Total Execution Time: %.6f sec\n", total_time);
    return 0;
}