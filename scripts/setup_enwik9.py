import os
import sys
import re
import urllib.request
import zipfile

def report_progress(block_num, block_size, total_size):
    read_so_far = block_num * block_size
    if total_size > 0:
        percent = min(100.0, read_so_far * 100.0 / total_size)
        sys.stdout.write(f"\rDownloading enwik9.zip: {percent:.1f}% ({read_so_far / (1024*1024):.1f}MB / {total_size / (1024*1024):.1f}MB)")
    else:
        sys.stdout.write(f"\rDownloading enwik9.zip: {read_so_far / (1024*1024):.1f}MB downloaded")
    sys.stdout.flush()

def clean_xml_tags(input_path, output_path):
    # XMLタグにマッチする正規表現
    tag_re = re.compile(r'<[^>]+>')
    print(f"Preprocessing: Cleaning XML tags from {input_path} and saving to {output_path}...")
    
    count = 0
    with open(input_path, 'r', encoding='utf-8', errors='ignore') as infile, \
         open(output_path, 'w', encoding='utf-8') as outfile:
        
        for line in infile:
            # XMLタグを除去
            clean_line = tag_re.sub('', line).strip()
            if clean_line:
                outfile.write(clean_line + '\n')
            
            count += 1
            if count % 1000000 == 0:
                sys.stdout.write(f"\rProcessed {count:,} lines...")
                sys.stdout.flush()
                
    sys.stdout.write(f"\rProcessed {count:,} lines. Done!\n")
    print(f"[Success] XML tags cleaned successfully! Plain text saved to {output_path}")

def main():
    target_dir = "./data"
    zip_path = os.path.join(target_dir, "enwik9.zip")
    extracted_path = os.path.join(target_dir, "enwik9")
    plain_output_path = os.path.join(target_dir, "enwik9_plain.txt")
    url = "http://mattmahoney.net/dc/enwik9.zip"

    # データディレクトリの作成
    os.makedirs(target_dir, exist_ok=True)

    # 1. ダウンロードと解凍
    if os.path.exists(extracted_path):
        print(f"[Info] enwik9 raw dataset already exists at {extracted_path}.")
    else:
        print("==================================================")
        print(" Downloading enwik9 Dataset (1GB raw XML corpus) ")
        print(" This might take a few moments depending on net speed...")
        print("==================================================")

        try:
            urllib.request.urlretrieve(url, zip_path, report_progress)
            print("\n[Success] Download completed successfully!")
        except Exception as e:
            print(f"\n[Error] Failed to download enwik9.zip: {e}")
            if os.path.exists(zip_path):
                os.remove(zip_path)
            sys.exit(1)

        print("Extracting enwik9.zip...")
        try:
            with zipfile.ZipFile(zip_path, 'r') as zip_ref:
                zip_ref.extractall(target_dir)
            print(f"[Success] Extracted enwik9 dataset successfully to {extracted_path}!")
        except Exception as e:
            print(f"[Error] Extraction failed: {e}")
            sys.exit(1)
        finally:
            if os.path.exists(zip_path):
                print("Cleaning up temporary zip file...")
                os.remove(zip_path)

    # 2. XMLタグ除去によるプレーンテキスト化の処理
    if os.path.exists(plain_output_path):
        print(f"[Info] Cleaned plain text already exists at {plain_output_path}.")
    else:
        clean_xml_tags(extracted_path, plain_output_path)

    print("==================================================")
    print(" Setup Completed! enwik9 (Raw & Plain) is ready.")
    print("==================================================")

if __name__ == "__main__":
    main()
