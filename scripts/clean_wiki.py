import re
import sys

def clean_xml_tags(input_path, output_path):
    # XMLタグにマッチする正規表現
    tag_re = re.compile(r'<[^>]+>')
    
    print(f"Cleaning XML tags from {input_path} and saving to {output_path}...")
    
    with open(input_path, 'r', encoding='utf-8', errors='ignore') as infile, \
         open(output_path, 'w', encoding='utf-8') as outfile:
        
        for line in infile:
            # XMLタグを除去
            clean_line = tag_re.sub('', line)
            # 無駄な空白や空行の除去
            clean_line = clean_line.strip()
            if clean_line:
                outfile.write(clean_line + '\n')
                
    print("Cleaning completed successfully!")

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python clean_wiki.py <input_file> <output_file>")
        sys.exit(1)
    clean_xml_tags(sys.argv[1], sys.argv[2])
