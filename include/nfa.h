/* nfa.h */
#pragma once

#include "config.h"
#include <stddef.h>   /* size_t 用 */

typedef struct NFA NFA;          /* 前方宣言 (実体は nfa.c) */

/* -- NFA Graph Construction (CPU/GPU 共通) -- */
enum
{
    Match = 256,
    Split = 257,
    Any   = 258,
};

typedef struct State State;
struct State
{
    int c; // 遷移する文字。Match, Split, Anyは特殊な文字として扱う。
    State *out; // 次にどのStateに行くか。Stateのポインタが入る。
    State *out1; // 分岐がある場合、もう一つのStateのポインタが入る。正規表現は2つの分岐で表現できるはずなので、out1まであれば十分。
    int lastlist; // NFA探索時（実行時）に同じStateが重複してリストに登録されたり、無限ループに陥るのを防ぐための「訪問済マーカー（世代ID）」。
};

extern State matchstate;
extern int nstate;

State *post2nfa(char *postfix);

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
