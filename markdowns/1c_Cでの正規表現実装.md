# Cでの正規表現実装  
  
元コードがCで書かれていたのでCで実装することにした。  
  
## 実装コード  
[実装コード](https://github.com/NamelessOgya/regular-expression-using-kagayaki/tree/fix-dot-related-bug)  
  
### 正規表現マッチ部分  
```./src/nfa.c```として実装。   
正規表現マッチ部分は[参考実装](https://rdm.nii.ac.jp/4gnfr/wiki/1b_%E5%8F%82%E8%80%83%E5%AE%9F%E8%A3%85%E3%81%AE%E8%AA%BF%E6%9F%BB/)の物をそのまま用いた。  
  
### 実験部分実装  
```nfa.c```を用いて正規表現正規表現をマッチを行う部分は```test_nfa.c```として実装。  
  
テスト用のcsvファイルを```./data```に配置して実行すると、各行に対してマッチしているか否か/実行時間を```./result```配下に配置する。  
  
## 課題  
テストを通じて、参考実装の```.```の処理にバグがあることが判明。  
以下で修正を実施中。  
[issue](https://github.com/NamelessOgya/regular-expression-using-kagayaki/issues/1)  
  
サンプル実装では「.」を実装しておらず、内部実装用の区切り文字として使われていることが判明。  
おそらく後から実装しても変更は軽微と考えて、一旦実装なしで進める。  
要否に関しては相談させてください。