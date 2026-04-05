#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <unistd.h> 

#include "config.h"
#include "nfa.h"
#include "utils.h"

char line[MAX_LINE_LENGTH];
char regex[MAX_LINE_LENGTH] = "";
char target[MAX_LINE_LENGTH]; //正規表現マッチの検索対象文字列
char target_list[MAX_SENTENCE_LENGTH][MAX_LINE_LENGTH]; //検索対象を\nで分割し、リストにしたもの。
char result[MAX_RESULT_LENGTH];

int main() {
    FILE *file = fopen("./data/test_cases.csv", "r");
    if (!file) {
        perror("Failed to open ./data/test_cases.csv");
        return 1;
    }
    if (!file) {
        perror("Failed to open ./data/test_cases.csv");
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
        printf("Matched: %zu\n", k);
        printf("Execution Time: %.6f sec\n", case_time);
        printf("------------------------\n");

        join_matches(result, sizeof(result), target_list, hit_idx, k);
        fprintf(csv_out, "\"%s\",\"%s\",\"%s\",%.6f\n", regex, target, result, case_time);

        total_time += case_time;
    }

    fclose(file);
    fclose(csv_out);

    return 0;
}