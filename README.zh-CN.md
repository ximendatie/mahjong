# mahjong

![mahjong 可视化展示](docs/assets/showcase.png)

[打开可视化展示页](docs/showcase.html) ·
[下载 Release](https://github.com/ximendatie/mahjong/releases) ·
[发布传播手册](docs/launch.md)

mahjong 是一个本地优先的 macOS 桌面伴侣，用来观察 Codex、Claude、ChatGPT、Hermes 和其他 AI Agent 在桌面应用与终端会话里的工作状态。

它采用本地优先、默认只读的设计：应用帮助你了解各个 Agent 正在做什么，但不会上传数据、修改 provider 配置，也不会控制其他应用。

项目名来自它的交互模型：当多个 Agent 会话正在运行时，悬浮桌面伴侣会在不同麻将牌图标之间切换，让当前负载一眼可见。

## 为什么值得试

- 不需要在窗口、标签页和终端之间来回找，就能看到哪些本地 Agent 正在运行。
- 用一个很小的悬浮桌面伴侣，让 Agent 状态保持可见。
- 只查看本地任务元数据，同时保留清晰的隐私边界。
- 新 Provider 可以通过小而可审查的 parser 和 runtime 集成接入。

## 功能

- 显示一个悬浮的麻将牌桌面伴侣，并在本地 Agent 工作时做出状态反馈。
- 在程序坞显示 mahjong 入口，使用红中麻将牌作为应用图标。
- 支持在设置中隐藏 Dock 入口，只保留菜单栏和桌宠常驻。
- 打开 mahjong Board，展示运行中、已完成和已归档的任务卡片。
- 检测受支持的桌面应用和终端 Agent 进程。
- 显示当前版本，并可检查 GitHub Release 上的手动更新。
- 读取受支持 provider 的本地会话元数据。
- 支持在本地草拟未来计划，方便记录稍后要处理的工作。

## 项目状态

mahjong 还处在早期阶段，但已经适合本地试用。当前重点是把首次使用体验做可信：Provider 控制、诊断信息、隐私默认值和可下载 Release 包。

## 运行

```bash
script/build_and_run.sh
```

脚本会构建本地 `.app` 包到 `.build/mahjong.app`，并通过 macOS LaunchServices 打开它。

当前版本包含本地 mock 任务数据。点击悬浮伴侣可以打开 Agent Board，然后通过看板控件添加、完成和归档示例任务。

## 环境要求

- macOS 14 或更新版本
- Swift 6 工具链
- ImageMagick 的 `magick` 命令，可选，仅在本地 bundle 构建时重新生成应用图标需要

## 构建

```bash
swift build
```

## 测试

```bash
swift test
```

## 打包发布 Zip

```bash
script/build_release_zip.sh
```

发布脚本会构建 `.build/mahjong.app`，并打包为 `.build/dist/mahjong.zip`。

## 安全边界

mahjong 默认只做只读的本地观察：

- 默认不展示完整对话正文。任务卡片只在字段可用时展示线程标题、状态、模型、provider 和 token 用量。
- 不写入 Codex、Claude、ChatGPT 或终端 Agent 的配置文件。
- 不控制 Codex Desktop、Claude Desktop、ChatGPT Desktop、终端 Agent 或任何 provider 应用。
- 不发送消息、不执行命令，也不触发 provider 侧动作。
- 不上传本地会话数据，也不连接远程服务。

## 当前支持的 Provider

| Provider | 任务元数据 | 运行态检测 | 权限说明 |
| --- | --- | --- | --- |
| Codex Desktop / Codex 本地会话 | 读取 `~/.codex/session_index.jsonl` 和 `~/.codex/sessions/**/*.jsonl`。 | 匹配终端进程。 | 仅读取本地文件。 |
| Claude 本地会话 | 读取 `~/.claude/projects/**/*.jsonl`。 | 匹配终端进程。 | 仅读取本地文件。 |
| Claude Desktop 本地会话 | 读取 `~/Library/Application Support/Claude-3p/local-agent-mode-sessions/**/local_*.json` 和 `~/Library/Application Support/Claude-3p/claude-code-sessions/**/local_*.json` 的元数据。 | 把活跃会话与本地 Claude Desktop `--resume` 进程关联。 | 仅读取本地文件。 |
| Hermes 本地会话 | 读取 `~/.hermes/state.db` 中的会话和消息元数据。 | 通过 `NSWorkspace` 检测 Hermes Agent 桌面应用，并通过 `ps` 检测 Hermes CLI/gateway 进程。 | 需要本地 SQLite 元数据存在。 |
| 终端 Agent | 不解析对话内容。 | 从 `ps` 读取 Codex、Claude、Hermes 和 OpenClaw 的进程元数据。 | 仅使用进程列表。 |
| OpenClaw | 暂不解析任务元数据。 | 仅检测 OpenClaw Desktop 和 OpenClaw gateway/CLI 进程是否存在。 | 仅做存在性检测。 |
| ChatGPT Desktop | 不解析对话正文；使用本地对话缓存修改时间作为最近活动兜底。 | 通过 `NSWorkspace` 检测应用是否运行，通过 Accessibility 按钮标签判断生成状态。 | Accessibility 是可选能力，只用于判断生成状态标签。 |
| Trae CN | 读取 ai-agent 日志中的时间戳和 session/task 标识；不解析对话正文。 | 通过 `NSWorkspace` 检测 Trae CN 桌面端运行态，并用进程列表兜底。 | 仅使用本地日志元数据。 |

## 文档

- [视觉展示页](docs/showcase.html)
- [发布传播手册](docs/launch.md)
- [隐私和安全说明](docs/privacy.md)
- [架构概览](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [Provider 开发指南](docs/provider-development.md)
- [Provider scaffold](docs/provider-scaffold.md)
- [自动更新策略](docs/auto-update.md)
- [贡献者任务看板](docs/contributor-tasks.md)
- [发布指南](docs/release.md)
- [贡献指南](CONTRIBUTING.zh-CN.md) / [English](CONTRIBUTING.md)
- [安全政策](SECURITY.zh-CN.md) / [English](SECURITY.md)

## 路线图

适合贡献的方向：

- Provider 开关和轻量设置界面。
- 更多本地 Agent provider。
- 对长时间运行或暂停会话做更准确的状态推断。
- 签名和 notarization 的发布构建。
- 菜单栏模式和通知偏好。
- 更多 UI polish 和无障碍改进。
- 本地化 UI 文案。
- 扩展 provider 解析器的测试覆盖。

## 帮它被更多人看到

- Star 或转发给同时运行多个本地 Agent 的开发者。
- 下载 Release 包试用，并反馈首次运行卡在哪里。
- 为你想要的 Provider 开一个 issue。
- 从 [贡献者任务看板](docs/contributor-tasks.md) 里挑一个小任务。

建议 GitHub Topics：

`macos`, `swift`, `ai-agents`, `codex`, `claude`, `chatgpt`, `local-first`,
`agent-monitoring`, `desktop-companion`

## 贡献

欢迎提交 issue、想法和 pull request。如果想添加新的 provider，请先阅读 [docs/architecture.md](docs/architecture.md)，并保持 provider 本地优先、只读，以及谨慎选择哪些数据可以出现在 UI 中。
