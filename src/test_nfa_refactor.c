#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAX_LINE_LENGTH 256
#define MAX_COMMAND_LENGTH 1024
// #define OUTPUT_CSV_TEMPLATE "./results/results_%s.csv"
#define OUTPUT_CSV_TEMPLATE "./results/results_%s%s.csv"   /* ← %s を 2 つに */
#define NFA_EXECUTABLE "./nfa.out"

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
    char output_csv[50];
    snprintf(filename, size,
             OUTPUT_CSV_TEMPLATE, timestamp, gpu_suffix);
}


int main() {
    FILE *file = fopen("./data/test_cases.csv", "r");

    char output_csv[50];
    generate_csv_filename(char output_csv, sizeof output_csv)
    printf("output_csv: %s\n", output_csv);
    // FILE *csv_out = fopen(output_csv, "w");
    // if (!csv_out) {
    //     perror("Failed to open results CSV file");
    //     fclose(file);
    //     return 1;
    // }

    // write_csv_header(csv_out); // ヘッダー行を追加

    // char line[MAX_LINE_LENGTH];
    // char regex[MAX_LINE_LENGTH] = "";
    // char target[MAX_LINE_LENGTH];
    // char result[MAX_LINE_LENGTH];

    // clock_t start_time = clock(); //wall clockに修正必要 
    // clock_t case_start;
    // double total_time = 0.0;

    // int first_line = 1;
    // while (fgets(line, sizeof(line), file)) {
    //     if (first_line) {
    //         first_line = 0;
    //         continue;
    //     }

    //     char *token = strtok(line, ",");
    //     if (token) {
    //         strcpy(regex, token);
    //         token = strtok(NULL, ",");
    //         if (token) {
    //             strcpy(target, token);
    //         } else {
    //             continue;
    //         }
    //     } else {
    //         continue;
    //     }

    //     char command[MAX_COMMAND_LENGTH];
    //     snprintf(command, sizeof(command), "%s \"%s\" \"%s\"", NFA_EXECUTABLE, regex, target);

    //     case_start = clock();
    //     FILE *fp = popen(command, "r");
    //     if (fp == NULL) {
    //         perror("Failed to run command");
    //         continue;
    //     }

    //     if (fgets(result, sizeof(result), fp) == NULL) {
    //         strcpy(result, "No Match");
    //     } else {
    //         pass
    //     }

    //     pclose(fp);

    //     double case_time = (double)(clock() - case_start) / CLOCKS_PER_SEC;

    //     printf("Query: %s\n", regex);
    //     printf("Target: %s\n", target);
    //     printf("Matched: %s\n", result);
    //     printf("Execution Time: %.6f sec\n", case_time);
    //     printf("------------------------\n");

    //     fprintf(csv_out, "\"%s\",\"%s\",\"%s\",%.6f\n", regex, target, result, case_time);

    //     total_time += case_time;
    // }

    // fclose(file);
    // fclose(csv_out);

    // double elapsed_time = (double)(clock() - start_time) / CLOCKS_PER_SEC;
    // printf("Total Execution Time: %.6f sec\n", elapsed_time);
    // printf("Results saved to: %s\n", output_csv);

    return 0;
}