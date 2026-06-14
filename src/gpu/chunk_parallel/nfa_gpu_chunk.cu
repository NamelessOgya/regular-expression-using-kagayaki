/* nfa_gpu_chunk.cu - 行グループ並列版 */
/*
 * 1スレッド = 複数行（LINES_PER_CHUNK 行）を担当し、チャンク内の全行を
 * 順番に NFA マッチする。
 *
 * line_parallel との違い:
 *   line_parallel  : 1スレッド / 1行   → n_lines スレッド（最大並列度）
 *   chunk_parallel : 1スレッド / N行   → n_lines/N スレッド（スレッド数削減、逐次量増加）
 *
 * この粒度の違いが GPU の性能にどう影響するかを比較するのがこの実装の研究的意義。
 */
#include "nfa_gpu_common.h"
#include "utils.h"
#include <algorithm>

/* 1スレッドが担当する行数 (コンパイル時に -DLINES_PER_CHUNK=N で上書き可能) */
#ifndef LINES_PER_CHUNK
#define LINES_PER_CHUNK 8
#endif

/**
 * チャンク（行グループ）ごとに並列 NFA マッチを行うカーネル。
 * 各スレッドは d_chunk_line_start[tid] 〜 d_chunk_line_end[tid] の行を処理する。
 */
__global__ void gpu_chunk_match_kernel(
    const GPUState* d_states,          // GPU 上の線形化 NFA 状態配列
    const char*     d_texts,           // テキストバッファ全体
    const int*      d_off,             // 各行の開始バイトオフセット
    const int*      d_len,             // 各行の長さ
    const int*      d_chunk_line_start,// チャンク tid の担当開始行インデックス
    const int*      d_chunk_line_end,  // チャンク tid の担当終了行インデックス (exclusive)
    int             n_chunks,
    int*            d_line_matched     // 出力: 行ごとのマッチフラグ (0/1)
) {
    int tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= n_chunks) return;

    int ls = d_chunk_line_start[tid];
    int le = d_chunk_line_end[tid];

    /* チャンク内の各行を順番に NFA で処理する */
    for (int li = ls; li < le; li++) {
        const char* str = d_texts + d_off[li];
        int len = d_len[li];

        int clist[256], nlist[256];
        int n_c = 0, n_n = 0;
        bool visited[256];

        for (int j = 0; j < 256; ++j) visited[j] = false;
        add_state_local(clist, n_c, d_states, 0, visited);

        int matched = 0;

        /* 空文字列でマッチするか確認 */
        for (int i = 0; i < n_c; ++i)
            if (d_states[clist[i]].c == Match) { matched = 1; break; }

        /* 1文字ずつ走査（部分一致 O(L×m) Thompson NFA） */
        for (int pos = 0; pos < len && !matched; ++pos) {
            char ch = str[pos];
            n_n = 0;
            for (int j = 0; j < 256; ++j) visited[j] = false;

            for (int i = 0; i < n_c; ++i) {
                const GPUState& st = d_states[clist[i]];
                if (st.c == static_cast<unsigned char>(ch) ||
                    (st.c == 258 /* Any */ && ch != '\n'))
                    add_state_local(nlist, n_n, d_states, st.out, visited);
            }
            /* サブストリング対応のため start(0) を毎ステップ追加 */
            add_state_local(nlist, n_n, d_states, 0, visited);

            n_c = n_n;
            for (int i = 0; i < n_c; ++i) clist[i] = nlist[i];

            for (int i = 0; i < n_c; ++i)
                if (d_states[clist[i]].c == Match) { matched = 1; break; }
        }

        d_line_matched[li] = matched;
    }
}

extern "C" {

/**
 * アプローチ 2 (行グループ並列 / Chunk-Parallel) のホスト側実行 API
 *
 * - テキストを LINES_PER_CHUNK 行ずつのチャンクに分割
 * - 1 CUDA スレッドが 1 チャンク（複数行）を担当
 * - 全行を正確に処理するため、マッチ数は line-parallel と一致する
 */
SearchResult gpu_chunk_parallel(struct NFA *nfa, const char *text, size_t text_bytes) {
    SearchResult result = create_search_result();
    if (!text || text_bytes == 0) return result;

    double t0 = now_sec();

    /* 1. 行分割 */
    std::vector<int>        h_off;
    std::vector<int>        h_len;
    std::vector<const char*> line_ptrs;

    const char* cur  = text;
    const char* tend = text + text_bytes;

    while (cur < tend) {
        const char* nl = (const char*)memchr(cur, '\n', tend - cur);
        size_t len = nl ? (size_t)(nl - cur) : (size_t)(tend - cur);
        h_off.push_back((int)(cur - text));
        h_len.push_back((int)len);
        line_ptrs.push_back(cur);
        cur = nl ? nl + 1 : tend;
        if (!nl) break;
    }

    int n_lines = (int)h_off.size();
    if (n_lines == 0) return result;

    /* 2. チャンク分割: LINES_PER_CHUNK 行ずつ 1 スレッドに割り当てる */
    int n_chunks = (n_lines + LINES_PER_CHUNK - 1) / LINES_PER_CHUNK;
    std::vector<int> h_chunk_ls(n_chunks), h_chunk_le(n_chunks);
    for (int c = 0; c < n_chunks; c++) {
        h_chunk_ls[c] = c * LINES_PER_CHUNK;
        h_chunk_le[c] = std::min((c + 1) * LINES_PER_CHUNK, n_lines);
    }

    double t1 = now_sec();

    /* 3. NFA 状態配列の作成 */
    order.clear();
    idx_map.clear();
    gather_states(nfa->start);

    std::vector<GPUState> h_states(order.size());
    for (size_t i = 0; i < order.size(); ++i) {
        State* s = order[i];
        h_states[i] = { s->c, idx_of(s->out), idx_of(s->out1), 0 };
    }

    /* 4. GPU メモリの確保と転送 */
    GPUState* d_states;
    char*     d_texts;
    int*      d_off_gpu;
    int*      d_len_gpu;
    int*      d_chunk_ls_gpu;
    int*      d_chunk_le_gpu;
    int*      d_line_matched;

    cudaMalloc(&d_states,       h_states.size() * sizeof(GPUState));
    cudaMalloc(&d_texts,        text_bytes);
    cudaMalloc(&d_off_gpu,      n_lines  * sizeof(int));
    cudaMalloc(&d_len_gpu,      n_lines  * sizeof(int));
    cudaMalloc(&d_chunk_ls_gpu, n_chunks * sizeof(int));
    cudaMalloc(&d_chunk_le_gpu, n_chunks * sizeof(int));
    cudaMalloc(&d_line_matched, n_lines  * sizeof(int));

    cudaMemcpy(d_states,       h_states.data(),   h_states.size() * sizeof(GPUState), cudaMemcpyHostToDevice);
    cudaMemcpy(d_texts,        text,               text_bytes,                         cudaMemcpyHostToDevice);
    cudaMemcpy(d_off_gpu,      h_off.data(),       n_lines  * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemcpy(d_len_gpu,      h_len.data(),       n_lines  * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemcpy(d_chunk_ls_gpu, h_chunk_ls.data(),  n_chunks * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemcpy(d_chunk_le_gpu, h_chunk_le.data(),  n_chunks * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemset(d_line_matched, 0, n_lines * sizeof(int));

    /* 5. カーネル起動 (1ブロックあたり 256 スレッド) */
    int threads = 256;
    int blocks  = (n_chunks + threads - 1) / threads;
    gpu_chunk_match_kernel<<<blocks, threads>>>(
        d_states, d_texts, d_off_gpu, d_len_gpu,
        d_chunk_ls_gpu, d_chunk_le_gpu, n_chunks, d_line_matched
    );
    cudaDeviceSynchronize();
    {
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess)
            fprintf(stderr, "CUDA Error (Chunk Parallel): %s\n", cudaGetErrorString(err));
    }

    /* 6. 結果の回収 */
    std::vector<int> h_line_matched(n_lines);
    cudaMemcpy(h_line_matched.data(), d_line_matched, n_lines * sizeof(int), cudaMemcpyDeviceToHost);

    /* 7. SearchResult への格納（最初の MAX_STORED_MATCHES 件のみ内容を保存） */
    for (int i = 0; i < n_lines; ++i) {
        if (h_line_matched[i]) {
            if (result.stored_count < MAX_STORED_MATCHES) {
                int len = h_len[i];
                char* line_buf = (char*)malloc(len + 1);
                memcpy(line_buf, line_ptrs[i], len);
                line_buf[len] = '\0';
                add_match_item(&result, i + 1, line_buf);
                free(line_buf);
            } else {
                result.count++;  // 内容は保存しない、カウントのみ
            }
        }
    }

    /* 8. GPU メモリ解放 */
    cudaFree(d_states);
    cudaFree(d_texts);
    cudaFree(d_off_gpu);
    cudaFree(d_len_gpu);
    cudaFree(d_chunk_ls_gpu);
    cudaFree(d_chunk_le_gpu);
    cudaFree(d_line_matched);

    double t2 = now_sec();
    result.cpu_pre_time = t1 - t0;
    result.gpu_exec_time = t2 - t1;
    printf("   [Breakdown Chunk Static] CPU Preprocess: %.6f sec | GPU Execution: %.6f sec (Total: %.6f sec)\n", 
           t1 - t0, t2 - t1, t2 - t0);

    return result;
}

SearchResult gpu_chunk_dynamic(struct NFA *nfa, const char *text, size_t text_bytes) {
    SearchResult result = create_search_result();
    if (!text || text_bytes == 0) return result;

    double t0 = now_sec();

    /* 1. 行分割 */
    std::vector<int>        h_off;
    std::vector<int>        h_len;
    std::vector<const char*> line_ptrs;

    const char* cur  = text;
    const char* tend = text + text_bytes;

    while (cur < tend) {
        const char* nl = (const char*)memchr(cur, '\n', tend - cur);
        size_t len = nl ? (size_t)(nl - cur) : (size_t)(tend - cur);
        h_off.push_back((int)(cur - text));
        h_len.push_back((int)len);
        line_ptrs.push_back(cur);
        cur = nl ? nl + 1 : tend;
        if (!nl) break;
    }

    int n_lines = (int)h_off.size();
    if (n_lines == 0) return result;

    /* 2. 動的チャンク分割 (文字数ベースの負荷分散) */
    // 2.1 全行の合計文字数（バイト数）を計算
    long total_chars = 0;
    for (int i = 0; i < n_lines; i++) {
        total_chars += h_len[i];
    }

    // 2.2 目標チャンク数は LINES_PER_CHUNK を元に決定（同じスレッド数を目標とする）
    int n_chunks_target = (n_lines + LINES_PER_CHUNK - 1) / LINES_PER_CHUNK;
    if (n_chunks_target < 1) n_chunks_target = 1;
    long target_chars   = (total_chars + n_chunks_target - 1) / n_chunks_target;
    if (target_chars < 1) target_chars = 1;

    // 2.3 文字数の累積でチャンクを動的に区切る
    std::vector<int> h_chunk_ls, h_chunk_le;
    int chunk_start    = 0;
    long running_chars = 0;

    for (int i = 0; i < n_lines; i++) {
        running_chars += h_len[i];
        bool is_last = (i == n_lines - 1);

        if (running_chars >= target_chars || is_last) {
            h_chunk_ls.push_back(chunk_start);
            h_chunk_le.push_back(i + 1);  // exclusive
            chunk_start    = i + 1;
            running_chars  = 0;
        }
    }

    int n_chunks = (int)h_chunk_ls.size();

    double t1 = now_sec();

    /* 3. NFA 状態配列の作成 */
    order.clear();
    idx_map.clear();
    gather_states(nfa->start);

    std::vector<GPUState> h_states(order.size());
    for (size_t i = 0; i < order.size(); ++i) {
        State* s = order[i];
        h_states[i] = { s->c, idx_of(s->out), idx_of(s->out1), 0 };
    }

    /* 4. GPU メモリの確保と転送 */
    GPUState* d_states;
    char*     d_texts;
    int*      d_off_gpu;
    int*      d_len_gpu;
    int*      d_chunk_ls_gpu;
    int*      d_chunk_le_gpu;
    int*      d_line_matched;

    cudaMalloc(&d_states,       h_states.size() * sizeof(GPUState));
    cudaMalloc(&d_texts,        text_bytes);
    cudaMalloc(&d_off_gpu,      n_lines  * sizeof(int));
    cudaMalloc(&d_len_gpu,      n_lines  * sizeof(int));
    cudaMalloc(&d_chunk_ls_gpu, n_chunks * sizeof(int));
    cudaMalloc(&d_chunk_le_gpu, n_chunks * sizeof(int));
    cudaMalloc(&d_line_matched, n_lines  * sizeof(int));

    cudaMemcpy(d_states,       h_states.data(),   h_states.size() * sizeof(GPUState), cudaMemcpyHostToDevice);
    cudaMemcpy(d_texts,        text,               text_bytes,                         cudaMemcpyHostToDevice);
    cudaMemcpy(d_off_gpu,      h_off.data(),       n_lines  * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemcpy(d_len_gpu,      h_len.data(),       n_lines  * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemcpy(d_chunk_ls_gpu, h_chunk_ls.data(),  n_chunks * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemcpy(d_chunk_le_gpu, h_chunk_le.data(),  n_chunks * sizeof(int),             cudaMemcpyHostToDevice);
    cudaMemset(d_line_matched, 0, n_lines * sizeof(int));

    /* 5. カーネル起動 (1ブロックあたり 256 スレッド) */
    int threads = 256;
    int blocks  = (n_chunks + threads - 1) / threads;
    gpu_chunk_match_kernel<<<blocks, threads>>>(
        d_states, d_texts, d_off_gpu, d_len_gpu,
        d_chunk_ls_gpu, d_chunk_le_gpu, n_chunks, d_line_matched
    );
    cudaDeviceSynchronize();
    {
        cudaError_t err = cudaGetLastError();
        if (err != cudaSuccess)
            fprintf(stderr, "CUDA Error (Chunk Parallel Dynamic): %s\n", cudaGetErrorString(err));
    }

    /* 6. 結果の回収 */
    std::vector<int> h_line_matched(n_lines);
    cudaMemcpy(h_line_matched.data(), d_line_matched, n_lines * sizeof(int), cudaMemcpyDeviceToHost);

    /* 7. SearchResult への格納（最初の MAX_STORED_MATCHES 件のみ内容を保存） */
    for (int i = 0; i < n_lines; ++i) {
        if (h_line_matched[i]) {
            if (result.stored_count < MAX_STORED_MATCHES) {
                int len = h_len[i];
                char* line_buf = (char*)malloc(len + 1);
                memcpy(line_buf, line_ptrs[i], len);
                line_buf[len] = '\0';
                add_match_item(&result, i + 1, line_buf);
                free(line_buf);
            } else {
                result.count++;  // 内容は保存しない、カウントのみ
            }
        }
    }

    /* 8. GPU メモリ解放 */
    cudaFree(d_states);
    cudaFree(d_texts);
    cudaFree(d_off_gpu);
    cudaFree(d_len_gpu);
    cudaFree(d_chunk_ls_gpu);
    cudaFree(d_chunk_le_gpu);
    cudaFree(d_line_matched);

    double t2 = now_sec();
    printf("   [Breakdown] CPU Preprocess: %.6f sec | GPU Execution: %.6f sec (Total: %.6f sec)\n", 
           t1 - t0, t2 - t1, t2 - t0);

    result.cpu_pre_time = t1 - t0;
    result.gpu_exec_time = t2 - t1;

    return result;
}

} // extern "C"
