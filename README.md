# regular-expression-using-kagayaki  
## 誰向け  
WIP  

## 概要  
GPUを用いて正規表現マッチの高速化をGPUを用いて行う。 
[Regular Expression Matching Can Be Simple And Fast](https://swtch.com/~rsc/regexp/regexp1.html)の実装をGPUで高速化する。  


## 実行準備  
### 1. コードの修正  
WIP  
  
### 2. ビルド済みコンテナの取得  
repositoryのルートディレクトリから
```
.env/kagayaki_sh/make_new_sif_env.sh
```
これで./singularity/ubuntu.sifが作成される。  
  
## cpu版でのテスト実行    
```
compile_and_conduct_test_cpu.sh
```
実行完了すると```./results/```に実行結果がcsv排出される。