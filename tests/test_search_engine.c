#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "utils.h"
#include "nfa.h"

// 🧪 テスト1: 結果データ構造の動的拡張とメモリライフサイクル
void test_search_result_lifecycle() {
    SearchResult result = create_search_result();
    
    // 初期状態の検証
    assert(result.items == NULL);
    assert(result.count == 0);
    assert(result.capacity == 0);
    
    // アイテムの追加
    add_match_item(&result, 10, "First match");
    assert(result.count == 1);
    assert(result.capacity > 0);
    assert(result.items != NULL);
    assert(result.items[0].line_number == 10);
    assert(strcmp(result.items[0].line_content, "First match") == 0);
    
    // 初期容量（通常4）を超える追加を行い、自動拡張を検証
    add_match_item(&result, 20, "Second match");
    add_match_item(&result, 30, "Third match");
    add_match_item(&result, 40, "Fourth match");
    add_match_item(&result, 50, "Fifth match"); // ここで拡張が発生
    
    assert(result.count == 5);
    assert(result.capacity >= 5);
    assert(result.items[4].line_number == 50);
    assert(strcmp(result.items[4].line_content, "Fifth match") == 0);
    
    // 解放の検証 (ASan環境でリークしないこと)
    free_search_result(&result);
    assert(result.items == NULL);
    assert(result.count == 0);
    assert(result.capacity == 0);
    
    printf("[PASS] test_search_result_lifecycle\n");
}

// 🧪 テスト2: 改行区切り走査とマッチング精度の検証
void test_cpu_sequential_correctness() {
    const char *text = "apple\nbanana\napricot\ngrape\n";
    size_t text_bytes = strlen(text);
    
    NFA *nfa = nfa_compile("apple|apricot");
    assert(nfa != NULL);
    
    // cpu_line_sequential 戦略を実行
    SearchResult result = search_engine_execute("cpu_line_sequential", nfa, text, text_bytes);
    
    printf("DEBUG: result.count = %zu\n", result.count);
    for (size_t idx = 0; idx < result.count; idx++) {
        printf("DEBUG: Match [%zu]: Line %d, content='%s'\n", idx, result.items[idx].line_number, result.items[idx].line_content);
    }
    
    // "apple" (行1), "apricot" (行3) の2件がマッチするはず
    assert(result.count == 2);
    
    assert(result.items[0].line_number == 1);
    assert(strcmp(result.items[0].line_content, "apple") == 0);
    
    assert(result.items[1].line_number == 3);
    assert(strcmp(result.items[1].line_content, "apricot") == 0);
    
    free_search_result(&result);
    nfa_free(nfa);
    
    printf("[PASS] test_cpu_sequential_correctness\n");
}

// 🧪 テスト3: 極端な境界条件（エッジケース）の検証
void test_search_edge_cases() {
    // A. 空テキスト
    {
        NFA *nfa = nfa_compile("a.*");
        SearchResult result = search_engine_execute("cpu_line_sequential", nfa, "", 0);
        assert(result.count == 0);
        free_search_result(&result);
        nfa_free(nfa);
    }
    
    // B. マッチなし
    {
        NFA *nfa = nfa_compile("xyz");
        const char *text = "apple\nbanana\n";
        SearchResult result = search_engine_execute("cpu_line_sequential", nfa, text, strlen(text));
        assert(result.count == 0);
        free_search_result(&result);
        nfa_free(nfa);
    }
    
    // C. 末尾に改行がないファイル
    {
        NFA *nfa = nfa_compile("banana");
        // bananaの末尾に改行がない
        const char *text = "apple\nbanana";
        SearchResult result = search_engine_execute("cpu_line_sequential", nfa, text, strlen(text));
        assert(result.count == 1);
        assert(result.items[0].line_number == 2);
        assert(strcmp(result.items[0].line_content, "banana") == 0);
        free_search_result(&result);
        nfa_free(nfa);
    }
    
    // D. UTF-8マルチバイト文字の日本語マッチング
    {
        NFA *nfa = nfa_compile("日本語.*");
        assert(nfa != NULL);
        const char *text = "英語\n日本語テストです\nフランス語\n";
        SearchResult result = search_engine_execute("cpu_line_sequential", nfa, text, strlen(text));
        assert(result.count == 1);
        assert(result.items[0].line_number == 2);
        assert(strcmp(result.items[0].line_content, "日本語テストです") == 0);
        free_search_result(&result);
        nfa_free(nfa);
    }
    
    printf("[PASS] test_search_edge_cases\n");
}

int main() {
    printf("--- Running Search Engine Unit Tests ---\n");
    
    test_search_result_lifecycle();
    test_cpu_sequential_correctness();
    test_search_edge_cases();
    
    printf("--- All search engine tests passed! ---\n");
    return 0;
}
