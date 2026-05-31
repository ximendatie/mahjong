# 贡献指南

感谢你帮助 mahjong 变得更有用。这个项目有意保持小而清晰：
本地观察、明确的隐私边界，以及快速迭代。

## 开发环境

要求：

- macOS 14 或更新版本
- Swift 6 工具链
- ImageMagick，可选；如果你希望 `script/build_app.sh` 重新生成图标，需要安装 `magick`

常用命令：

```bash
swift build
swift test
script/build_and_run.sh
```

## Pull Request Checklist

- 保持 provider 行为本地优先、只读。
- 不上传本地 session 数据，也不把它发送到远程服务。
- 不写入 provider 的配置、session 或缓存文件。
- 默认避免展示完整对话正文。
- 如果修改 parser 或状态判断逻辑，请新增或更新测试。
- 如果用户可见行为或 provider 行为发生变化，请更新 `README.md`、`README.zh-CN.md` 或 `docs/architecture.md`。

## 添加 Provider

请先阅读 [docs/provider-development.md](docs/provider-development.md)。简要规则：

1. 如果可以安全地从本地元数据推导任务卡片，添加 `AgentTaskProvider`。
2. 如果只能检测应用或进程是否运行，添加 `AgentRuntimeProvider`。
3. 优先使用明确的元数据、时间戳和状态事件，不要依赖解析消息正文。
4. 文件缺失、schema 未知或权限不足时，应返回空数据或部分数据，不要让 App 崩溃。
5. 添加基于 fixture 的测试，覆盖代表性的本地文件或数据库行。

适合新贡献者的任务整理在 [docs/contributor-tasks.md](docs/contributor-tasks.md)。

## 报告安全或隐私问题

请不要在公开 issue 中粘贴敏感本地路径、prompt、session 文件或数据库内容。
请参考 `SECURITY.zh-CN.md` 中的说明。
