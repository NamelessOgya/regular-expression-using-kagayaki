/* =======================================================================
 *  sandbox/nfa.cu
 *  Thompson‑NFA 正規表現マッチャ (GPU 版)
 *  -------------------------------------------------
 *  ● re2post / post2nfa など CPU 側ロジックは nfa_cpu_common.h に分離
 *  ● 文字列ごとに 1‑thread で並列マッチ
 *  ● 最大状態数 : 4096、最大クエリ数 : 1024、最大文字列長 : 1024
 *  ビルド例 :  nvcc -O3 -std=c++17 -arch=sm_80 -Isandbox sandbox/nfa.cu -o nfa.out
 * =======================================================================*/
 #include <cuda_runtime.h>
 #include <vector>
 #include <unordered_map>
 #include <iostream>
 #include <cstring>
 #include "nfa_cpu_common.h"
 
 /* --------------------------- グローバル ------------------------------ */
 int   nstate      = 0;                       // CPU 側で状態数をインクリメント
 State matchstate  = { Match, nullptr, nullptr, 0 };
 
 /* --------------------------- GPU 用構造体 --------------------------- */
 struct GPUState {
     int c;
     int out;
     int out1;
     int lastlist;      // GPU カーネルでは未使用（0 固定）
 };
 
 /* -------------------- NFA を線形化するユーティリティ ----------------- */
 static std::vector<State*>            order;     // DFS 順
 static std::unordered_map<State*,int> idx_map;   // State* → 連番
 
 void gather_states(State* s)
 {
     if (!s || idx_map.count(s)) return;
     int id = static_cast<int>(order.size());
     idx_map[s] = id;
     order.push_back(s);
 
     if (s->out ) gather_states(s->out );
     if (s->out1) gather_states(s->out1);
 }
 inline int idx_of(State* s) { return s ? idx_map.at(s) : -1; }
 
 /* ---------------------- GPU カーネル補助関数 ------------------------- */
 __device__ __forceinline__
 void add_state(int* list, int& n, const GPUState* d_states,
                int idx, int list_id)
 {
     if (idx < 0) return;
     const GPUState& st = d_states[idx];
     if (st.lastlist == list_id) return;          // visited
     // Split は ε 遷移を辿る
     if (st.c == Split) {
         add_state(list, n, d_states, st.out , list_id);
         add_state(list, n, d_states, st.out1, list_id);
     } else {
         list[n++] = idx;
     }
 }
 
 __global__ void match_kernel(const GPUState* d_states,
                              const char* d_texts,
                              const int*  d_off,
                              const int*  d_len,
                              int n_strings,
                              int* d_res)
 {
     int tid = blockIdx.x * blockDim.x + threadIdx.x;
     if (tid >= n_strings) return;
 
     const char* str = d_texts + d_off[tid];
     int   len       = d_len[tid];
 
     /* スレッドローカルの NFA ワーク領域 */
     __shared__ int   list_id_shared;            // ブロック共有 list_id
     if (threadIdx.x == 0) list_id_shared = 1;
     __syncthreads();
 
     int list_id = list_id_shared;
     const int MAX_STATE = 4096;
     int clist[MAX_STATE], nlist[MAX_STATE];
     int n_c = 0, n_n = 0;
 
     add_state(clist, n_c, d_states, 0, list_id);   // 0: start
 
     for (int pos = 0; pos < len; ++pos) {
         ++list_id;
         char ch = str[pos];
         n_n = 0;
         for (int i = 0; i < n_c; ++i) {
             const GPUState& st = d_states[clist[i]];
             if (st.c == static_cast<unsigned char>(ch))
                 add_state(nlist, n_n, d_states, st.out, list_id);
         }
         // swap
         n_c = n_n;
         for (int i = 0; i < n_c; ++i) clist[i] = nlist[i];
     }
     // accept?
     int matched = 0;
     for (int i = 0; i < n_c && !matched; ++i)
         if (d_states[clist[i]].c == Match) matched = 1;
 
     d_res[tid] = matched;
 }
 
 /* -------------------------------------------------------------------- */
 int main(int argc, char** argv)
 {
     if (argc < 3) {
         std::cerr << "usage: nfa regexp string...\n";
         return 1;
     }
     /* ---------- 1. CPU で NFA 構築 ---------- */
     char* post = re2post(argv[1]);
     if (!post) { std::cerr << "bad regexp\n"; return 1; }
 
     State* start = post2nfa(post);
     if (!start) { std::cerr << "post2nfa failed\n"; return 1; }
 
     gather_states(start);                        // order[] に DFS
 
     /* ---------- 2. GPUState 配列作成 ---------- */
     std::vector<GPUState> h_states(order.size());
     for (size_t i = 0; i < order.size(); ++i) {
         State* s = order[i];
         h_states[i] = { s->c,
                         idx_of(s->out),
                         idx_of(s->out1),
                         0 };
     }
 
     /* ---------- 3. 文字列バッチ準備 ---------- */
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
 
     /* ---------- 4. デバイスメモリ確保 ---------- */
     GPUState* d_states;  cudaMalloc(&d_states, h_states.size()*sizeof(GPUState));
     char*     d_texts;   cudaMalloc(&d_texts,  total_bytes);
     int*      d_off;     cudaMalloc(&d_off,    n_inputs*sizeof(int));
     int*      d_len;     cudaMalloc(&d_len,    n_inputs*sizeof(int));
     int*      d_res;     cudaMalloc(&d_res,    n_inputs*sizeof(int));
 
     cudaMemcpy(d_states, h_states.data(), h_states.size()*sizeof(GPUState),
                cudaMemcpyHostToDevice);
     cudaMemcpy(d_texts , h_texts.data() , total_bytes, cudaMemcpyHostToDevice);
     cudaMemcpy(d_off   , h_off.data()   , n_inputs*sizeof(int), cudaMemcpyHostToDevice);
     cudaMemcpy(d_len   , h_len.data()   , n_inputs*sizeof(int), cudaMemcpyHostToDevice);
 
     /* ---------- 5. カーネル起動 ---------- */
     int threads = 256;
     int blocks  = (n_inputs + threads - 1) / threads;
     match_kernel<<<blocks, threads>>>(d_states,
                                       d_texts, d_off, d_len,
                                       n_inputs, d_res);
     cudaDeviceSynchronize();
 
     /* ---------- 6. 結果取得・出力 ---------- */
     std::vector<int> h_res(n_inputs);
     cudaMemcpy(h_res.data(), d_res, n_inputs*sizeof(int), cudaMemcpyDeviceToHost);
 
     for (int i = 0; i < n_inputs; ++i)
        //  if (h_res[i]) std::cout << argv[i+2] << '\n';
        if (h_res[i]) printf("%s\n", argv[i+2]);
 
     /* ---------- 7. 後始末 ---------- */
     cudaFree(d_states); cudaFree(d_texts);
     cudaFree(d_off);    cudaFree(d_len); cudaFree(d_res);
     
    
     return 0;
 }
 