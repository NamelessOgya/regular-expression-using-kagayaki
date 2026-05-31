#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <assert.h>
#include "config.h"
#include "utils.h"

void test_get_jst_timestamp() {
    char buffer[20];
    
    get_jst_timestamp(buffer, sizeof(buffer));
    printf("Timestamp: %s\n", buffer);
    
    // 1. 全体で17文字であることを確認
    assert(strlen(buffer) == 17);
    
    // 2. strtok は元の文字列を書き換えて破壊してしまうため、検証用のコピーを作る
    char copy[20];
    strcpy(copy, buffer);
    
    // 3. "_" で順番に区切って、それぞれの文字数を検証する
    char *tok;
    
    // 1ブロック目: 日付 (YYYYMMDD) -> 8文字のはず
    tok = strtok(copy, "_");
    assert(tok != NULL);         // 万が一区切れなかったらエラー
    assert(strlen(tok) == 8);    // 8文字かチェック
    
    // 2ブロック目: 時 (HH) -> 2文字のはず
    tok = strtok(NULL, "_");
    assert(tok != NULL);
    assert(strlen(tok) == 2);
    
    // 3ブロック目: 分 (MM) -> 2文字のはず
    tok = strtok(NULL, "_");
    assert(tok != NULL);
    assert(strlen(tok) == 2);
    
    // 4ブロック目: 秒 (SS) -> 2文字のはず
    tok = strtok(NULL, "_");
    assert(tok != NULL);
    assert(strlen(tok) == 2);
    
    // 5. これ以上はブロック（"_"の区切り）が存在しないことを確認
    tok = strtok(NULL, "_");
    assert(tok == NULL);
}




void test_remove_trailing_newline() {
    // パターン1: 末尾に改行がある場合 -> 消えること
    char test1[] = "hello\n";
    remove_trailing_newline(test1);
    assert(strcmp(test1, "hello") == 0);
    
    // パターン2: 途中に改行がある場合 -> 消えず、文字が途切れないこと
    char test2[] = "hello\nworld";
    remove_trailing_newline(test2);
    assert(strcmp(test2, "hello\nworld") == 0);

    // （おまけ）パターン3: 改行が全くない場合 -> 何も変わらないこと
    char test3[] = "hello";
    remove_trailing_newline(test3);
    assert(strcmp(test3, "hello") == 0);

    printf("remove_trailing_newline passed!\n");
}

void test_write_csv_header() {
    // 1. テスト用の書き込みファイルを sandbox 内に作成
    const char *test_file = "sandbox/test_header_test.csv";
    FILE *fw = fopen(test_file, "w");
    assert(fw != NULL); // ちゃんとファイルが開けたか確認
    
    // 2. 関数を呼び出して実際に書き込ませる
    write_csv_header(fw);
    fclose(fw);
    
    // 3. 今度は読み込みモードで開き直す
    FILE *fr = fopen(test_file, "r");
    assert(fr != NULL);
    
    // 4. 文字列を読み出す
    char buffer[256];
    char *res = fgets(buffer, sizeof(buffer), fr);
    assert(res != NULL); // 中身が空でないか確認
    
    // 5. 期待する出力と完全に一致するか確認
    const char *expected = "正規表現,検索対象,マッチ行数,マッチ詳細(行番号と行テキスト),実行時間(秒)\n";
    assert(strcmp(buffer, expected) == 0);
    
    fclose(fr);
    
    // 6. テストが終わったらファイルを自動で消去（掃除）する
    remove(test_file);
    
    printf("write_csv_header passed!\n");
}

void test_generate_csv_filename() {
    char filename[128];
    
    // 関数を呼び出してファイル名を生成させる
    generate_csv_filename(filename, sizeof(filename));
    
    // 1. ファイル名が特定のプレフィックスで始まっていることの確認
    // "./results/results_" は 18文字
    assert(strncmp(filename, "./results/results_", 18) == 0);
    
    // 2. 拡張子とサフィックス(GPUかCPUか)のテスト
#ifdef GPU_RUN
    // GPU_RUNがONのときは "_gpu.csv" で終わっているか確認
    char *ext = strstr(filename, "_gpu.csv");
    assert(ext != NULL); 
    assert(strcmp(ext, "_gpu.csv") == 0);
#else
    // CPUのときはただの ".csv" で終わっており "_gpu" が含まれていないか確認
    char *ext = strstr(filename, ".csv");
    assert(ext != NULL); 
    assert(strcmp(ext, ".csv") == 0);
    assert(strstr(filename, "_gpu") == NULL); // GPU文字が入っていてはダメ
#endif

    // 3. 全体の文字数が想定通りか確認
    // "./results/results_" (18) + "YYYYMMDD_HH_MM_SS" (17) + ".csv" (4) = 最低39文字
    assert(strlen(filename) >= 39);
    
    printf("generate_csv_filename passed! (Generated: %s)\n", filename);
}

void test_split_csv_static() {
    char regex[128];
    char target[128];
    
    // パターン1: 正常系 (カンマが1つ)
    char line1[] = "hello,world";
    size_t count1 = split_csv_static(line1, regex, target, sizeof(regex));
    assert(count1 == 2);
    assert(strcmp(regex, "hello") == 0);
    assert(strcmp(target, "world") == 0);
    
    // パターン2: カンマが複数ある場合 (3要素以上あってもregexとtargetには前2つが入る)
    char line2[] = "pattern,target_text,other_data";
    memset(regex, 0, sizeof(regex));
    memset(target, 0, sizeof(target));
    size_t count2 = split_csv_static(line2, regex, target, sizeof(regex));
    assert(count2 == 3);
    assert(strcmp(regex, "pattern") == 0);
    assert(strcmp(target, "target_text") == 0);

    // パターン3: 文字列が長すぎる場合のバッファサイズ超過テスト (エラーとして弾くこと)
    char line3[] = "1234567,abcdefghi";
    char short_regex[5]; // 4文字 + \0 が限界
    char short_target[5];

    printf("  ( Info: ↓これはバッドケースのテストなので、エラーが出ていれば正常です )\n");
    size_t count3 = split_csv_static(line3, short_regex, short_target, sizeof(short_regex));
    
    // 切り詰めは行わず、(size_t)-1 を返してエラー状態になっているかを確認
    assert(count3 == (size_t)-1);

    printf("split_csv_static passed!\n");
}

int main() {
    printf("--- Running Unit Tests ---\n");
    
    test_get_jst_timestamp();
    test_remove_trailing_newline();
    test_write_csv_header();
    test_generate_csv_filename();
    test_split_csv_static();
    
    printf("--- All tests passed! ---\n");
    return 0;
}