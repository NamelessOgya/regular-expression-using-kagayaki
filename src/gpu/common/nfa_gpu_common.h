/* nfa_gpu_common.h */
#ifndef NFA_GPU_COMMON_H
#define NFA_GPU_COMMON_H

#include <vector>
#include <unordered_map>
#include "nfa.h"
#include "utils.h"

// GPU上で高速処理を行うための軽量なフラット状態構造体
struct GPUState {
    int c;          // 遷移する文字。Match=256, Split=257, Any=258
    int out;        // 遷移先状態インデックス (無効は -1)
    int out1;       // 分岐がある場合のもう一つの遷移先状態インデックス (無効は -1)
    int lastlist;   // CPU互換用ダミープレースホルダ
};

// スレッドセーフかつ重複排除のための線形化グラフ構築用静的バッファ
static std::vector<State*> order;
static std::unordered_map<State*, int> idx_map;

/**
 * CPU側で構築された複雑なNFAグラフを辿り、すべての状態ノードを
 * 順番に配列（ベクトル）に登録して「フラット（線形）な状態テーブル」を作成します。
 */
static inline void gather_states(State* s)
{
    if (!s || idx_map.count(s)) return;
    int id = static_cast<int>(order.size());
    idx_map[s] = id;
    order.push_back(s);

    if (s->out ) gather_states(s->out );
    if (s->out1) gather_states(s->out1);
}

/**
 * 特定の状態ポインタが、線形化テーブルの何番目にあるかを返します。
 */
static inline int idx_of(State* s) { return s ? idx_map.at(s) : -1; }

/**
 * 【超重要: スレッドローカルでの重複遷移防止とε遷移探索】
 * 
 * 状態 idx から文字を消費せずに進める範囲（ε遷移 / Split）を反復的に辿り、
 * アクティブ状態リスト（list）に登録します。
 */
__device__ __forceinline__
void add_state_local(int* list, int& n, const GPUState* d_states,
                     int idx, bool* visited)
{
    if (idx < 0) return;

    // スレッドローカルの探索キュー (レジスタ・スタック上に配置)
    int queue[256];
    int q_head = 0;
    int q_tail = 0;

    // 開始状態をキューに投入し、訪問済みにマーク
    queue[q_tail++] = idx;
    visited[idx] = true;

    while (q_head < q_tail) {
        int curr = queue[q_head++];
        const GPUState& st = d_states[curr];

        if (st.c == Split) {
            // 文字を消費しない「Split」状態の場合、遷移先 (out と out1) を探索キューに投入
            if (st.out >= 0 && !visited[st.out]) {
                visited[st.out] = true;
                queue[q_tail++] = st.out;
            }
            if (st.out1 >= 0 && !visited[st.out1]) {
                visited[st.out1] = true;
                queue[q_tail++] = st.out1;
            }
        } else {
            // 通常の文字判定状態（または Match/Any）に到達した場合、アクティブ状態リストに追加
            list[n++] = curr;
        }
    }
}

#endif // NFA_GPU_COMMON_H
