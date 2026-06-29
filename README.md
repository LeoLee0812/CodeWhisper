# CodeWhisper 🎤

**针对中文语境优化的语音转文字工具，一键转录至剪贴板，打破网页端限制，实现与各家大模型（ChatGPT/Grok/Gemini 等）的无缝对话。** | Local Speech-to-Text for Any AI

> **v1.0 起，CodeWhisper 已重构为原生 Swift / SwiftUI macOS 应用** —— 菜单栏常驻、Apple Neural Engine 加速、模型内置离线开箱即用、单个 `.dmg` 安装，无需 Python / FFmpeg 环境。旧的 Python 版仍保留在仓库中作为参考（见文末「Python 旧版」）。

---

## 为什么需要 CodeWhisper？

### 痛点 1：打字速度跟不上思维速度

和 AI 高强度对话时，你的思路文思泉涌，但打字成了瓶颈：

```
你的大脑：💨💨💨 "我想让你帮我优化这个算法，用双指针..."
你的手指速度：🐢 "我...想...让...你..."
```

**键盘成为了 AI 的牢笼。语音输入是解决人机交互带宽瓶颈的最自然方式。**

### 痛点 2：想用语音，但大厂的方案对中文程序员不友好

你想用语音输入解决打字慢的问题，但各大厂商的语音转文字都有坑：

| 厂商 | 问题 | 来源 |
|------|------|------|
| **ChatGPT** | 由于网络波动或语音输入 tokens 限制，超过 20 秒经常发生吞用户录音的情况 | [OpenAI 官方论坛](https://community.openai.com/t/transcription-failures-with-voice-messages-on-chatgpt/705251) |
| **Gemini** | 中文支持差，说的越多越吞文字，用户反馈 "Voice Recognition simply does not work" | [Google 支持社区](https://support.google.com/gemini/thread/342537101) |
| **Grok** | 语音模式需要 Premium+ 订阅 | [Social Media Today](https://www.socialmediatoday.com/news/xai-x-formerly-twitter-adds-grok-voice-mode/740820/) |
| **Mac 自带** | 依旧采用上一代 ASR 技术，转录中文后语义直接崩塌 | - |

> 各大厂商针对中文社区并不能做很好的特定优化，加之网络本身就不稳定，更容易出问题。

### 解决思路：Whisper 本地化

发现 ChatGPT 背后用的 **Whisper** 模型转录效果其实很好，问题出在网络和平台限制上。

**所以把 Whisper 提取出来，做成本地工具**：
- 本地运行，不怕断网
- 不绑定任何平台，想喂哪个 AI 就粘贴到哪个

### 双向奔赴：大模型的兜底推理能力

一个句子中即使有一两个词识别错了，并不影响整个语义。下游的大模型能通过上下文捕获你的真实意图：

```
你说的："帮我用双指针解决这个力扣题"
识别成："帮我用双只针解决这个利扣题"
大模型：完全理解 ✅（上下文推断）
```

**语音输入层有些小错误没关系，下游大模型会兜底。** 当然，能更准确肯定更好——这就是为什么 CodeWhisper 还做了特定术语的字典纠正功能。

---

## CodeWhisper 的解决方案

```
┌─────────────────────────────────────────────────────────┐
│  🎙️ 按住快捷键录音（Mac 菜单栏常驻）                        │
│       ↓                                                 │
│  🧠 WhisperKit 本地转录（CoreML / ANE，不怕断网）           │
│       ↓                                                 │
│  🔧 程序员术语自动纠正 + 繁简转换 + 标点规范化               │
│       ↓                                                 │
│  📋 自动复制到剪贴板，并可自动粘贴到当前应用                  │
│       ↓                                                 │
│  🤖 直达任意 AI：ChatGPT / Claude / Gemini / Grok / ...   │
└─────────────────────────────────────────────────────────┘
```

**核心优势：**
- ✅ **纯本地、离线开箱即用**：模型与 tokenizer 已内置进 App，首次启动无需联网
- ✅ **原生 + ANE 加速**：基于 [WhisperKit](https://github.com/argmaxinc/WhisperKit)，`large-v3-turbo` 模型在 Apple Neural Engine 上数十倍实时速度，发热小、续航好
- ✅ **不绑定平台**：想和哪个 AI 聊就粘贴到哪个
- ✅ **中文开发优化**：400+ 术语纠正规则，社区共建
- ✅ **零依赖安装**：单个 `.dmg`，无需 Python / FFmpeg

---

## Quick Start 🚀

### 系统要求

- macOS 14 (Sonoma) 及以上
- Apple Silicon（M 系列芯片）

### 安装（推荐：下载 DMG）

1. 到 [Releases](https://github.com/LeoLee0812/CodeWhisper/releases) 下载最新的 **`CodeWhisper.dmg`**
2. 双击打开 dmg，把 **CodeWhisper** 拖入「应用程序」文件夹
3. **首次启动**：当前为本地 ad-hoc 签名（未做 Apple 公证），Gatekeeper 会拦一下。任选其一绕过：
   - 在「应用程序」里 **右键点 CodeWhisper → 打开**，在弹窗中再点「打开」
   - 或在终端执行：`xattr -dr com.apple.quarantine /Applications/CodeWhisper.app`
4. **授权权限**（系统设置 → 隐私与安全性）：
   - **麦克风**：用于录音
   - **辅助功能**：用于全局快捷键监听 + 自动粘贴上屏

启动后菜单栏右上角会出现 🎙️ 图标（应用不在 Dock 显示，常驻菜单栏）。

> 模型已随 App 内置（`large-v3-turbo`，约 600MB），**首次启动即可离线使用**，无需等待下载。
>
> ⏳ **关于首次启动**：第一次运行时，CoreML 会针对你的芯片对模型做一次性 Apple Neural Engine 编译（约 1-2 分钟，菜单栏图标显示加载中）。这一步只发生一次，之后会走缓存、秒级就绪。建议安装后先打开 App 让它在后台完成编译，再开始使用。

---

## 使用方式

### 按住说话，松开上屏

| 菜单栏图标 | 含义 |
|------|------|
| 🎙️ | 待命 |
| 🔴 | 正在录音 |
| ⏳ | 正在转录 |

**工作流程：**
1. **按住 `⌘M`**（默认快捷键）开始录音
2. 说出你的内容
3. **松开** → 自动转录 → 术语纠正 → 复制到剪贴板并**自动粘贴**到当前光标处
4. 直接在 ChatGPT / Claude / IDE 等任意应用里继续

也可以点击菜单栏图标，从菜单里手动开始/停止录音、查看历史、打开设置。

### 设置项

- **模型**：默认 `large-v3-turbo`（内置）；可切换高精度 `large-v3` 或省空间 `small`（非内置的会在首次选用时联网下载）
- **快捷键**：自定义 hold-to-record 组合键（默认 `⌘M`）
- **转录模式**：
  - **全量模式（默认）**：录完整段再转，标点/上下文更准
  - **流式模式**：按住说话时**边说边实时出字**（基于 WhisperKit 实时流式器），松开后走同一套术语纠错再上屏
- **输出方式**：仅复制到剪贴板 / 复制并自动粘贴
- **开机自启**：登录时自动常驻菜单栏
- **提示音**：转录完成提示音开关

### 后处理管线（与 Python 版对齐）

录音 → WhisperKit 本地转录（锁定中文 `zh`）→ 幻觉/静音/重复循环过滤 → 繁体转简体 → 中文标点规范化 → **400+ 术语字典兜底纠错** → 上屏 + 写入历史。

---

## 🧠 术语纠错引擎

各大语音识别对程序员术语的识别都很差，CodeWhisper 用社区字典自动纠正：

| 说的话 | 普通识别 | CodeWhisper |
|--------|----------|-------------|
| 提PR | "TPR" ❌ | 提PR ✅ |
| Mentor | "门特尔" ❌ | Mentor ✅ |
| MySQL | "my circle" ❌ | MySQL ✅ |
| Apollo | "阿波罗" ❌ | Apollo ✅ |
| 提测 | "体测" ❌ | 提测 ✅ |

**纠错算法**：短的纯字母数字词（≤3 字符）加前后边界，避免子串误匹配；长词直接匹配；按错误词长度降序匹配，先长后短避免覆盖。字典还会被编码进 Whisper 的 prompt，引导模型优先识别这些术语。

### 📚 社区驱动的术语字典

**覆盖 13+ 大分类，400+ 条术语规则**（持续收录大家提供的术语～）：

| 分类 | 示例术语 |
|------|----------|
| 职场术语 | 提PR/提MR、提测、排期、逾期、联调、灰度、验收、复盘、风险评估、需求拆解... |
| 大学 / 求职 | 秋招、春招、校招、社招、offer、CV、实习、技术栈、笔试、面试、刷题、年包、SP、SSP... |
| 编程语言 | Python、Java、Go、JavaScript、TypeScript、Rust、C++、C#、PHP、Kotlin... |
| 开发工具 | IDEA、VSCode、WebStorm、PyCharm、Goland、Vim、Postman、Git、GitHub... |
| 技术概念 | API、REST、GraphQL、SQL、ORM、CRUD、MVC、Token、设计模式... |
| 后端开发 | Spring、SpringBoot、Kafka、Zookeeper、Apollo、Arthas、RPC、QPS、TPS... |
| 数据库 | MySQL、PostgreSQL、MongoDB、Redis、ES、慢SQL、缓存击穿、缓存雪崩... |
| DevOps | Docker、Kubernetes、K8s、Maven、Gradle、npm、Yarn、CI/CD、流水线... |
| 运维 / 协议 / 硬件 | Nginx、HTTP/HTTPS、TCP/UDP、三次握手、macOS、Linux、ARM... |

> 完整规则见 [`dictionaries/programmer_terms.json`](./dictionaries/programmer_terms.json)，欢迎提 Issue / PR 补充。字典是与代码低耦合的纯 JSON，理论上可迁移到医疗、法律等其它行业。

---

## 模型说明

基于 [WhisperKit](https://github.com/argmaxinc/WhisperKit)（CoreML），在 Apple Neural Engine 上推理：

| 模型 | 体积 | 中文准确率 | 说明 |
|------|------|-----------|------|
| `large-v3-turbo` | ~600MB | 高 | **默认，已内置**，速度/准确率/续航最佳平衡 |
| `large-v3` | ~950MB | 最高 | 追求极致准确率，首次选用时下载 |
| `small` | ~220MB | 中 | 省空间，首次选用时下载 |

> `tiny` / `base` 中文准确率不足，不建议用于中文。

---

## 从源码构建 🔨

需要 Xcode 15+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、[create-dmg](https://github.com/create-dmg/create-dmg)（`brew install xcodegen create-dmg`）。

```bash
# 1. 生成 Xcode 工程
cd mac && xcodegen generate

# 2. 直接用 Xcode 构建运行，或命令行构建
xcodebuild -project mac/CodeWhisper.xcodeproj -scheme CodeWhisper -configuration Release build

# 3. 一键打包成内置模型的单文件 DMG（构建 + ad-hoc 签名 + 内置模型/tokenizer + create-dmg）
bash scripts/build_dmg.sh
```

> `build_dmg.sh` 会把 `mac/Models/<模型>` 与 `mac/Models/tokenizer` 拷进 `App.app/Contents/Resources/Models/` 实现离线内置。模型文件较大、不入 Git，可用 `huggingface-cli` 从 `argmaxinc/whisperkit-coreml`（模型）和 `openai/whisper-large-v3`（tokenizer）下载到 `mac/Models/` 后再打包。

项目结构与 Agent 协作约定见 [`CLAUDE.md`](./CLAUDE.md)。

---

## 技术架构

| 模块 | 实现 |
|------|------|
| UI / 菜单栏 | SwiftUI `MenuBarExtra`（`LSUIElement` 隐藏 Dock 图标） |
| 转录引擎 | WhisperKit（CoreML / Apple Neural Engine） |
| 音频采集 | `AVAudioEngine` + `AVAudioConverter`（重采样到 16kHz 单声道） |
| 全局快捷键 | `NSEvent` 全局监听实现 hold-to-record |
| 自动上屏 | `NSPasteboard` 复制 + `CGEvent` 模拟 ⌘V |
| 术语 / 繁简 / 标点 | 移植自 Python 版的纠错与归一化逻辑（`StringTransform` 繁转简） |
| 持久化 | `UserDefaults`（设置）+ JSON（历史，存于 Application Support） |

---

## License 📄

MIT License - 详见 [LICENSE](./LICENSE)

## 参与贡献 ❤️

- 🐛 报告转录错误和识别问题
- 📝 添加新的术语修正规则（编辑 `dictionaries/programmer_terms.json`）
- 👀 反馈 Bug 或添加新功能
- 📚 联系邮箱：1656839861un@gmail.com

详见 [CONTRIBUTING.md](./CONTRIBUTING.md)

---

## Python 旧版（Legacy）

v1.0 之前的 Python + rumps 实现仍保留在仓库：`app.py`、`codewhisper/`、`gui/`、`requirements.txt`。它支持 Mac 菜单栏与 Windows 悬浮球，依赖 Python 环境与 FFmpeg。如果你在非 Apple Silicon 设备上、或想用 NVIDIA GPU 加速，可参考旧版：

```bash
pip install -r requirements.txt
python app.py
```

> 原生 macOS 版是当前主线，Python 版不再新增功能。
