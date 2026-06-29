# CodeWhisper 项目说明（CLAUDE.md）

> 本文件是所有 agent 协作时的共享上下文。任何 agent 在动手前都应先读本文件。

## 一句话定位

CodeWhisper 是一个**面向中文开发者的本地语音转文字工具**：按住快捷键说话，松开后在本地用 Whisper 完成转录，自动纠正开发者术语，并一键复制 / 自动上屏到当前应用（ChatGPT、Claude、IDE 等）。

## 当前重构目标（利姆露大人的需求）

把原本的 **Python + rumps** 实现，重构为**原生 Swift / SwiftUI macOS 应用**：

- 菜单栏（任务栏）常驻，隐藏 Dock 图标（`LSUIElement = YES`）
- 用户**无需安装 Python / FFmpeg**，开箱即用
- 打包成**单个独立 `.dmg`**，可直接拖入「应用程序」
- 发布到 GitHub Release
- 在保留原功能的基础上，加入更强的原生体验（自动上屏、流式转录、模型管理、开机自启等）

## 必须保留 / 对齐的核心功能（来自 Python 版）

1. 菜单栏图标常驻，录音时图标状态变化（🎙️ → 🔴 → ⏳）
2. **按住快捷键录音、松开自动转录**（hold-to-record，默认 ⌘M，可配置）
3. 转录后**自动复制到剪贴板**，并可选**自动粘贴**到当前聚焦应用
4. **术语纠正**：加载 `dictionaries/programmer_terms.json`（400+ 规则），把误识别的发音纠正成正确术语；短的纯字母数字词用前后边界，长词直接匹配，按错误词长度降序匹配
5. **繁体转简体** + **中文标点规范化**（英文逗号→中文逗号）
6. **幻觉/静音过滤**：静音跳过、重复循环过滤、压缩比阈值
7. **历史记录**管理（持久化、容量限制、清除）
8. 两种转录体验：极速（边录边转）/ 全量（录完带标点）

## 技术架构（Swift 重构方案）

- **转录引擎**：WhisperKit（argmaxinc，CoreML / Apple Neural Engine，纯 Swift Package），替代 Python 的 openai-whisper
- **UI**：SwiftUI `MenuBarExtra`（window 风格），设置/历史用 SwiftUI 视图
- **音频**：`AVAudioEngine` 采集，`AVAudioConverter` 重采样到 16kHz 单声道 Float
- **全局热键**：`NSEvent` 全局监听实现 hold-to-record（需辅助功能权限）
- **自动上屏**：`NSPasteboard` 复制 + `CGEvent` 模拟 ⌘V（需辅助功能权限）
- **持久化**：`UserDefaults`（设置）+ JSON 文件（历史，存于 `~/Library/Application Support/CodeWhisper`）
- **沙盒**：关闭 App Sandbox（菜单栏工具需全局事件监听 + CGEvent 发送 + 网络下载模型）
- **构建**：XcodeGen 由 `mac/project.yml` 生成工程 → `xcodebuild` → ad-hoc 签名 → `.dmg`

## 目录结构

```
CodeWhisper/
├── CLAUDE.md                # 本文件
├── mac/                     # ★ Swift 原生应用（重构产物）
│   ├── project.yml          # XcodeGen 工程定义（含 WhisperKit SPM 依赖）
│   ├── Sources/
│   │   ├── App/             # @main App 入口、AppDelegate、协调器 AppState
│   │   ├── Core/            # 录音、转录、词典、剪贴板、热键、历史、设置
│   │   └── Views/           # SwiftUI 菜单/设置/历史界面
│   └── Resources/           # programmer_terms.json、图标等
├── scripts/build_dmg.sh     # 构建 + 打包 DMG 脚本
├── dictionaries/            # 术语字典（Swift 版直接复用 JSON）
├── config/                  # base_dict / base_config（Python 版遗留，可参考）
├── codewhisper/ , gui/, app.py  # ← Python 旧版（重构完成后归档/删除）
```

## Agent 协作流程

```
利姆露大人 → 紫苑（总调度）
                ├─ 夏尔（复杂需求/技术调研/PRD）→ 哥布塔/哥布奇/哥布藏
                ├─ 朱菜（SwiftUI / 菜单栏 / 热键 UI）
                ├─ 盖鲁德（音频 / WhisperKit 推理 / 持久化 / 上屏）
                ├─ 泰斯塔罗斯（XcodeGen / 构建 / 签名 / DMG / git / Release）
                ├─ 迪亚波罗（编译验证 / 测试）
                └─ 苍影（第一性原理审核，P0 上报紫苑）
```

约定：
- 所有需求经紫苑分发；紫苑明确写出「执行人 / 任务 / 产出 / 依赖」
- 执行 agent **只做分配的任务**，文件头写中文修改说明，完成后回报改了哪些文件、暴露了哪些接口
- 闭环：执行 → 迪亚波罗测试 → 苍影审核 → P0 回紫苑重新调度

## 文档与注释语言规则

- CLAUDE.md / README.md / **所有代码注释**一律用**中文**
- 标识符（变量名/函数名/类名）保持英文

## 构建与发布命令

```bash
# 生成 Xcode 工程
cd mac && xcodegen generate
# 构建
xcodebuild -project mac/CodeWhisper.xcodeproj -scheme CodeWhisper -configuration Release build
# 一键打包 DMG（构建 + ad-hoc 签名 + create-dmg）
bash scripts/build_dmg.sh
```

## 交付目标（DoD）

- [ ] `mac/` 下 Swift 工程可被 `xcodebuild` 成功构建为 `CodeWhisper.app`
- [ ] 应用菜单栏常驻、hold-to-record、本地转录、术语纠正、自动上屏、历史记录均可用
- [ ] 产出单个 `CodeWhisper.dmg`
- [ ] 发布到 GitHub Release（`LeoLee0812/CodeWhisper`）
- [ ] README 更新为原生应用安装说明
