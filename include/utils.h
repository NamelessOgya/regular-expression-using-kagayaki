#pragma once

#include <stdio.h>
#include <stddef.h>

#include "config.h"

struct NFA;

#ifdef __cplusplus
extern "C" {
#endif

// 検索エンジンの抽象化用のデータ構造
typedef struct {
    int line_number;     // マッチした元の行番号 (1-indexed)
    char *line_content;  // マッチした行の内容（動的確保によるコピー）
} MatchItem;

typedef struct {
    MatchItem *items;    // マッチ項目的動的配列
    size_t count;        // マッチした総件数
    size_t capacity;     // 動的配列の確保容量
} SearchResult;

SearchResult create_search_result(void);
void free_search_result(SearchResult *result);
void add_match_item(SearchResult *result, int line_number, const char *content);

SearchResult gpu_line_parallel(struct NFA *nfa, const char *text, size_t text_bytes);
SearchResult gpu_chunk_parallel(struct NFA *nfa, const char *text, size_t text_bytes);

SearchResult search_engine_execute(
    const char *strategy,
    struct NFA *nfa,
    const char *text,
    size_t text_bytes
);

// ユーティリティ関数のプロトタイプ宣言

void get_jst_timestamp(char *buffer, size_t size);
double now_sec(void);
void remove_trailing_newline(char *s);
void write_csv_header(FILE *file);
void generate_csv_filename(char *filename, size_t size);
size_t split_csv_static(char *line, char *regex, char *target, size_t buflen);

#ifdef __cplusplus
}
#endif



