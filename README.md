# regular-expression-using-kagayaki  

## 概要  
GPUを用いて正規表現マッチの高速化を行うプロジェクトです。
[Regular Expression Matching Can Be Simple And Fast](https://swtch.com/~rsc/regexp/regexp1.html)の実装をGPUで高速化します。  

## プロジェクト構成（リファクタリング済み）
将来的なGPU高速化に備え、CPU版とGPU版を切り替えてテストできるように整理されています。

```text
.
├── include/              # 全体で共通して使うヘッダー
│   ├── config.h          # 制限値（文字数など）の定義
│   ├── nfa.h             # CPU/GPU共通のコンパイル・検索インターフェース
│   └── utils.h           # 時間計測などのユーティリティプロトタイプ
├── src/                  
│   ├── common/           # CPU・GPU共通の実装部品
│   │   └── utils.c
│   ├── cpu/              # CPU版コアエンジン
│   │   └── nfa_cpu.c
│   └── gpu/              # GPU版コアエンジン（完全疎結合設計）
│       ├── common/       # GPU共通ヘッダー (nfa_gpu_common.h)
│       ├── line_parallel/# 「文ごとに分割」並列モデル (nfa_gpu_line.cu)
│       └── chunk_parallel/# 「チャンク分け」並列モデル (nfa_gpu_chunk.cu)
├── app/                  # エントリポイント
│   └── run_benchmark.c   # (旧: test_nfa.c) CSVデータを利用したパフォーマンス計測
├── tests/                
│   └── test_unit_nfa.c   # ロジック理解・確認用の軽量な単体テスト
├── data/                 # テストケースのCSVを置く場所 (test_cases.csv)
├── results/              # 計測結果の出力先
└── Taskfile.yml          # コンパイル・テスト・環境構築を完全自動化するタスクランナー設定
```

## 実行準備 (Docker環境の構築)
本プロジェクトは、HostPCの環境を汚さずに開発を行えるよう、Dockerによる専用コンテナを用意しています。
最初に以下のコマンド（Host上）を用いて環境を準備してください。

### 前提：タスクランナー（`task`）のインストール
開発の全フローは [Task](https://taskfile.dev/) (Taskfile.yml) で自動化されています。
ホストPCにまだインストールされていない場合は、付属のスクリプトを実行してインストールしてください。

```bash
# taskコマンドのインストール
./install_task.sh

# インストールしたパスを反映させる
source ~/.bashrc
```

### Dockerコンテナの起動
次に、Taskコマンドを使ってコンテナを準備・起動します。

```bash
# 1. コンテナのビルド（初回・設定変更時のみ）
task env:build

# 2. コンテナを起動し、中に入る（以後、全ての作業はコンテナ内で行います）
task env:start

# 3. 開発終了後、コンテナを明示的に停止する場合（任意）
task env:stop
```

## 実行手順（コンテナ内）

コンテナ内（`/app`ディレクトリ）に入ったら、以下のコマンドで一貫したテストやビルドが可能です。

### 1. すべてのテストを一元実行
```bash
task test_all
```
UTとユーティリティのテストなど、自動化された全てのテストを通しで実行します。

### 2. 単体テスト（特定の機能を個別に確認）
```bash
task test_unit    # NFAのアルゴリズム本体テスト
task test_utils   # 時間取得や文字パース部分のツールテスト
```

### 3. ベンチマークの本番実行
CSVデータ(`data/test_cases.csv`)を用いて正規表現の実行速度を計測し、その結果を `results/` に出力させます。

```bash
# CPU版のベンチマーク実行 (メモリ安全性チェック付き)
task bench_cpu

# GPU版のベンチマーク実行 (文ごとに分割モデルのみを独立実行)
task bench_gpu_line

# GPU版のベンチマーク実行 (チャンク分けモデルのみを独立実行)
task bench_gpu_chunk

# GPU版のベンチマーク比較実行 (Line と Chunk の両方を同時実行して比較)
task bench_gpu
```