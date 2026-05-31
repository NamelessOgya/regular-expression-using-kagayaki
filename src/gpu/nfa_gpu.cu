/* =======================================================================
 *  src/gpu/nfa_gpu.cu
 *  Thompson‑NFA 正規表現マッチャ (GPU高速化版)
 *  -------------------------------------------------
 *  このファイルは、NVIDIA GPU (CUDA) を利用して Thompson NFA 正規表現検索を
 *  爆速並列化するための実装ファイルです。
 *  
 *  以下の2つの並列化アプローチを実装し、それぞれの特長・設計意図について
 *  初学者にも分かりやすいよう、丁寧な解説コメントを付与しています。
 * 
 *  1. 「単純なGPU利用」 (改行 \n で区切った論理行単位でのスレッド並列)
 *  2. 「長さが同じチャンク同士の並列」 (固定長チャンク + 境界重ね合わせによるWarp最適並列)
 * =======================================================================*/

#include <cuda_runtime.h>
#include <vector>
#include <unordered_map>
#include <iostream>
#include <cstring>
#include <algorithm>

#include "nfa.h"
#include "utils.h"
#ifndef GPU_RUN
#include "nfa_cpu_common.h"
#endif

/* --------------------------- GPU用状態構造体 --------------------------- */
/**
 * GPUのグローバルメモリ（または定数バッファ）に転送するための、
 * NFA状態（State）の線形化（シリアライズ）構造体です。
 * ポインタ参照（State*）をデバイス上で直接扱えないため、連番インデックス（int）に変換しています。
 */
struct GPUState {
    int c;        // 遷移する文字 (または Match = 256, Split = 257, Any = 258)
    int out;      // 遷移先状態1のインデックス (-1 の場合は遷移先なし)
    int out1;     // 遷移先状態2のインデックス (-1 の場合は遷移先なし)
    int lastlist; // GPUカーネル内では使用せず（0固定）。代わりにスレッドローカル配列で重複排除します。
};

/* -------------------- NFA を線形化するユーティリティ ----------------- */
static std::vector<State*>            order;     // 深さ優先探索 (DFS) 順の状態配列
static std::unordered_map<State*,int> idx_map;   // Stateポインタから配列インデックスへの逆引きマップ

/**
 * CPU側で構築された複雑なNFAグラフを辿り、すべての状態ノードを
 * 順番に配列（ベクトル）に登録して「フラット（線形）な状態テーブル」を作成します。
 */
void gather_states(State* s)
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
inline int idx_of(State* s) { return s ? idx_map.at(s) : -1; }


/* =======================================================================
 *  CUDA カーネル補助デバイス関数 (スレッドローカル走査)
 * =======================================================================*/

/**
 * 【超重要: スレッドローカルでの重複遷移防止とε遷移探索】
 * 
 * 状態 idx から文字を消費せずに進める範囲（ε遷移 / Split）を再帰的に辿り、
 * アクティブ状態リスト（list）に登録します。
 * 
 * [初心者向け解説]
 * - CPU版ではグローバル変数 `listid` や状態構造体のメンバ `lastlist` を書き換えて重複チェックを
 *   行っていましたが、GPU上で数千〜数万のスレッドが同時に実行される場合、共有メモリを直接書き換えると
 *   競合（データレース）が発生します。
 * - これを防ぐため、各スレッド自身が持つスレッドローカル（レジスタ/ローカルスタック）上の配列 `visited`
 *   を利用し、一切の排他制御なしで安全・超高速に重複排除を行っています。
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


/* =======================================================================
 *  アプローチ 1: 「単純なGPU利用」 (改行 \n で区切った論理行並列)
 * =======================================================================*/

/**
 * 1スレッド ＝ 1行 を担当し、行単位で並列に NFA 部分一致（Substring Search）を実行するカーネル。
 * 
 * [初心者向け解説]
 * - 最も直感的でシンプルなGPU実装モデルです。
 * - しかし、Wikipediaデータセットプロファイリング結果にあるように、「1文字だけの行」と「4,000文字の行」が
 *   混在しているため、同じWarp（32スレッド）内で一番長い行の走査が終わるまで他の31個のスレッドがすべて
 *   アイドリング状態で待機し続けることになり、GPUコアの実行効率（Warp効率）に課題があります。
 */
__global__ void gpu_line_match_kernel(
    const GPUState* d_states,  // GPU上の線形化NFA状態配列
    const char* d_texts,       // テキストバッファ全体へのポインタ
    const int* d_off,          // 各行のテキスト開始オフセット配列 (バイト位置)
    const int* d_len,          // 各行の長さ配列 (バイト数)
    int n_lines,               // 総行数
    int* d_res                 // マッチ結果格納配列 (0: マッチなし, 1: マッチあり)
) {
    // 自分のスレッドIDを計算
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n_lines) return;

    // 自分が担当する行の先頭ポインタと長さを取得
    const char* str = d_texts + d_off[tid];
    int len = d_len[tid];

    // スレッドローカルに十分な状態リスト容量（最大256状態）を静的に確保
    // これにより、動的メモリ確保 (malloc) なしでハードウェアレジスタをフル活用できます
    int clist[256], nlist[256];
    int n_c = 0, n_n = 0;
    bool visited[256];

    // 初期化：すべての訪問フラグをクリア
    for (int j = 0; j < 256; ++j) visited[j] = false;
    
    // NFAの開始位置 (0番) からスタート
    add_state_local(clist, n_c, d_states, 0, visited);

    int matched = 0;
    
    // 空文字列時点でマッチ可能（例: 空文字にマッチするパターン）か確認
    for (int i = 0; i < n_c; ++i) {
        if (d_states[clist[i]].c == Match) {
            matched = 1;
            break;
        }
    }

    // 担当する行のテキストを1文字ずつ走査する (シングルパス O(L) 探索)
    for (int pos = 0; pos < len && !matched; ++pos) {
        char ch = str[pos];
        n_n = 0;
        
        // 遷移ごとに訪問状態テーブルをリセット
        for (int j = 0; j < 256; ++j) visited[j] = false;

        // 現在アクティブな全状態について、文字 ch にマッチする遷移先があるか検査
        for (int i = 0; i < n_c; ++i) {
            const GPUState& st = d_states[clist[i]];
            if (st.c == static_cast<unsigned char>(ch) || (st.c == 258 /* Any wildcard */ && ch != '\n')) {
                add_state_local(nlist, n_n, d_states, st.out, visited);
            }
        }

        // 【超重要】サブストリング・マッチ（部分一致）を実現するため、
        // 毎ステップテキストの「現在位置」から新しいマッチを開始できるように start(0) を追加します！
        add_state_local(nlist, n_n, d_states, 0, visited);

        // clist と nlist をスワップ
        n_c = n_n;
        for (int i = 0; i < n_c; ++i) clist[i] = nlist[i];

        // 受理状態（Match）に到達したスレッドが1つでもあれば、その時点で部分一致成功！
        for (int i = 0; i < n_c; ++i) {
            if (d_states[clist[i]].c == Match) {
                matched = 1;
                break; // 早期リターン
            }
        }
    }

    // 結果を書き込み
    d_res[tid] = matched;
}


/* =======================================================================
 *  アプローチ 2: 「長さが同じチャンク同士の並列」 (均等チャンク + 重ね合わせ)
 * =======================================================================*/

/**
 * テキストを一律の固定サイズ（CHUNK_SIZE）に分割し、1スレッド ＝ 1チャンク を担当して走査するカーネル。
 * 
 * [初心者向け解説]
 * - この方法では、すべてのスレッドが全く同じサイズ（例: 2048文字）のループを並列実行するため、
 *   Warp内の全スレッドが同一の進行速度で命令を実行でき、アイドリング待機（Load Imbalance）が極限まで減少します。
 * - スレッド間でまたがる文字（境界を跨いだパターン）の取りこぼしを防ぐため、
 *   各スレッドは自分のチャンクの後ろ側にある `overlap_size` バイト分も重ね合わせてスキャンします。
 * - マッチしたスレッドは、マッチした「絶対バイト位置（global_match_idx）」を書き込みます。
 */
__global__ void gpu_chunk_match_kernel(
    const GPUState* d_states,  // GPU上の線形化NFA状態配列
    const char* d_texts,       // テキストバッファ全体へのポインタ
    size_t text_bytes,         // テキストの総バイト長
    size_t chunk_size,         // 1チャンクあたりの基準バイトサイズ (例: 2048)
    size_t overlap_size,       // 重ね合わせ境界幅 (例: 128)
    int n_chunks,              // 総チャンク（スレッド）数
    long long* d_res           // マッチした絶対バイト位置を格納する配列 (マッチなしは -1)
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n_chunks) return;

    // 自分のチャンクの開始位置を算出
    size_t start_idx = tid * chunk_size;
    if (start_idx >= text_bytes) {
        d_res[tid] = -1;
        return;
    }

    // 重ね合わせを含んだスキャン終了位置を決定
    size_t end_idx = start_idx + chunk_size + overlap_size;
    if (end_idx > text_bytes) {
        end_idx = text_bytes;
    }

    // スキャン対象範囲のポインタと長さを取得
    const char* str = d_texts + start_idx;
    size_t len = end_idx - start_idx;

    int clist[256], nlist[256];
    int n_c = 0, n_n = 0;
    bool visited[256];

    for (int j = 0; j < 256; ++j) visited[j] = false;
    add_state_local(clist, n_c, d_states, 0, visited);

    long long matched_idx = -1;

    // 初期状態で即マッチするか確認
    for (int i = 0; i < n_c; ++i) {
        if (d_states[clist[i]].c == Match) {
            matched_idx = start_idx;
            break;
        }
    }

    // 1文字ずつ走査 (シングルパス O(L) 部分一致)
    for (size_t pos = 0; pos < len && matched_idx == -1; ++pos) {
        char ch = str[pos];

        if (ch == '\n') {
            // 改行文字に達した場合、行境界を跨いだ遷移を完全に遮断します！
            // アクティブ状態リストを初期状態 (0) のみにリセットし、過去の行の進行状態をクリアします。
            n_c = 0;
            for (int j = 0; j < 256; ++j) visited[j] = false;
            add_state_local(clist, n_c, d_states, 0, visited);
            continue; // 改行自体の文字遷移は行いません
        }

        n_n = 0;
        for (int j = 0; j < 256; ++j) visited[j] = false;

        for (int i = 0; i < n_c; ++i) {
            const GPUState& st = d_states[clist[i]];
            // ワイルドカード Any (258) も、改行文字ではない場合にのみ遷移を許可します（本家 grep 準拠）
            if (st.c == static_cast<unsigned char>(ch) || (st.c == 258 /* Any */ && ch != '\n')) {
                add_state_local(nlist, n_n, d_states, st.out, visited);
            }
        }

        // サブストリング対応のための start(0) 追加
        add_state_local(nlist, n_n, d_states, 0, visited);

        n_c = n_n;
        for (int i = 0; i < n_c; ++i) clist[i] = nlist[i];

        // 受理状態到達チェック
        for (int i = 0; i < n_c; ++i) {
            if (d_states[clist[i]].c == Match) {
                // テキスト全体の「絶対バイトインデックス」を計算して書き込み、即座にループを抜ける
                matched_idx = start_idx + pos;
                break;
            }
        }
    }

    d_res[tid] = matched_idx;
}


/* =======================================================================
 *  extern "C" ホスト側ラッパー関数群 (CPU/C言語側からの呼び出し窓口)
 * =======================================================================*/

extern "C" {

/**
 * アプローチ 1 (行並列) のホスト側実行API
 */
SearchResult gpu_line_parallel(struct NFA *nfa, const char *text, size_t text_bytes) {
    SearchResult result = create_search_result();
    if (!text || text_bytes == 0) return result;

    // 1. テキストを改行 '\n' で走査し、行ごとのオフセットと長さの配列をCPU上に用意します
    std::vector<int> h_off;
    std::vector<int> h_len;
    std::vector<const char*> line_ptrs;

    const char* current_line = text;
    const char* text_end = text + text_bytes;

    while (current_line < text_end) {
        const char* next_line = (const char*)memchr(current_line, '\n', text_end - current_line);
        size_t len;
        if (next_line) {
            len = next_line - current_line;
        } else {
            len = text_end - current_line;
        }

        h_off.push_back(current_line - text);
        h_len.push_back(static_cast<int>(len));
        line_ptrs.push_back(current_line);

        if (next_line) {
            current_line = next_line + 1;
        } else {
            break;
        }
    }

    int n_lines = static_cast<int>(h_off.size());
    if (n_lines == 0) return result;

    // 2. NFA 状態ポインタを DFS で探索し、フラットな GPUState 配列を作成します
    order.clear();
    idx_map.clear();
    gather_states(nfa->start);

    std::vector<GPUState> h_states(order.size());
    for (size_t i = 0; i < order.size(); ++i) {
        State* s = order[i];
        h_states[i] = { s->c, idx_of(s->out), idx_of(s->out1), 0 };
    }

    // 3. GPU デバイスメモリの確保とホストデータの転送 (HtoD)
    GPUState* d_states;
    char*     d_texts;
    int*      d_off;
    int*      d_len;
    int*      d_res;

    cudaMalloc(&d_states, h_states.size() * sizeof(GPUState));
    cudaMalloc(&d_texts,  text_bytes);
    cudaMalloc(&d_off,    n_lines * sizeof(int));
    cudaMalloc(&d_len,    n_lines * sizeof(int));
    cudaMalloc(&d_res,    n_lines * sizeof(int));

    cudaMemcpy(d_states, h_states.data(), h_states.size() * sizeof(GPUState), cudaMemcpyHostToDevice);
    cudaMemcpy(d_texts,  text,            text_bytes,                       cudaMemcpyHostToDevice);
    cudaMemcpy(d_off,    h_off.data(),    n_lines * sizeof(int),            cudaMemcpyHostToDevice);
    cudaMemcpy(d_len,    h_len.data(),    n_lines * sizeof(int),            cudaMemcpyHostToDevice);

    // 4. CUDA カーネルをグリッド起動 (1ブロック辺り 256 スレッドで並列化)
    int threads = 256;
    int blocks  = (n_lines + threads - 1) / threads;
        gpu_line_match_kernel<<<blocks, threads>>>(d_states, d_texts, d_off, d_len, n_lines, d_res);
    
    // カーネルの実行完了をCPU側で同期して待機します
    cudaDeviceSynchronize();
    {
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA Error (Line Parallel): %s\n", cudaGetErrorString(err));
        }
    }

    // 5. 結果データをデバイスからホストへ回収 (DtoH)
    std::vector<int> h_res(n_lines);
    cudaMemcpy(h_res.data(), d_res, n_lines * sizeof(int), cudaMemcpyDeviceToHost);

    // 6. マッチした行を SearchResult に詰め込みます
    for (int i = 0; i < n_lines; ++i) {
        if (h_res[i]) {
            int len = h_len[i];
            char* line_buf = (char*)malloc(len + 1);
            memcpy(line_buf, line_ptrs[i], len);
            line_buf[len] = '\0';
            
            add_match_item(&result, i + 1, line_buf);
            free(line_buf);
        }
    }

    // 7. GPUメモリの解放
    cudaFree(d_states);
    cudaFree(d_texts);
    cudaFree(d_off);
    cudaFree(d_len);
    cudaFree(d_res);

    return result;
}


/**
 * アプローチ 2 (固定長チャンク並列) のホスト側実行API
 */
SearchResult gpu_chunk_parallel(struct NFA *nfa, const char *text, size_t text_bytes) {
    SearchResult result = create_search_result();
    if (!text || text_bytes == 0) return result;

    // 1. 各論理行の開始インデックステーブルを構築 (後でマッチ絶対位置から行番号を「高速逆引き」するため)
    std::vector<size_t> line_starts;
    std::vector<size_t> line_lens;
    
    const char* current_line = text;
    const char* text_end = text + text_bytes;
    while (current_line < text_end) {
        const char* next_line = (const char*)memchr(current_line, '\n', text_end - current_line);
        size_t len;
        if (next_line) {
            len = next_line - current_line;
        } else {
            len = text_end - current_line;
        }
        line_starts.push_back(current_line - text);
        line_lens.push_back(len);

        if (next_line) {
            current_line = next_line + 1;
        } else {
            break;
        }
    }

    // 2. チャンクサイズと重ね合わせのパラメータ決定
    const size_t CHUNK_SIZE = 2048;      // Warpの実行を揃える均一チャンクサイズ
    const size_t OVERLAP_SIZE = 128;     // 境界跨ぎを完全に吸収する重ね合わせ境界幅
    int n_chunks = (text_bytes + CHUNK_SIZE - 1) / CHUNK_SIZE;

    // 3. NFA 状態配列の作成
    order.clear();
    idx_map.clear();
    gather_states(nfa->start);

    std::vector<GPUState> h_states(order.size());
    for (size_t i = 0; i < order.size(); ++i) {
        State* s = order[i];
        h_states[i] = { s->c, idx_of(s->out), idx_of(s->out1), 0 };
    }

    // 4. GPU メモリの確保と転送
    GPUState* d_states;
    char*     d_texts;
    long long* d_res;

    cudaMalloc(&d_states, h_states.size() * sizeof(GPUState));
    cudaMalloc(&d_texts,  text_bytes);
    cudaMalloc(&d_res,    n_chunks * sizeof(long long));

    cudaMemcpy(d_states, h_states.data(), h_states.size() * sizeof(GPUState), cudaMemcpyHostToDevice);
    cudaMemcpy(d_texts,  text,            text_bytes,                       cudaMemcpyHostToDevice);

    // 5. CUDA カーネル起動 (チャンク並列)
    int threads = 256;
    int blocks  = (n_chunks + threads - 1) / threads;
    gpu_chunk_match_kernel<<<blocks, threads>>>(d_states, d_texts, text_bytes, CHUNK_SIZE, OVERLAP_SIZE, n_chunks, d_res);
    cudaDeviceSynchronize();
    {
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess) {
            fprintf(stderr, "CUDA Error (Chunk Parallel): %s\n", cudaGetErrorString(err));
        }
    }

    // 6. 結果の回収と「高速逆引き行特定」
    std::vector<long long> h_res(n_chunks);
    cudaMemcpy(h_res.data(), d_res, n_chunks * sizeof(long long), cudaMemcpyDeviceToHost);

    // 同一行が複数チャンクで重なって重複マッチするのを防ぐためのユニークセット
    std::vector<bool> matched_lines(line_starts.size(), false);

    for (int i = 0; i < n_chunks; ++i) {
        long long match_pos = h_res[i];
        if (match_pos >= 0 && match_pos < (long long)text_bytes) {
            // [ハイブリッド技術] 二分探索 (std::upper_bound) を用いて、
            // チャンク内で検出されたマッチ絶対バイト位置が「元のテキストの何行目に該当するか」を O(log N) で超高速逆引き特定！
            auto it = std::upper_bound(line_starts.begin(), line_starts.end(), (size_t)match_pos);
            int line_idx = std::distance(line_starts.begin(), it) - 1;
            
            if (line_idx >= 0 && line_idx < (int)line_starts.size() && !matched_lines[line_idx]) {
                matched_lines[line_idx] = true;
                
                size_t start = line_starts[line_idx];
                size_t len = line_lens[line_idx];
                
                char* line_buf = (char*)malloc(len + 1);
                memcpy(line_buf, text + start, len);
                line_buf[len] = '\0';
                
                // 行番号と文字列を結果に追加
                add_match_item(&result, line_idx + 1, line_buf);
                free(line_buf);
            }
        }
    }

    // 7. デバイスメモリ解放
    cudaFree(d_states);
    cudaFree(d_texts);
    cudaFree(d_res);

    return result;
}

} // extern "C"


/* =======================================================================
 *  元々実装されていたスタンドアロン実行用の main 関数
 *  ---------------------------------------------------------------------
 *  GPU_RUN マクロが定義されていない（＝単体のテストバイナリとしてコンパイルする）
 *  場合のみ有効にし、統合ベンチマーク実行時の多重 main 定義エラーを防ぎます。
 * =======================================================================*/
#ifndef GPU_RUN

int main(int argc, char** argv)
{
    if (argc < 3) {
        std::cerr << "usage: nfa regexp string...\n";
        return 1;
    }
    
    char* post = re2post(argv[1]);
    if (!post) { std::cerr << "bad regexp\n"; return 1; }

    State* start = post2nfa(post);
    if (!start) { std::cerr << "post2nfa failed\n"; return 1; }

    gather_states(start);

    std::vector<GPUState> h_states(order.size());
    for (size_t i = 0; i < order.size(); ++i) {
        State* s = order[i];
        h_states[i] = { s->c, idx_of(s->out), idx_of(s->out1), 0 };
    }

    const int n_inputs = argc - 2;
    std::vector<int>  h_off(n_inputs), h_len(n_inputs);
    size_t total_bytes = 0;
    for (int i = 0; i < n_inputs; ++i) {
        h_off[i] = total_bytes;
        h_len[i] = static_cast<int>(strlen(argv[i+2]));
        total_bytes += h_len[i];
    }
    std::vector<char> h_texts(total_bytes);
    for (int i = 0; i < n_inputs; ++i)
        memcpy(h_texts.data() + h_off[i], argv[i+2], h_len[i]);

    GPUState* d_states;  cudaMalloc(&d_states, h_states.size()*sizeof(GPUState));
    char*     d_texts;   cudaMalloc(&d_texts,  total_bytes);
    int*      d_off;     cudaMalloc(&d_off,    n_inputs*sizeof(int));
    int*      d_len;     cudaMalloc(&d_len,    n_inputs*sizeof(int));
    int*      d_res;     cudaMalloc(&d_res,    n_inputs*sizeof(int));

    cudaMemcpy(d_states, h_states.data(), h_states.size()*sizeof(GPUState), cudaMemcpyHostToDevice);
    cudaMemcpy(d_texts , h_texts.data() , total_bytes, cudaMemcpyHostToDevice);
    cudaMemcpy(d_off   , h_off.data()   , n_inputs*sizeof(int), cudaMemcpyHostToDevice);
    cudaMemcpy(d_len   , h_len.data()   , n_inputs*sizeof(int), cudaMemcpyHostToDevice);

    int threads = 256;
    int blocks  = (n_inputs + threads - 1) / threads;
    
    // 単体実行時はシンプルな行並列マッチングカーネルを起動
    gpu_line_match_kernel<<<blocks, threads>>>(d_states, d_texts, d_off, d_len, n_inputs, d_res);
    cudaDeviceSynchronize();

    std::vector<int> h_res(n_inputs);
    cudaMemcpy(h_res.data(), d_res, n_inputs*sizeof(int), cudaMemcpyDeviceToHost);

    for (int i = 0; i < n_inputs; ++i)
        if (h_res[i]) printf("%s\n", argv[i+2]);

    cudaFree(d_states); cudaFree(d_texts);
    cudaFree(d_off);    cudaFree(d_len); cudaFree(d_res);
    
    return 0;
}

#endif // GPU_RUN