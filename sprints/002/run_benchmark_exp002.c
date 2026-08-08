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

static sigjmp_buf  timeout_env;
static volatile sig_atomic_t timed_out = 0;

static void alarm_handler(int sig) {
    (void)sig;
    timed_out = 1;
    siglongjmp(timeout_env, 1);
}

char line[MAX_LINE_LENGTH];
char regex[MAX_LINE_LENGTH] = "";
char target[MAX_LINE_LENGTH];

int main(int argc, char *argv[]) {
    setvbuf(stdout, NULL, _IOLBF, 0);

    const char *text_path = TARGET_TEXT_PATH;
    size_t subset_char_limit = DEFAULT_SUBSET_SIZE;
    const char *pattern_file_path = "./sprints/002/patterns.txt";

    if (argc >= 2) {
        text_path = argv[1];
    }
    if (argc >= 3) {
        pattern_file_path = argv[2];
    }
    if (argc >= 4) {
        int val = atoi(argv[3]);
        if (val > 0) subset_char_limit = (size_t)val;
    }

    struct sigaction sa;
    sa.sa_handler = alarm_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGALRM, &sa, NULL);

    FILE *text_file = fopen(text_path, "r");
    if (!text_file) {
        fprintf(stderr, "[Error] Failed to open target text file: %s\n", text_path);
        return 1;
    }

    fseek(text_file, 0, SEEK_END);
    long file_size = ftell(text_file);
    if (file_size <= 0) file_size = MAX_SENTENCE_LENGTH;
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

    size_t subset_bytes = 0;
    size_t char_count = 0;
    while (large_text_buffer[subset_bytes] != '\0' && char_count < subset_char_limit) {
        unsigned char c = (unsigned char)large_text_buffer[subset_bytes];
        if (c < 0x80) subset_bytes += 1;
        else if ((c & 0xE0) == 0xC0) subset_bytes += 2;
        else if ((c & 0xF0) == 0xE0) subset_bytes += 3;
        else if ((c & 0xF8) == 0xF0) subset_bytes += 4;
        else subset_bytes += 1;
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
    free(large_text_buffer);

    printf("======================================\n");
    printf(" Loaded dataset: %s (%zu bytes)\n", text_path, read_bytes);
    printf(" Pattern file  : %s\n", pattern_file_path);
    printf(" Extracted subset: %zu characters (%zu bytes)\n", char_count, subset_bytes);
    printf("======================================\n\n");

    FILE *file = fopen(pattern_file_path, "r");
    if (!file) {
        perror("Failed to open pattern file");
        free(target_subset);
        return 1;
    }

    char output_csv[80];
    generate_csv_filename(output_csv, sizeof output_csv);
    
    FILE *csv_out = fopen(output_csv, "w");
    write_csv_header(csv_out);

    double case_start;
    double total_time = 0.0;

    while (fgets(line, sizeof(line), file)) {
        remove_trailing_newline(line);
        if (strlen(line) == 0 || line[0] == '#') continue;

        strncpy(regex, line, sizeof(regex) - 1);
        regex[sizeof(regex) - 1] = '\0';

        char post[MAX_LINE_LENGTH];
        re2post(regex, post);
        NFA *nfa = post2nfa(post);

        if (!nfa) {
            fprintf(stderr, "Skipped invalid regex: %s\n", regex);
            continue;
        }

        timed_out = 0;
        SearchResult res;
        case_start = now_sec();

        if (sigsetjmp(timeout_env, 1) == 0) {
            alarm(TIMEOUT_SECONDS);
            res = BENCHMARK_FN(nfa, target_subset, subset_bytes);
            alarm(0);
        } else {
            res = create_search_result();
            res.execution_time_sec = (double)TIMEOUT_SECONDS;
            printf("[TIMEOUT] Skipping case: %s\n", regex);
        }

        double case_elapsed = now_sec() - case_start;
        total_time += case_elapsed;

        write_csv_row(csv_out, regex, subset_bytes, &res);
        free_nfa(nfa);
    }

    fclose(file);
    fclose(csv_out);
    free(target_subset);

    printf("======================================\n");
    printf("Benchmark finished! Total Execution Time: %f sec\n", total_time);
    printf("Output -> %s\n", output_csv);
    printf("======================================\n");

    return 0;
}
