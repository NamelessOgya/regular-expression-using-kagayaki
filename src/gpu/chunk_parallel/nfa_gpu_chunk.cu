/* nfa_gpu_chunk.cu */
#include "nfa_gpu_common.h"
#include <algorithm>

/**
 * テキストを一律の固定サイズ（CHUNK_SIZE）に分割し、1スレッド ＝ 1チャンク を担当して走査するカーネル。
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

extern "C" {

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
