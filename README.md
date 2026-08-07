# regular-expression-using-kagayaki

## 誰向け
WIP

## 概要
GPUを用いて正規表現マッチの高速化を行う。  
[Regular Expression Matching Can Be Simple And Fast](https://swtch.com/~rsc/regexp/regexp1.html) の実装をGPUで高速化する。

---

## ディレクトリ構成

```
.
├── compile_and_conduct_test_cpu.sh   # CPU版 ビルド＆ベンチマーク実験スクリプト
├── compile_and_conduct_test_gpu.sh   # GPU版 ビルド＆ベンチマーク実験スクリプト
├── setup_dataset.sh                  # Wikipediaデータセット DL・整形スクリプト
├── Dockerfile                        # 開発環境用 Dockerfile (ubuntu:20.04)
├── env/
│   └── vm_hosting_sh/               # GPU VM (Docker) 向けスクリプト
│       ├── install_nvidia_toolkit.sh # NVIDIA Container Toolkit インストール（初回のみ）
│       ├── make_new_sif_env.sh       # CUDA イメージ取得
│       ├── start_container.sh        # コンテナ起動
│       └── stop_container.sh         # コンテナ停止
├── include/                          # ヘッダファイル
├── scripts/
│   └── clean_wiki.py                 # enwik8 の XMLタグ除去スクリプト
├── sandbox/
│   ├── nfa.c                         # NFA 実装 (CPU版)
│   ├── nfa.cu                        # NFA 実装 (GPU版 CUDA)
│   └── nfa_cpu_common.h
├── src/
│   └── test_nfa.c                    # ベンチマーク実験プログラム
├── data/                             # 実験データ置き場（DL後に生成）
└── results/                          # 実行結果 CSV 出力先
```

---

## 実行方法

### 0. 事前準備: NVIDIA Container Toolkit のインストール（初回のみ）

Dockerで `--gpus all` オプションを使うために、ホストマシンへ NVIDIA Container Toolkit をインストールする。

```bash
./env/vm_hosting_sh/install_nvidia_toolkit.sh
```

内部処理の流れ:
1. NVIDIA Container Toolkit の apt リポジトリを追加
2. `nvidia-container-toolkit` をインストール
3. Docker を再起動して設定を反映

> **注意**: `sudo` 権限が必要。既にインストール済みの場合はスキップ可。

### 1. GPU 環境イメージのビルド

```bash
./env/vm_hosting_sh/make_new_sif_env.sh
```

`nvidia/cuda:11.8.0-devel-ubuntu22.04` をベースに、`curl` / `python3` / `gcc` / `datasets` 等を含む
カスタムイメージ `re_exp_env_gpu` をビルドする（`env/vm_hosting_sh/Dockerfile.gpu` を使用）。

### 2. コンテナの起動

```bash
./env/vm_hosting_sh/start_container.sh
```

リポジトリのルートディレクトリが `/app` としてマウントされたコンテナに入る。  
`WORKDIR /app` が設定されているため、起動直後から `/app` にいる。

### 3. Wikipediaデータセットの準備（初回のみ）

コンテナ内で以下を実行する。

```bash
./setup_dataset.sh
```

内部処理の流れ:
1. `http://mattmahoney.net/dc/enwik8.zip`（約36MB）をダウンロード
2. zip を展開して `enwik8`（Wikipedia の XML ダンプ）を取り出す
3. `scripts/clean_wiki.py` で XML タグを除去し、プレーンテキストに変換
4. `./data/wiki_plain.txt` として保存
5. 一時ファイルを削除

> **注意**: `curl` と `python3` が必要。コンテナ内には同梱済み。

### 4. 統合ベンチマーク実験の実行（通常はこちらを使用）

コンテナ内で以下を実行する。CPU・GPU 全手法のスイープ実験、複数回試行の平均化、グラフ生成まで一括で行う。

```bash
./run_all.sh
```

主なオプション:

```bash
./run_all.sh --runs 5       # 各ベンチマークを5回繰り返す（デフォルト: 3回）
./run_all.sh --cpu-only     # CPU のみ実行（GPU はスキップ）
```

実行完了後、`results/run_<timestamp>/plots/benchmark_grid.png` に CPU vs GPU 比較グラフが生成される。

> **詳細**: 実行フローや出力ディレクトリ構造の詳細は [docs/run_all.md](docs/run_all.md) を参照。

---

### 4-a. 単体テスト: CPU版ビルド＆動作確認

コンテナ内で以下を実行する。

```bash
./compile_and_conduct_test_cpu.sh
```

内部処理の流れ:
1. `sandbox/nfa.c` → `nfa.o` にコンパイル（ASan 付き）
2. `src/test_nfa.c` → `test_nfa.o` にコンパイル
3. リンクして `test_nfa.asan` を生成
4. `./test_nfa.asan` を実行

実行完了後、`./results/` に結果 CSV が出力される。

### 4-b. GPU版ベンチマーク実験の実行

コンテナ内で以下を実行する。

```bash
./compile_and_conduct_test_gpu.sh
```

内部処理の流れ:
1. `sandbox/nfa.cu` を nvcc でコンパイル → `nfa.out`
2. `src/test_nfa.c` を gcc でコンパイル（`-DGPU_RUN`）→ `test_nfa.out`
3. `./test_nfa.out` を実行

> **注意**: GPU版の実行には CUDA 対応 GPU と nvcc が必要。

### 5. コンテナの停止

コンテナを終了するには `exit` またはコンテナ外から以下を実行する。

```bash
./env/vm_hosting_sh/stop_container.sh
```

---

## 実行結果の確認

実行完了後、`./results/` ディレクトリに CSV ファイルが出力される。

```bash
ls ./results/
```

---

## ドキュメント

| ドキュメント | 内容 |
|---|---|
| [docs/run_all.md](docs/run_all.md) | `run_all.sh` の実行フロー・オプション・出力構造の詳細 |
| [docs/gpu_parallelism.md](docs/gpu_parallelism.md) | GPU 並列化戦略（Line-Parallel vs Chunk-Parallel）の比較 |
| [docs/time_measurement.md](docs/time_measurement.md) | 実行時間の計測方法 |
| [docs/dataset.md](docs/dataset.md) | ベンチマーク対象データセット（enwik8）の詳細 |