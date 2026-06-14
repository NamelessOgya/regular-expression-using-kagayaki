/* nfa_gpu_line.cu */
#include "nfa_gpu_common.h"

/**
 * 1スレッド ＝ 1行 を担当し、行単位で並列に NFA 部分一致（Substring Search）を実行するカーネル。
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
    int clist[256], nlist[256];
    int n_c = 0, n_n = 0;
    bool visited[256];

    // 初期化：すべての訪問フラグをクリア
    for (int j = 0; j < 256; ++j) visited[j] = false;
    
    // NFAの開始位置 (0番) からスタート
    add_state_local(clist, n_c, d_states, 0, visited);

    int matched = 0;
    
    // 空文字列時点でマッチ可能か確認
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

        // サブストリング対応のための start(0) 追加
        add_state_local(nlist, n_n, d_states, 0, visited);

        // clist と nlist をスワップ
        n_c = n_n;
        for (int i = 0; i < n_c; ++i) clist[i] = nlist[i];

        // 受理状態到達チェック
        for (int i = 0; i < n_c; ++i) {
            if (d_states[clist[i]].c == Match) {
                matched = 1;
                break;
            }
        }
    }

    // 結果を書き込み
    d_res[tid] = matched;
}

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

    // 7. GPUメモリの解放
    cudaFree(d_states);
    cudaFree(d_texts);
    cudaFree(d_off);
    cudaFree(d_len);
    cudaFree(d_res);

    return result;
}

} // extern "C"
