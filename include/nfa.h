/* nfa.h */
#ifndef NFA_H_
#define NFA_H_

#include "config.h"
#include <stddef.h>   /* size_t 用 */

typedef struct NFA NFA;          /* 前方宣言 (実体は nfa.c) */

/* 既存 API */
NFA   *nfa_compile(const char *regex);
int    nfa_test(const NFA *nfa, const char *text);
void   nfa_free(NFA *nfa);

/* ← 追加したいプロトタイプ */
size_t nfa_grep_idx(const NFA         *nfa,
                    const char *const *list,
                    size_t             n,
                    size_t            *out_idx);

size_t nfa_grep_idx_arr(
        const NFA *nfa,
        const char list[][MAX_LINE_LENGTH],
        size_t     n,
        size_t    *out_idx);

#endif /* NFA_H_ */
