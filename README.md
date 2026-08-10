# VoiceCapture

批量把 macOS 上任意 App 播放的外放声音录下来，本地转录成带 front matter 的 Markdown 文本。全程本地跑（whisper.cpp），不上传任何音频到第三方服务。

## 原理

1. `voice-capture-agent.sh start` 把系统输出切到一个 Multi-Output Device（真实输出 + [BlackHole](https://github.com/ExistentialAudio/BlackHole) 虚拟声卡的组合），这样你能听到声音的同时，`ffmpeg` 也在从 BlackHole 里把这份输出录下来。
2. `voice-capture-agent.sh stop` 结束录音、把系统输出切回原设备，自动调用 `transcribe-to-md.sh` 转录。
3. `transcribe-to-md.sh` 用 [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 的 `whisper-cli` 做语音转文字，用 OpenCC 把繁体转简体，输出一份带 front matter（来源文件、时长、模型、语言、转录时间）的 `.md` 文件。

## 前置依赖

- [BlackHole 2ch](https://github.com/ExistentialAudio/BlackHole)：`brew install --cask blackhole-2ch`
- 用「音频 MIDI 设置」（Audio MIDI Setup）手动创建一个 **Multi-Output Device**，勾选你的真实输出设备 + BlackHole 2ch
- [SwitchAudioSource](https://github.com/deweller/switchaudio-osx)：`brew install switchaudio-osx`
- `ffmpeg`：`brew install ffmpeg`
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) 编译好的 `whisper-cli`，以及一个 ggml 模型（默认找 `~/whisper.cpp/models/ggml-large-v3.bin`）
  - 可选：一个 VAD 模型（默认找 `~/.whisper-models/ggml-silero-v5.1.2.bin`），用来过滤长静音，减少 whisper 的幻觉重复
- OpenCC：`brew install opencc`（默认用 `t2s.json` 配置做繁转简）

## 用法

```bash
voice-capture-agent.sh start    # 开始录音（自动切到 Multi-Output 设备）
voice-capture-agent.sh stop     # 停止录音，恢复原输出设备，自动转录成 .md
voice-capture-agent.sh status   # 查看当前是否在录音
```

也可以单独对一个已有的音频文件跑转录：

```bash
transcribe-to-md.sh <音频文件> [输出目录，默认与音频同目录] [语言代码，默认 auto]
```

## 数据目录（不在本仓库里）

脚本默认把录音和转录结果存在 `~/VoiceCapture/recordings` 和 `~/VoiceCapture/transcripts`，这两个目录不随本仓库同步（本地个人数据，可能涉及录制内容的版权/隐私，不适合上传）。

## 环境变量（可覆盖默认路径）

| 变量 | 默认值 |
|---|---|
| `WHISPER_MODEL` | `~/whisper.cpp/models/ggml-large-v3.bin` |
| `WHISPER_VAD_MODEL` | `~/.whisper-models/ggml-silero-v5.1.2.bin` |
| `WHISPER_BIN` | `/opt/homebrew/bin/whisper-cli` |
| `OPENCC_CONFIG` | `/opt/homebrew/share/opencc/t2s.json` |
