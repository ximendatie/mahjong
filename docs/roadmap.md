# mahjong 路线图

mahjong 的长期方向是成为一个本地优先的 AI Agent 工作状态伴侣：安静、可信、可扩展，并且容易参与贡献。

## 产品北极星

> 一个用麻将牌状态展示 AI Agent 正在做什么的本地桌面伴侣。

核心原则：

- 默认本地优先、只读观察。
- 提供清晰的隐私控制。
- Provider 的行为需要可解释。
- 先做好小而高频的日常使用体验，再考虑复杂编排能力。
- 新增 Provider 应该有文档、有测试、易于 Review。

## 阶段总览

| 阶段 | 版本 | 目标 | 主要产出 |
| --- | --- | --- | --- |
| 0 | 当前 | 保持基线健康 | App 可构建、测试通过、开源基础设施齐备。 |
| 1 | 0.1.x | 让首次使用可信 | Settings、Provider 开关、诊断信息、首个 Release 包。 |
| 2 | 0.2.x | 让工程基础可扩展 | Provider 注册表、拆分 UI 组件、fixture 测试、标准化状态。 |
| 3 | 0.3.x | 让它成为日常工具 | 菜单栏模式、常驻窗口行为、状态解释、刷新性能。 |
| 4 | 0.4.x | 让外部贡献更容易 | Provider 开发文档、Issue 标签、good first issue、更多 Provider。 |
| 5 | 0.5.x | 让分发体验成熟 | 签名/公证构建、DMG、可重复的 Release 自动化。 |
| 6 | 1.0 | 稳定产品承诺 | 可靠的本地观察工具，具备清晰隐私边界和扩展模型。 |

## 路线图流向

```mermaid
flowchart LR
    A["当前基线"] --> B["0.1 可信首次使用"]
    B --> C["0.2 可扩展 Provider 架构"]
    C --> D["0.3 日常使用体验"]
    D --> E["0.4 贡献者增长"]
    E --> F["0.5 成熟分发"]
    F --> G["1.0 稳定产品承诺"]
```

## 阶段详情

### 阶段 0：当前基线

| 模块 | 状态 |
| --- | --- |
| macOS 麻将牌桌宠 | 已完成 |
| mahjong Board | 已完成 |
| Codex / Claude / Claude Desktop / Hermes 支持 | 初始支持 |
| Terminal / Desktop runtime 检测 | 初始支持 |
| README / LICENSE / CONTRIBUTING / SECURITY | 已完成 |
| CI 和基础测试 | 已完成 |

验收标准：

- `swift build` 通过。
- `swift test` 通过。
- `main` 分支保持可发布状态。

### 阶段 1：可信首次使用

目标版本：`0.1.x`

| 优先级 | 工作项 | 原因 |
| --- | --- | --- |
| P0 | Settings 页面 | 已有基础设置页，后续继续打磨首次使用解释。 |
| P0 | Provider 启用/禁用开关 | 已支持选择 mahjong 读取哪些来源。 |
| P0 | Provider Diagnostics | 已展示路径缺失、关闭、无数据和读取结果状态。 |
| P0 | 隐私模式 | 已隐藏任务标题、摘要、模型、Token 和诊断路径细节。 |
| P0 | README 截图/GIF | 视觉型产品需要直观展示。 |
| P0 | GitHub Release `.zip` | 已有 `script/build_release_zip.sh` 生成 `.build/dist/mahjong.zip`。 |

建议的 Settings 项：

- Provider 开关。
- 刷新间隔。
- 显示/隐藏 Token usage。
- 显示/隐藏本地项目名。
- 隐私模式。

Diagnostics 应展示：

- 数据路径不存在。
- 权限不足。
- Schema 不支持。
- 外部工具不可用，例如 `sqlite3`。
- 读取成功，但没有发现 session。

验收标准：

- 新用户能在 5 分钟内运行 App。
- 每个 Provider 都可以被关闭。
- Provider 失败原因能在 UI 里看到。
- 有 Release notes 和可下载构建产物。

### 阶段 2：可扩展工程基础

目标版本：`0.2.x`

| 优先级 | 工作项 | 原因 |
| --- | --- | --- |
| Done | 引入 `AgentProviderDescriptor` | Provider 元数据已集中管理。 |
| Done | 拆分 `BoardView.swift` | 主视图已拆成侧栏、任务列、任务卡、运行列表、设置和未来计划视图。 |
| Done | 增加 fixture 测试 | Codex、Claude CLI、Claude Desktop、Hermes 均有本地数据夹具覆盖。 |
| Done | 增加标准化状态 | 任务状态已区分进行中、已完成、已中断、已归档。 |
| Done | 标准化 Provider ID | 设置、诊断、任务和运行态均使用稳定 Provider ID。 |

建议的 Provider descriptor 字段：

```swift
struct AgentProviderDescriptor {
    let id: String
    let displayName: String
    let defaultEnabled: Bool
    let dataPaths: [String]
    let privacyDescription: String
}
```

推荐的 UI 拆分：

| 组件 | 职责 |
| --- | --- |
| `BoardView` | 整体布局和 Tab 路由 |
| `TaskColumnView` | 状态列 |
| `TaskCardView` | 单个任务卡片 |
| `AgentRuntimeListView` | 运行中的 Agent 列表 |
| `FutureTasksView` | 未来计划快速记录界面 |
| `AgentIconResolver` | Provider 图标解析 |

状态模型方向：

```mermaid
stateDiagram-v2
    [*] --> Running
    Running --> Completed
    Running --> Stale
    Completed --> History
    Stale --> Completed
    Stale --> History
```

验收标准：

- 已完成：新增 Provider 元数据集中在 `AgentProviderDescriptor`。
- 已完成：新增 Provider 不需要修改无关 UI 文件。
- 已完成：Parser 变更有 fixture 测试覆盖。
- 已完成：UI 能展示用户可理解的任务结果状态。

### 阶段 3：日常使用体验

目标版本：`0.3.x`

| 优先级 | 工作项 | 原因 |
| --- | --- | --- |
| P0 | 菜单栏模式 | 即使 Board 关闭，也能看到关键状态。 |
| P0 | 窗口与常驻行为 | 关闭 Board 时隐藏窗口而不是退出 App，并提供清晰退出入口。 |
| P0 | 空状态与状态解释 | 让无数据、未授权、已中断等状态更容易理解。 |
| P1 | 刷新与性能 | 控制刷新频率，避免 Accessibility 和 provider 扫描造成负担。 |
| Deferred | 权限提示 | 不做启动引导；在用户使用相关能力时再提示，例如 ChatGPT 生成中检测需要辅助功能权限。 |
| Out | 首次启动引导 | 当前阶段不做。 |
| Out | 可选完成通知 | 当前阶段不做。 |
| Out | 未来计划增强 | 当前阶段不继续扩展。 |
| Out | 任务操作 | 当前阶段不做。 |
| Out | 隐私细节扩展 | 当前阶段不做。 |

建议拆分：

1. 菜单栏模式
   - 新增 menu bar extra。
   - 显示当前 running 数。
   - 显示最近完成/中断任务摘要。
   - 提供打开 Board、刷新、退出入口。
   - 设置页增加菜单栏显示开关。

2. 窗口与常驻行为
   - 关闭 Board 时隐藏窗口，不退出 App。
   - Dock、`LSUIElement`、菜单栏行为保持一致。
   - 提供明确的“退出 mahjong”入口。
   - 点击桌宠或菜单栏都能重新打开 Board。
   - 重启后恢复隐私模式、Provider 开关等既有设置。

3. 空状态与状态解释
   - 每个任务列补充清晰空状态。
   - “已中断”列说明只来自明确中断事件。
   - ChatGPT 未授权 Accessibility 时给出下一步操作。
   - Provider 无数据时避免让用户误以为 App 损坏。

4. 刷新与性能
   - 设置页增加刷新间隔。
   - 前台/后台刷新频率区分。
   - 限制 ChatGPT Accessibility 扫描深度和频率。
   - Provider 失败不阻塞其他 Provider。
   - Diagnostics 展示最近刷新时间。

验收标准：

- App 可以全天常驻，且不打扰。
- Board 关闭后仍能通过菜单栏看到关键状态并重新打开。
- ChatGPT 权限缺失、Provider 无数据、任务已中断等状态都有明确解释。
- 刷新频率可控，后台运行不会造成明显性能负担。

### 阶段 4：贡献者增长

目标版本：`0.4.x`

| 优先级 | 工作项 | 原因 |
| --- | --- | --- |
| Done | `docs/provider-development.md` | 降低 Provider PR 的门槛。 |
| Done | Good first issues | 已在 `docs/contributor-tasks.md` 整理可转换成 GitHub issues 的任务。 |
| Done | Issue 标签体系 | 已在 `docs/issue-labels.md` 定义标签用途和建议颜色。 |
| P1 | 更多 Provider 支持 | 通过社区 PR 扩大项目价值。 |

推荐标签：

- `provider`
- `privacy`
- `parser`
- `ui`
- `diagnostics`
- `docs`
- `tests`
- `good first issue`
- `help wanted`
- `release`

候选 Provider：

| Provider | 初始范围 |
| --- | --- |
| Aider | 本地 session 或进程检测 |
| OpenCode | 本地 session 或进程检测 |
| Gemini CLI | 进程和本地 metadata 检测 |
| Cursor / Windsurf | 先做 Desktop app / runtime 检测 |
| Goose / Continue | 如果本地 metadata 安全可用，则读取 metadata |

验收标准：

- 贡献者能根据文档新增 Provider。
- 新 Provider 包含测试。
- Issue 能按贡献类型轻松浏览。

### 阶段 5：成熟分发

目标版本：`0.5.x`

| 优先级 | 工作项 | 原因 |
| --- | --- | --- |
| Done | 自动化 Release 构建 | 已增加 tag 触发的 GitHub Actions release workflow。 |
| Done | `.dmg` 打包 | 已增加 `script/build_release_dmg.sh`。 |
| Done | Code signing | 已增加 `script/sign_app.sh`，支持 Developer ID 或 ad-hoc fallback。 |
| Done | Notarization | 已增加 `script/notarize.sh`，支持 notarytool profile 或 Apple ID credentials。 |
| Done | Changelog 自动化 | 已增加 `CHANGELOG.md` 和 release guide；后续可继续自动生成 notes。 |
| P2 | Sparkle 自动更新 | Release 流程稳定后再考虑。 |

验收标准：

- 用户能下载并打开 App，Gatekeeper 摩擦较低。
- Release 产物能稳定生成。
- 每次 Release 都有 notes 和构建产物。

### 阶段 6：1.0 稳定产品承诺

目标版本：`1.0`

第六阶段不以新增大功能为主，而是收口、验收、稳定化和发布可信度建设。

1.0 应包含：

- 稳定的 Provider registry。
- Settings 和 Provider 开关。
- Provider Diagnostics。
- 隐私模式。
- 可靠的 Release 包。
- 核心 Provider fixture 测试。
- 清晰的数据访问文档。
- 贡献者文档。
- 安静、稳定、适合日常使用的 UI。

#### P0 发布前验收

| 模块 | 任务 | 验收标准 |
| --- | --- | --- |
| 稳定性 | 跑通 `swift build`、`swift test`、release zip、release dmg | 本地和 CI 都能稳定产出构建物。 |
| 常驻体验 | 检查 Board 关闭、菜单栏、桌宠、退出入口 | App 可以全天常驻，不误退出，且能明确退出。 |
| 隐私边界 | 审计 Provider 读取路径、展示字段和隐私模式 | 隐私模式下不暴露标题、摘要、模型、token、token 统计总量、未来计划 notes 和详细诊断路径。 |
| Provider 质量 | Codex、Claude CLI、Claude Desktop、Hermes、ChatGPT、OpenClaw 全量回归 | 每个 Provider 都有明确的有数据、无数据、权限缺失、关闭或失败状态。 |
| Diagnostics | 统一诊断状态和失败文案 | 用户能知道为什么没有数据，以及下一步该做什么。 |
| Release | 准备 1.0 release checklist | 版本号、构建、签名、公证、notes 和附件步骤明确。 |

#### P1 产品打磨

| 模块 | 任务 | 验收标准 |
| --- | --- | --- |
| UI polish | 检查 Board、Settings、Token Usage、Future Tasks、Runtime 列表 | 空状态清晰，长文本不挤压或重叠。 |
| 性能 | 检查刷新频率、后台扫描、Accessibility 读取频率 | 常驻时 CPU 占用稳定，不频繁打扰系统。 |
| Provider registry | 复查新增 Provider 的接入面 | 新 Provider 不需要修改无关 UI 文件。 |
| 测试覆盖 | 补齐核心 parser fixture 和状态归类测试 | 本地数据格式变化时能及时发现回归。 |
| 文档 | 更新 README、隐私文档、架构文档、Provider 开发指南 | 新用户和贡献者能按文档完成安装、理解边界、添加 Provider。 |

#### P2 发布后增强

| 模块 | 任务 | 验收标准 |
| --- | --- | --- |
| 自动更新 | 评估 Sparkle 是否进入 1.0 | 明确做或不做；不做则进入 post-1.0。 |
| 可访问性 | 检查按钮标签、键盘可达性、颜色对比 | 基础可访问性不拖后腿。 |
| 本地化 | 检查中文/英文文档和 UI 文案一致性 | 不出现明显中英状态不一致。 |
| 发布传播 | 整理 launch checklist 和反馈入口 | 1.0 发布后能收集问题和 Provider 需求。 |

1.0 前不优先做：

- 自动控制 Provider 执行任务。
- 云同步。
- 完整对话正文展示。
- 复杂任务编排。
- 登录系统。
- 插件市场。

## 推荐执行顺序

| 顺序 | 版本 | 里程碑 |
| --- | --- | --- |
| 1 | 0.1.0 | Settings、Provider 开关、隐私模式、release zip 脚本已落地；README 截图待补 |
| 2 | 0.1.1 | Provider Diagnostics 已落地；后续继续增强错误细节 |
| 3 | 0.2.0 | `AgentProviderDescriptor`、UI 拆分已落地 |
| 4 | 0.2.1 | Claude 和 Hermes fixture 测试已落地 |
| 5 | 0.3.0 | 菜单栏模式、窗口常驻 |
| 6 | 0.3.1 | 空状态解释、刷新性能 |
| 7 | 0.4.0 | Provider 开发文档、good first issues |
| 8 | 0.5.0 | Release 打包、签名、公证 |

## 最高优先级 Backlog

| 优先级 | Issue 标题 |
| --- | --- |
| Done | Add Settings page for provider toggles |
| Done | Add provider diagnostics panel |
| Done | Add privacy mode |
| P0 | Add screenshot and demo GIF to README |
| Done | Introduce `AgentProviderDescriptor` |
| Done | Split `BoardView` into smaller components |
| Out | Add first-run onboarding |
| Done | Add Claude provider fixture tests |
| Done | Add Claude Desktop provider fixture tests |
| Done | Add Hermes sqlite fixture tests |
| P1 | Add provider development guide |
| Done | Add GitHub release packaging script |
| P2 | Add signed and notarized macOS release flow |
