# Sprint 003 理論資料: Thompson NFA 正規表現マッチングの理論値詳細計算式とその根拠

**作成日**: 2026-09-22  
**対象ハードウェア**:  
- **CPU**: AMD Ryzen 7 7700 (Zen 4, 8 cores / 16 threads, 3.8 GHz base / 5.3 GHz boost, L3 32MB)  
- **GPU**: NVIDIA GeForce RTX 5090 (Blackwell CC 12.0, 170 SMs, 21,760 CUDA cores, 3.09 GHz boost, GDDR7 32GB, 1,792 GB/s)  
**対象データセット**: Wikipedia プレーンテキスト `enwik8` (95,909,488 文字, 831,111 行, 平均行長 115.4 文字)

---

## 1. 目的と位置づけ

本資料は、[sprints/002/memo.md](file:///home/kasumi/regular-expression-using-kagayaki/sprints/002/memo.md) で提起された**「理論値と実測値の確認」「CPU側の実行速度が理論通りかの検証」**に応えるための理論的基盤を構築するものである。

GPU および CPU 上での Thompson NFA (Non-deterministic Finite Automaton) による部分一致検索処理の速度を、ハードウェア諸元（クロック周波数、メモリ帯域、演算ユニット数、キャッシュ構造）およびアルゴリズムの計算ステップから数理モデル化し、理論的な予測時間を算出する。

---

## 2. ハードウェア諸元と Roofline 限界

### 2.1 ハードウェアスペック一覧

| 項目 | AMD Ryzen 7 7700 (CPU) | NVIDIA GeForce RTX 5090 (GPU) |
|---|---|---|
| **アーキテクチャ** | Zen 4 | Blackwell (Compute Capability 12.0) |
| **コア数 / ユニット数** | 8 コア / 16 スレッド | 170 SMs (Streaming Multiprocessors) / 21,760 CUDA Cores |
| **動作周波数** | ~4.5 GHz (全コア負荷時実効) | ~3.09 GHz (Boost) |
| **理論メモリ帯域幅** | ~83.2 GB/s (Dual DDR5-5200) | **1,792 GB/s** (512-bit GDDR7 @ 28 Gbps) |
| **L1 キャッシュ** | 32 KB (Data) + 32 KB (Inst) / コア | 128 KB (Shared/L1) / SM ($\approx 21.76$ MB 合計) |
| **L2 キャッシュ** | 1 MB / コア | **96 MB** (チップ共有) |
| **ワープサイズ** | N/A (SIMD 512-bit / AVX-512) | 32 スレッド / ワープ |

---

### 2.2 Roofline モデルに基づく理論下限（メモリ律速 vs 演算律速）

`enwik8` のデータサイズは $D = 95.9 \text{ MB} \approx 0.096 \text{ GB}$ である。

#### (1) メモリ転送の理論下限時間 ($T_{\text{mem\_bound}}$)
純粋にテキストデータ全体をメモリから 1 回読み出すだけの最小理論時間は以下の通り：
- **GPU (GDDR7 1,792 GB/s)**:
  $$T_{\text{read\_GPU}} = \frac{0.096 \text{ GB}}{1792 \text{ GB/s}} \approx 0.0535 \text{ ms} \quad (53.5 \text{ }\mu\text{s})$$
- **PCIe 転送 (PCIe 4.0 x16 実効 ~25 GB/s)**:
  $$T_{\text{HtoD\_text}} = \frac{0.096 \text{ GB}}{25 \text{ GB/s}} \approx 3.84 \text{ ms}$$
- **CPU (DDR5 実効 ~60 GB/s)**:
  $$T_{\text{read\_CPU}} = \frac{0.096 \text{ GB}}{60 \text{ GB/s}} \approx 1.60 \text{ ms}$$

> **含意**:  
> 実測の GPU 実行時間は数 10ms 〜 数 100ms であり、テキストの単純読み出し（0.05ms）の数 100 倍〜数 1000 倍を要している。  
> したがって、**本処理は「グローバルメモリの帯域幅限界（Memory-bound）」ではなく、「NFA 状態遷移の演算ステップ数・分岐・L1/レジスタレイテンシ（Compute & Latency-bound）」に支配されている**ことがわかる。

---

## 3. Thompson NFA の命令レベル計算量モデル

### 3.1 1文字走査あたりの処理ステップ

テキストの各文字 $c$ を走査する際、1 スレッド内で実行される処理（`nfa_gpu_line.cu` L45-L74）は以下の 4 ステップからなる：

1. **`visited` 配列のクリア**:
   ```c
   for (int j = 0; j < 256; ++j) visited[j] = false;
   ```
   - 256 回のレジスタ/ローカルメモリ書き込み（約 16〜32 命令、ベクトル化時 4〜8 命令）。
2. **アクティブ状態集合 `clist` の走査と文字比較**:
   - 現在のアクティブ状態数を $S = |\text{clist}|$（$1 \le S \le |Q|$）とする。
   - 各アクティブ状態 $s \in \text{clist}$ に対し、状態文字 $st.c$ と文字 $c$ を比較。
   - 一致した場合、またはワイルドカードの場合に `add_state_local(nlist, ..., st.out)` を呼び出す。
3. **$\epsilon$-閉包展開 (`add_state_local`)**:
   - 遷移先状態が Split ($\epsilon$ 分岐) の場合、再帰的に分岐先を展開。
   - `visited[id]` を検査し、未訪問なら訪問済みにマークして `nlist` に追加。
4. **部分一致（Substring Search）用開始状態 (0番) の再追加**:
   - 各文字走査ごとに `add_state_local(nlist, ..., 0, visited)` を実行（常時部分一致開始）。
5. **リストのスワップ**:
   - `clist` に `nlist` をコピー（$S_{\text{next}}$ 回の 32-bit 整数コピー）。

#### 1文字あたりの平均サイクル数 $C_{\text{char}}(|Q|)$
1文字を処理するのに必要な CPU/GPU 命令サイクル数は、平均アクティブ状態数 $\bar{S}$ と NFA 総状態数 $|Q|$ に強く依存する：
$$C_{\text{char}}(|Q|) = C_{\text{clear}} + \bar{S} \times C_{\text{eval}} + C_{\text{start}} + \bar{S} \times C_{\text{copy}}$$

- **非マッチ・単純文字の場合**: $\bar{S} \approx 1 \sim 2$（開始状態から数状態のみアクティブ）
- **多分岐 Alternation（$k$ 分岐, $|Q| \approx 5k$）の場合**:
  - 先頭文字一致などで多数の状態が一時的にアクティブ化されるため、$\bar{S}$ は分岐数に比例して増大する。

---

### 3.2 スレッド初期化コスト $C_{\text{init}}$

各行（または各チャンク）の処理開始時に発生する初期化：
- `visited[256]` のゼロクリア（初回）
- 開始状態 0 番の初期追加
- マッチフラグ `matched = 0` の初期化

---

## 4. 各手法の理論実行時間モデル

### 4.1 CPU Sequential (`cpu_line_sequential`, Ryzen 7 7700)

CPU は 1 コアのシングルスレッドで 831,111 行（95.9 MB）を逐次処理する。

$$T_{\text{CPU}} = \frac{N_{\text{total\_chars}} \times C_{\text{char\_CPU}}(|Q|)}{f_{\text{CPU}}} + \frac{N_{\text{lines}} \times C_{\text{init\_CPU}}}{f_{\text{CPU}}}$$

- $N_{\text{total\_chars}} = 95,909,488$ 文字
- $N_{\text{lines}} = 831,111$ 行
- $f_{\text{CPU}} \approx 4.5 \times 10^9 \text{ Hz}$ (4.5 GHz)
- Ryzen 7 (Zen 4) の 1 サイクルあたり実行可能命令数 (IPC) は、分岐予測ミスやメモリ依存を考慮すると $\text{IPC} \approx 1.5 \sim 2.5$。
- **1文字あたりの所要サイクル数**:
  - `-O3` 最適化時: $C_{\text{char\_CPU}} \approx 20 \sim 60 \text{ サイクル}$（単純パターン時）
  - 単純パターンの場合：
    $$T_{\text{CPU\_simple}} \approx \frac{9.59 \times 10^7 \times 30}{4.5 \times 10^9} \approx 0.64 \text{ 秒} \quad (640 \text{ ms})$$
  - 多分岐・複雑パターンの場合（$C_{\text{char\_CPU}} \approx 150 \sim 300$ サイクル）：
    $$T_{\text{CPU\_complex}} \approx \frac{9.59 \times 10^7 \times 200}{4.5 \times 10^9} \approx 4.26 \text{ 秒}$$

> **ASan の影響**:  
> `-fsanitize=address` を付与した場合、メモリアクセスごとにシャドウメモリ検査命令が挿入されるため、命令数が 2〜3 倍に膨張し、所要時間は約 2.0x〜3.0x 遅延する（理論予測）。

---

### 4.2 GPU Line-Parallel (LPC=1)

- **スレッド総数**: $N_{\text{threads}} = N_{\text{lines}} = 831,111$
- **GPU 並列実行キャパシティ**:
  - RTX 5090: 170 SMs。
  - 各 SM で同時に実行可能なアクティブワープ数: 最大 48 ワープ（1,536 スレッド/SM）。
  - チップ全体のアクティブスレッド数 $M_{\text{active}} = 170 \times 1,536 = 261,120$ スレッド。
  - 全スレッドを消化するのに必要なウェーブ数（Waves）：
    $$W_{\text{waves}} = \left\lceil \frac{831,111}{261,120} \right\rceil \approx 3.2 \text{ 〜 } 4 \text{ ウェーブ}$$

#### 実行時間数式:
$$T_{\text{GPU\_Line\_kernel}} = \sum_{w=1}^{W_{\text{waves}}} \left( \frac{\mathbb{E}[\max_{t \in \text{warp}} (L_t \cdot C_{\text{char\_GPU}}(|Q|))]}{f_{\text{SM}}} + \frac{C_{\text{init\_thread}}(|Q|)}{f_{\text{SM}}} \right)$$

- **特徴**:
  - $C_{\text{init\_thread}}$ が全 831,111 スレッドで毎回発生（83万回の初期化）。
  - ワープ内 32 スレッドの最大行長 $\max_{t \in \text{warp}} L_t$ に律速されるが、1 スレッド 1 行のため、長行スレッド以外は早期に終了して次のウェーブへ移行可能。

---

### 4.3 GPU Chunked-Static (LPC=8)

- **スレッド総数**: $N_{\text{threads}} = \lceil 831,111 / 8 \rceil = 103,889$
- **ウェーブ数**:
  $$W_{\text{waves}} = \left\lceil \frac{103,889}{261,120} \right\rceil = 1 \text{ ウェーブ}$$
  （1 ウェーブで全スレッドが GPU 全 SM に一度に配置可能！）

#### 実行時間数式:
$$T_{\text{GPU\_ChunkStatic\_kernel}} = \frac{\mathbb{E}[\max_{t \in \text{warp}} (\sum_{k=1}^8 L_{t,k} \cdot C_{\text{char\_GPU\_warm}}(|Q|))]}{f_{\text{SM}}} + \frac{C_{\text{init\_thread}}(|Q|)}{f_{\text{SM}}}$$

- **特徴と速度向上要因**:
  1. **初期化回数が 1/8**: 初期化オーバーヘッドが 83 万回から 10 万回へと激減。
  2. **キャッシュ局所性・レジスタ再利用（Cache Warmth）**:
     $C_{\text{char\_GPU\_warm}} < C_{\text{char\_GPU}}$。同一スレッド内で 8 行分を連続実行するため、`visited` 配列や `clist` 用の L1 キャッシュ/レジスタがウォーム状態を保ち、実効サイクル数が削減される。特に状態数 $|Q|$ が大きいほどこの差が拡大する。
- **弱点**:
  - 8 行の合計文字数 $\sum_{k=1}^8 L_{t,k}$ のばらつきにより、ワープ内の最長スレッドの待機時間（Idle）が増大する。

---

### 4.4 GPU Chunked-Dynamic

- **スレッド総数**: 約 104,000
- **1 スレッドあたりの担当文字数**:
  $$L_{\text{target}} \approx \frac{95,909,488}{104,000} \approx 922 \text{ 文字 (全スレッド均等)}$$

#### 実行時間数式:
$$T_{\text{GPU\_ChunkDynamic}} = T_{\text{CPU\_pre\_dynamic}} + \frac{L_{\text{target}} \cdot C_{\text{char\_GPU\_warm}}(|Q|)}{f_{\text{SM}}} + \frac{C_{\text{init\_thread}}(|Q|)}{f_{\text{SM}}}$$

- **CPU 前処理時間 $T_{\text{CPU\_pre\_dynamic}}$**:
  全 831,111 行の累積文字数を CPU で順次加算してチャンク境界を決定する $O(N_{\text{lines}})$ ループ。
  $$T_{\text{CPU\_pre\_dynamic}} \approx \frac{N_{\text{lines}} \times C_{\text{accum\_loop}}}{f_{\text{CPU}}} \approx \frac{831,111 \times 15}{4.5 \times 10^9} \approx 2.8 \sim 3.5 \text{ ms}$$
- **特徴**:
  - GPU 側のワープダイバージェンスは極小化（全スレッドが 922 文字で揃う）されるが、CPU 前処理の 3.4ms が固定オーバーヘッドとして上乗せされる。

---

## 5. 手法間速度比の理論的予測

| 比較 | 理論的予測式 | 予測される挙動 |
|---|---|---|
| **CPU vs GPU** | $\frac{T_{\text{CPU}}}{T_{\text{GPU}}} \approx \frac{f_{\text{CPU}}^{-1} \cdot C_{\text{char\_CPU}}}{W_{\text{waves}} \cdot f_{\text{SM}}^{-1} \cdot C_{\text{char\_GPU}} / \text{Cooperative}}$ | GPU は 170 SMs による圧倒的並列化により **15倍〜50倍高速** と予測される |
| **Line vs Chunk-Static ($|Q| \le 20$)** | 初期化コスト小、ワープダイバージェンスが支配的 | **Line が 1.1x 〜 1.3x 高速** |
| **Line vs Chunk-Static ($|Q| \ge 40$)** | 作業領域大、Cache Warmth がダイバージェンスを上回る | **Chunk-Static が 1.1x 〜 1.4x 高速** |
| **Static vs Dynamic (均一分布)** | GPU 短縮幅 ($\approx 0.5 \text{ms}$) < CPU 前処理ペナルティ ($+3.4 \text{ms}$) | **Static が約 10% 〜 15% 高速** (Dynamic が遅い) |
| **Static vs Dynamic (偏在分布)** | GPU 短縮幅 ($> 6 \text{ms}$) > CPU 前処理ペナルティ ($+3.4 \text{ms}$) | **Dynamic が 30% 以上高速** |

---

## 6. まとめ

以上の定式化により、本実験 (Sprint 003) で実測・突合すべき検証項目は以下の 3 点に集約される：

1. **CPU 実行速度の妥当性**:
   - `-O3` ビルドにおける CPU 実行時間（約 0.6s〜数s）が、理論サイクル数（$C_{\text{char\_CPU}} \approx 20 \sim 200$）および Ryzen 7 7700 のクロック（4.5 GHz）から導かれる理論範囲に収まっているか。
   - ASan 付与時との速度比が理論予測（2〜3倍遅延）と一致するか。
2. **GPU 手法間の速度比逆転モデルの妥当性**:
   - 小状態数（$|Q| \le 20$）での Line 優位、大状態数（$|Q| \ge 40$）での Static 優位の理論値と実測値の定量的整合性。
3. **Dynamic の CPU 前処理 vs GPU 均等化の損益分岐点**:
   - 実測の CPU 前処理時間差（約 3.4ms）が理論通りの $O(N_{\text{lines}})$ スキャンコストと一致しているかの確認。
