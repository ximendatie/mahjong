# mahjong

mahjong 是一个轻量级 macOS 桌面伴侣，用来在本机观察 AI Agent 的工作状态，包括桌面应用和终端会话。

它采用本地优先、默认只读的设计：应用帮助你了解各个 Agent 正在做什么，但不会上传数据、修改 provider 配置，也不会控制其他应用。

项目名来自它的交互模型：当多个 Agent 会话正在运行时，悬浮桌面伴侣会在不同麻将牌图标之间切换，让当前负载一眼可见。

## 功能

- 显示一个悬浮的麻将牌桌面伴侣，并在本地 Agent 工作时做出状态反馈。
- 打开 mahjong Board，展示运行中、已完成和已归档的任务卡片。
- 检测受支持的桌面应用和终端 Agent 进程。
- 读取受支持 provider 的本地会话元数据。
- 支持在本地草拟未来计划，方便记录稍后要处理的工作。

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

| Provider | 当前行为 |
| --- | --- |
| Codex Desktop / Codex 本地会话 | 读取 `~/.codex/session_index.jsonl` 和 `~/.codex/sessions/**/*.jsonl`。 |
| Claude 本地会话 | 读取 `~/.claude/projects/**/*.jsonl`。 |
| Claude Desktop 本地会话 | 读取 `~/Library/Application Support/Claude-3p/local-agent-mode-sessions/**/local_*.json` 和 `~/Library/Application Support/Claude-3p/claude-code-sessions/**/local_*.json` 的元数据，并把活跃会话与本地 Claude Desktop `--resume` 进程关联。 |
| Hermes 本地会话 | 读取 `~/.hermes/state.db` 中的会话和消息元数据，并通过 `NSWorkspace` 检测 Hermes Agent 桌面应用、通过 `ps` 检测 Hermes CLI/gateway 进程。 |
| 终端 Agent | 从 `ps` 读取本地进程元数据，并记录匹配到的 Codex、Claude、Hermes 和 OpenClaw 进程。 |
| OpenClaw | 仅检测 OpenClaw Desktop 和 OpenClaw gateway/CLI 进程是否存在。 |
| ChatGPT Desktop | 通过 `NSWorkspace` 检测应用是否存在；MVP 阶段不解析对话数据。 |

## 文档

- [隐私和安全说明](docs/privacy.md)
- [架构概览](docs/architecture.md)
- [路线图](docs/roadmap.md)
- [贡献指南](CONTRIBUTING.md)

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

## 贡献

欢迎提交 issue、想法和 pull request。如果想添加新的 provider，请先阅读 [docs/architecture.md](docs/architecture.md)，并保持 provider 本地优先、只读，以及谨慎选择哪些数据可以出现在 UI 中。
