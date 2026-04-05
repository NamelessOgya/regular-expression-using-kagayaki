#include <stdio.h>
#include <assert.h>
#include "nfa.h"

void test_nfa_basic_match() {
    NFA *nfa = nfa_compile("a(b|c)*d");
    
    // assert(条件): 条件が1(True)なら何も起きず通過、0(False)なら強制終了
    assert(nfa != NULL);
    assert(nfa_test(nfa, "ad") == 1);       // 真ん中が0回
    assert(nfa_test(nfa, "abd") == 1);      // bが1回
    assert(nfa_test(nfa, "abcbcd") == 1);   // bとcの繰り返し
    assert(nfa_test(nfa, "axd") == 0);      // マッチしないはずの文字
    
    nfa_free(nfa);
    printf("[PASS] test_nfa_basic_match\n");
}

void test_nfa_wildcard() {
    NFA *nfa = nfa_compile("a.c");
    assert(nfa != NULL);
    assert(nfa_test(nfa, "abc") == 1);
    assert(nfa_test(nfa, "axc") == 1);
    assert(nfa_test(nfa, "ac") == 0);
    assert(nfa_test(nfa, "abbc") == 0);

    nfa_free(nfa);
    printf("[PASS] test_nfa_wildcard\n");
}

int main() {
    printf("--- Running Unit Tests ---\n");
    
    test_nfa_basic_match();
    test_nfa_wildcard();
    
    printf("--- All tests passed! ---\n");
    return 0;
}
