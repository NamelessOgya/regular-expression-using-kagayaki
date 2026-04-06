#include <stdio.h>
#include <assert.h>
#include <string.h>
#include "nfa.h"

void test_re2post() {
    // re2postが返すポインタはstatic bufferなので都度受けてチェックする
    
    // 1. 連結
    assert(strcmp(re2post((char*)"ab"), "ab#") == 0);
    
    // 2. 選択
    assert(strcmp(re2post((char*)"a|b"), "ab|") == 0);
    
    // 3. 繰り返し
    assert(strcmp(re2post((char*)"a*"), "a*") == 0);
    
    // 4. カッコ制御
    assert(strcmp(re2post((char*)"a(b|c)"), "abc|#") == 0);
    
    // 5. 複合パターン
    assert(strcmp(re2post((char*)"a(b|c)*d"), "abc|*#d#") == 0);
    
    // 6. ネストされたカッコ制御 1 (内側のカッコに演算子)
    assert(strcmp(re2post((char*)"((a|b)*c)*"), "ab|*c#*") == 0);

    // 7. ネストされたカッコ制御 2 (入れ子による遅延結合)
    assert(strcmp(re2post((char*)"(a(b(c)))"), "abc##") == 0);

    // 8. ネストされたカッコ制御 3 (実用的な複合ネスト)
    assert(strcmp(re2post((char*)"a(b(c|d)*)e"), "abcd|*##e#") == 0);

    // 9. 複数のOR (連続する選択)
    assert(strcmp(re2post((char*)"a|b|c"), "abc||") == 0);

    // 10. カッコ内の複数のOR
    assert(strcmp(re2post((char*)"(a|b|c)"), "abc||") == 0);

    // 11. ORとカッコの複雑な複合
    assert(strcmp(re2post((char*)"a|(b|c)|d"), "abc|d||") == 0);

    // 12. 複数のカッコグループの連結
    assert(strcmp(re2post((char*)"(a|b)(c|d)"), "ab|cd|#") == 0);
    
    printf("[PASS] test_re2post\n");
}

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
    
    test_re2post();
    test_nfa_basic_match();
    test_nfa_wildcard();
    
    printf("--- All tests passed! ---\n");
    return 0;
}
