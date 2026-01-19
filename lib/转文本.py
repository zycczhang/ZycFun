import os
import shutil


def copy_dart_to_txt():
    # 获取当前脚本所在的文件夹路径
    current_dir = os.getcwd()

    # 遍历当前文件夹下的所有文件
    for filename in os.listdir(current_dir):
        # 检查文件是否是.dart后缀，且是文件（不是文件夹）
        if filename.endswith('.dart') and os.path.isfile(os.path.join(current_dir, filename)):
            # 构造原文件的完整路径
            original_file_path = os.path.join(current_dir, filename)
            # 构造新文件的名称（替换后缀为.txt）
            new_filename = filename.replace('.dart', '.txt')
            new_file_path = os.path.join(current_dir, new_filename)

            try:
                # 复制文件
                shutil.copy2(original_file_path, new_file_path)
                print(f"成功复制并转换: {filename} -> {new_filename}")
            except Exception as e:
                print(f"处理文件 {filename} 时出错: {str(e)}")


if __name__ == "__main__":
    print("开始转换.dart文件为.txt文件...")
    copy_dart_to_txt()
    print("转换完成！")