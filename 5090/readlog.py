import os
import sys

def process_file(file_path):
    """处理单个文件，筛选出符合条件的行"""
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            # 获取文件名（不包含路径）
            file_name = os.path.basename(file_path)
            print("-" * 50)  # 分隔线，提高可读性
            print(f"{file_name}:")
            
            # 逐行读取文件
            for line in file:
                # 去除行首的空白字符后检查是否以指定字符串开头
                stripped_line = line.lstrip()
                if stripped_line.startswith(("Output", "Mean TTFT")):
                    print(f"{line.strip()}")
                    
    except UnicodeDecodeError:
        print(f"警告: 文件 '{file_path}' 不是文本文件，已跳过", file=sys.stderr)
    except Exception as e:
        print(f"处理文件 '{file_path}' 时发生错误: {str(e)}", file=sys.stderr)

def process_folder(folder_path):
    """处理文件夹中的所有文件"""
    # 检查文件夹是否存在
    if not os.path.exists(folder_path):
        print(f"错误: 文件夹 '{folder_path}' 不存在", file=sys.stderr)
        return
    
    # 检查是否是文件夹
    if not os.path.isdir(folder_path):
        print(f"错误: '{folder_path}' 不是一个文件夹", file=sys.stderr)
        return
    
    # 遍历文件夹中的所有文件
    for item in os.listdir(folder_path):
        item_path = os.path.join(folder_path, item)
        # 只处理文件，不处理子文件夹
        if os.path.isfile(item_path):
            process_file(item_path)

def main():
    # 检查命令行参数，获取要处理的文件夹路径
    if len(sys.argv) != 2:
        print("用法: python filter_folder_lines.py 文件夹路径")
        print("示例: python filter_folder_lines.py ./data_files")
        sys.exit(1)
    
    folder_path = sys.argv[1]
    process_folder(folder_path)

if __name__ == "__main__":
    main()

