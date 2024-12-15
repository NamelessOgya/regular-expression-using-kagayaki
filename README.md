# regular-expression-using-kagayaki  
## 誰向け  
WIP  

## 概要  
WIP  

## 実行準備  
### 1. コードの修正  
WIP  
  
### 2. ビルド済みコンテナの取得  
repositoryのルートディレクトリから
```
./make_new_sif_env.sh
```
これで./singularity/ubuntu.sifが作成される。  
  
## batch実行  
WIP  
  
## 対話的実行  
kagayakiのinteractive nodeへログイン  
```
qsub -q DEFAULT -l select=1 -I
```  
コンパイル    
```
g++ -o hello.out hello.cpp
```
実行    
```
./hello.out
```


### 結果確認    
WIP  

## 便利コマンド  
### 自分のjobを確認  
```
qstat -u (ログインユーザー名)  
```

### 自分のjobを削除  
```
qdel [job名 .spcc-xxxxみたいなやつ]  
```  

