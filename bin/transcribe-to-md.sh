#!/bin/bash
# 将 Audacity 导出的音频转录为带 front matter 的 Markdown。
# 用法: transcribe-to-md.sh <音频文件> [输出目录，默认与音频同目录] [语言代码，默认 auto]
set -euo pipefail

MODEL="${WHISPER_MODEL:-$HOME/whisper.cpp/models/ggml-large-v3.bin}"
VAD_MODEL="${WHISPER_VAD_MODEL:-$HOME/.whisper-models/ggml-silero-v5.1.2.bin}"
WHISPER_BIN="${WHISPER_BIN:-/opt/homebrew/bin/whisper-cli}"
OPENCC_CONFIG="${OPENCC_CONFIG:-/opt/homebrew/share/opencc/t2s.json}"

if [ $# -lt 1 ]; then
  echo "用法: $0 <音频文件> [输出目录] [语言代码]" >&2
  exit 1
fi

AUDIO_FILE="$1"
OUT_DIR="${2:-$(dirname "$AUDIO_FILE")}"
LANG="${3:-auto}"

if [ ! -f "$AUDIO_FILE" ]; then
  echo "错误: 找不到音频文件 $AUDIO_FILE" >&2
  exit 1
fi
if [ ! -f "$MODEL" ]; then
  echo "错误: 找不到模型 $MODEL" >&2
  exit 1
fi

BASENAME="$(basename "$AUDIO_FILE")"
STEM="${BASENAME%.*}"
mkdir -p "$OUT_DIR"
TMP_PREFIX="$(mktemp -d)/$STEM"

VAD_ARGS=()
if [ -f "$VAD_MODEL" ]; then
  VAD_ARGS=(--vad --vad-model "$VAD_MODEL")
else
  echo "警告: 找不到 VAD 模型 $VAD_MODEL，跳过静音过滤（长静音可能触发 whisper 幻觉重复）" >&2
fi

"$WHISPER_BIN" \
  -m "$MODEL" \
  -f "$AUDIO_FILE" \
  -l "$LANG" \
  -otxt -of "$TMP_PREFIX" \
  --print-progress false \
  "${VAD_ARGS[@]}" \
  2>/tmp/whisper-transcribe.log

if [ ! -f "${TMP_PREFIX}.txt" ]; then
  echo "错误: 转录失败，日志见 /tmp/whisper-transcribe.log" >&2
  exit 1
fi

DURATION=$(afinfo "$AUDIO_FILE" 2>/dev/null | grep "estimated duration" | awk '{print $3}')
DURATION="${DURATION:-unknown}"
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
MD_FILE="$OUT_DIR/${STEM}.md"

{
  echo "---"
  echo "source_file: $BASENAME"
  echo "duration_seconds: $DURATION"
  echo "model: $(basename "$MODEL")"
  echo "language: $LANG"
  echo "transcribed_at: $NOW"
  echo "---"
  echo
  # whisper.cpp 的 txt 输出每行一段，合并为自然段落（按空行分隔的整段文本）
  BODY="$(sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "${TMP_PREFIX}.txt")"
  if [ -f "$OPENCC_CONFIG" ]; then
    printf '%s' "$BODY" | opencc -c "$OPENCC_CONFIG"
    echo
  else
    echo "警告: 找不到 OpenCC 配置 $OPENCC_CONFIG，跳过繁转简" >&2
    echo "$BODY"
  fi
} > "$MD_FILE"

rm -rf "$(dirname "$TMP_PREFIX")"
echo "已生成: $MD_FILE"
