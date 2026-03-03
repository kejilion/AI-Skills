#!/usr/bin/env python3
import sys
import os
import subprocess
import json

def generate_voice_ogg(text, output_ogg):
    # 临时 mp3 路径
    temp_mp3 = output_ogg + ".mp3"
    
    try:
        # 1. 生成 MP3 (edge-tts)
        # 默认使用 zh-CN-YunyangNeural
        voice = os.getenv("EDGE_TTS_VOICE", "zh-CN-YunyangNeural")
        subprocess.run([
            "edge-tts", 
            "--voice", voice, 
            "--text", text, 
            "--write-media", temp_mp3
        ], check=True, capture_output=True)
        
        # 2. 转换为 OGG/Opus (ffmpeg)
        # Telegram 要求 OGG 容器配合 Opus 编码才能识别为语音条
        subprocess.run([
            "ffmpeg", 
            "-i", temp_mp3, 
            "-c:a", "libopus", 
            "-b:a", "32k", 
            "-vbr", "on", 
            "-y", 
            output_ogg
        ], check=True, capture_output=True)
        
        # 3. 清理临时文件
        if os.path.exists(temp_mp3):
            os.remove(temp_mp3)
            
        return True
    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        return False

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: telegram_voice.py <text> <output_ogg_path>")
        sys.exit(1)
        
    text = sys.argv[1]
    output_path = sys.argv[2]
    
    if generate_voice_ogg(text, output_path):
        print(output_path)
    else:
        sys.exit(1)
