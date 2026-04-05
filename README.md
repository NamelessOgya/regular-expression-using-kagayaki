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
│   └── gpu/              # GPU版コアエンジン
│       ├── nfa_gpu.cu
│       └── nfa_cpu_common.h
├── app/                  # エントリポイント
│   └── run_benchmark.c   # (旧: test_nfa.c) CSVデータを利用したパフォーマンス計測
├── tests/                
│   └── test_unit_nfa.c   # ロジック理解・確認用の軽量な単体テスト
├── data/                 # テストケースのCSVを置く場所 (test_cases.csv)
├── results/              # 計測結果の出力先
└── compile_and_conduct_*.sh   # コンパイルおよび実行用スクリプト
```

## 実行準備  
### ビルド済みコンテナの取得  
repositoryのルートディレクトリから
```bash
.env/kagayaki_sh/make_new_sif_env.sh
```
これで`./singularity/ubuntu.sif`が作成されます。  
  
## 実行手順

### 1. 単体テスト（ロジックの理解・確認用）
```bash
./compile_and_conduct_test_unit.sh
```
アルゴリズムが期待通り動くか素早く確認するためのコマンドです。

### 2. CPU版 ベンチマーク実行    
```bash
./compile_and_conduct_test_cpu.sh
```
`data/test_cases.csv` を読み込み、処理時間を計測します。
実行完了すると`./results/`に実行結果がcsv排出されます。

### 3. GPU版 ベンチマーク実行 (実装中)
```bash
./compile_and_conduct_test_gpu.sh
```