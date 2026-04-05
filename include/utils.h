#pragma once

#include <stdio.h>
#include <stddef.h>

#include "config.h"

// ユーティリティ関数のプロトタイプ宣言

void get_jst_timestamp(char *buffer, size_t size);
double now_sec(void);
void remove_trailing_newline(char *s);
void write_csv_header(FILE *file);
void generate_csv_filename(char *filename, size_t size);
size_t split_csv_static(char *line, char *regex, char *target, size_t buflen);
size_t split_str_to_array(const char *src, char lines[][MAX_LINE_LENGTH]);
int join_matches(char *result, size_t cap, const char list[][MAX_RESULT_LENGTH], const size_t *idx, size_t n);


