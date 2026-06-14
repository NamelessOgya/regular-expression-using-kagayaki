# アイデア: AI Agent に特化した grep エンジン

## 背景・モチベーション

本プロジェクトは「CPU grep vs GPU 正規表現エンジン」の性能比較が出発点だが、
今後の研究の伸ばし方として **「AI Agent が実際にたたく grep に特化した最適化」** という方向性が考えられる。

---

## 関連論文・参考文献

### 直接関連する研究（2025〜2026）

| 論文 | 概要 |
|---|---|
| **"Is Grep All You Need? How Agent Harnesses Reshape Agentic Search"** (arxiv, 2026年5月) | Claude Code, Chronos 等の実エージェントが grep vs ベクトル検索（RAG）でどちらが優秀かを実証比較。**多くのケースで grep の方が精度が高い**という結論 |
| **"An Exploratory Study of Code Retrieval Techniques in Coding Agents"** (preprints, 2025) | SWE-bench ベースでエージェントが実際にどのツール（grep/find/LSP/semantic）をどの順番で使うかを分析 |

### 関連ツール・動向

- **ast-grep**: 構文木ベースの検索ツール。"async 関数でエラー処理のないもの" のような構造的クエリに対応
- **llm-grep**: regex による絞り込み → LLM によるセマンティックフィルタリングの2パス方式
- **ripgrep (rg)**: 実運用では agent が `grep` と書いても `rg` にエイリアスされていることが多い

---

## 「AI Agent がたたきがちな grep」の特徴（文献から）

| 特徴 | 詳細 | エンジン設計への示唆 |
|---|---|---|
| **パターンが短く・ゆるい** | 30文字以下の単純パターンが大多数。複雑な後読み否定などはほぼ使わない | NFA よりも DFA / Aho-Corasick が有利な可能性 |
| **識別子・関数名がメイン** | `def foo`, `class Bar`, `import X` のようなリテラル中心 | 完全一致・前方一致のショートカットが効果的 |
| **反復的・段階的に絞り込む** | 1発で決めようとせず `foo` → `foo_handler` → `class FooHandler` と段階的 | 複数パターン同時検索（multi-pattern）の需要あり |
| **コードベースが対象** | Wikipedia のような自然文章ではなくソースコードが主対象 | ファイル単位・行単位の並列化設計が変わる |
| **繰り返し同じパターンを投げる** | 同一セッション内で同じ正規表現を複数回実行することが多い | NFA コンパイル結果のキャッシュが効果的 |

---

## 研究方向性のアイデア

### A. Agent の grep ログを実測してパターン分布を分析する
- Claude Code や GitHub Copilot Agent のツールコールログから実際の grep コマンドを収集
- 「現実の正規表現分布」を本プロジェクトの `data/test_cases.csv` に反映させ、より実用的なベンチマークを構築する

### B. Agent 向けに特化したエンジン設計
- **short-pattern 特化**: AI agent が使うパターンは短い → DFA ベースや Aho-Corasick が有利な可能性
- **multi-pattern 並列化**: 複数の正規表現を1パスで同時マッチングする GPU エンジン
- **NFA キャッシュ**: 同一パターンの再コンパイルをスキップする仕組み

### C. コードベース向けの行構造活用
- ソースコードは Wikipedia と異なり行長のばらつきが大きい（空行・短いコード・長いコメント）
- 動的チャンク分割（→ [`dynamic_chunk_splitting.md`](file:///home/ubuntu/regular-expression-using-kagayaki/ideas/dynamic_chunk_splitting.md)）との組み合わせが有効かもしれない

---

## 次のアクション（優先度順）

1. **"Is Grep All You Need?" 論文を精読する**
   - ベンチマークデータ（agent が実際に使ったクエリログ）が公開されているか確認
2. **実際の agent ログからパターンを収集する小実験**
   - Claude Code / GitHub Copilot Agent を使って SWE-bench タスクを解かせ、grep のパターンをログ収集
3. **コードベース対象のベンチマークデータを追加**
   - 現在の Wikipedia データに加えて、Linux カーネル等のソースコードをデータセットとして追加

---

## 参考リンク

- ["Is Grep All You Need?"](https://arxiv.org) (arxiv 2026)
- [An Exploratory Study of Code Retrieval Techniques in Coding Agents](https://preprints.org) (2025)
- [ast-grep](https://ast-grep.github.io/)
- [zjunlp/LLMAgentPapers](https://github.com/zjunlp/LLMAgentPapers) - LLM Agent 論文まとめ
