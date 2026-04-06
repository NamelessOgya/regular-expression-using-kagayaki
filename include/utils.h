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



