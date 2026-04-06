/* nfa.h */
#pragma once

#include "config.h"
#include <stddef.h>   /* size_t 用 */

typedef struct NFA NFA;          /* 前方宣言 (実体は nfa.c) */

/* 既存 API */
NFA   *nfa_compile(const char *regex);
int    nfa_test(const NFA *nfa, const char *text);
void   nfa_free(NFA *nfa);

/* 新しい直列検索用 API */
int nfa_search(const NFA *nfa, const char *text);

/* 
 * Regex Parser (CPU/GPU共通)
 * 中置記法の正規表現を逆ポーランド記法(後置表現)に変換する
 */
char* re2post(char *re);
