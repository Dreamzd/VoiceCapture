#!/bin/bash
# 本地语音录制 + 转录 agent。
# 用法:
#   voice-capture-agent.sh start   开始录音（自动切到 Multi-Output 设备）
#   voice-capture-agent.sh stop    停止录音，恢复原输出设备，自动转录成 .md
#   voice-capture-agent.sh status  查看当前状态
#
# 前置条件（一次性手动完成，见文档）：
#   1. brew install --cask blackhole-2ch
#   2. 用 Audio MIDI Setup 创建一个 Multi-Output Device，勾选你的真实输出设备 + BlackHole 2ch
#   3. 把下面 OUTPUT_DEVICE 改成你创建的 Multi-Output 设备的名字（默认叫 "Multi-Output Device"）
set -euo pipefail

BASE_DIR="$HOME/VoiceCapture"
REC_DIR="$BASE_DIR/recordings"
TXT_DIR="$BASE_DIR/transcripts"
STATE_FILE="$BASE_DIR/.state"
FAIL_LOG="$BASE_DIR/failures.log"

INPUT_DEVICE="BlackHole 2ch"          # ffmpeg 录音读取的虚拟声卡
OUTPUT_DEVICE="Multi-Output Device"    # 录音期间系统输出切到的设备（真实输出 + BlackHole 的组合）
TRANSCRIBE_SCRIPT="$HOME/bin/transcribe-to-md.sh"

mkdir -p "$REC_DIR" "$TXT_DIR"

log_fail() {
  echo "$(date -u +%FT%TZ) FAIL $1 $2" >> "$FAIL_LOG"
}

cmd="${1:-}"

case "$cmd" in
  start)
    if [ -f "$STATE_FILE" ]; then
      echo "已经在录音中：" >&2
      cat "$STATE_FILE" >&2
      exit 1
    fi

    if ! SwitchAudioSource -a -t output | grep -qx "$INPUT_DEVICE"; then
      echo "错误: 找不到输入设备 '$INPUT_DEVICE'。请先安装 BlackHole: brew install --cask blackhole-2ch" >&2
      exit 1
    fi
    if ! SwitchAudioSource -a -t output | grep -qx "$OUTPUT_DEVICE"; then
      echo "错误: 找不到输出设备 '$OUTPUT_DEVICE'。请先在 Audio MIDI Setup 里创建 Multi-Output Device（真实输出 + BlackHole 2ch）" >&2
      exit 1
    fi

    ORIGINAL_DEVICE="$(SwitchAudioSource -c -t output)"
    SESSION="$(date +%Y%m%d-%H%M%S)"
    WAV_FILE="$REC_DIR/$SESSION.wav"

    SwitchAudioSource -s "$OUTPUT_DEVICE" -t output

    ffmpeg -f avfoundation -i ":$INPUT_DEVICE" -ar 16000 -ac 1 -y "$WAV_FILE" \
      > "$BASE_DIR/ffmpeg-$SESSION.log" 2>&1 &
    REC_PID=$!

    # 确认 ffmpeg 真的起来了，没有立刻退出（比如设备被占用/权限没给）
    sleep 1
    if ! kill -0 "$REC_PID" 2>/dev/null; then
      SwitchAudioSource -s "$ORIGINAL_DEVICE" -t output
      echo "错误: ffmpeg 启动后立即退出，日志见 $BASE_DIR/ffmpeg-$SESSION.log" >&2
      exit 1
    fi

    cat > "$STATE_FILE" <<EOF
SESSION="$SESSION"
WAV_FILE="$WAV_FILE"
REC_PID="$REC_PID"
ORIGINAL_DEVICE="$ORIGINAL_DEVICE"
EOF
    echo "录音已开始: $WAV_FILE"
    echo "系统输出已切到: ${OUTPUT_DEVICE} (真实设备保存为: ${ORIGINAL_DEVICE}, stop 时自动恢复)"
    ;;

  stop)
    if [ ! -f "$STATE_FILE" ]; then
      echo "当前没有在录音" >&2
      exit 1
    fi
    # shellcheck disable=SC1090
    source "$STATE_FILE"

    kill -INT "$REC_PID" 2>/dev/null || true
    for _ in $(seq 1 10); do
      kill -0 "$REC_PID" 2>/dev/null || break
      sleep 0.5
    done

    SwitchAudioSource -s "$ORIGINAL_DEVICE" -t output
    rm -f "$STATE_FILE"

    if [ ! -s "$WAV_FILE" ]; then
      log_fail "$WAV_FILE" "录音文件为空或未生成"
      echo "错误: 录音文件为空，已记录到 $FAIL_LOG" >&2
      exit 1
    fi

    echo "录音已停止: $WAV_FILE"
    echo "开始转录..."
    if "$TRANSCRIBE_SCRIPT" "$WAV_FILE" "$TXT_DIR"; then
      echo "完成: $TXT_DIR/$(basename "${WAV_FILE%.wav}").md"
    else
      log_fail "$WAV_FILE" "whisper 转录失败"
      echo "错误: 转录失败，已记录到 $FAIL_LOG" >&2
      exit 1
    fi
    ;;

  status)
    if [ -f "$STATE_FILE" ]; then
      echo "录音中:"
      cat "$STATE_FILE"
    else
      echo "空闲"
    fi
    ;;

  *)
    echo "用法: $0 {start|stop|status}" >&2
    exit 1
    ;;
esac
