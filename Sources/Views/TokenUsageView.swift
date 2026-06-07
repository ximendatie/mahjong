import SwiftUI
import AppKit

struct TokenUsageView: View {
    @ObservedObject var taskStore: AgentTaskStore
    @State private var selectedRange = TokenUsageTimeRange.all
    @State private var codexUsageLimitState = CodexUsageLimitViewState.loading
    @State private var isCodexUsageLimitRefreshing = false
    @State private var claudeUsageSummary: ClaudeTokenUsageSummary? = nil

    private var summaries: [TokenUsageSummary] {
        taskStore.tokenUsageSummaries(for: selectedRange)
    }

    private var totalTokens: Int {
        summaries.reduce(0) { $0 + $1.totalTokens }
    }

    private var totalRecords: Int {
        summaries.reduce(0) { $0 + $1.taskCount }
    }

    private var headerSummary: String {
        if taskStore.isPrivacyModeEnabled {
            return "Token statistics hidden by privacy mode"
        }

        return "\(summaries.count) 个 Agent · \(Formatters.tokens(totalTokens)) tokens"
    }

    private var sessionTasks: [AgentTask] {
        taskStore.tasks
            .filter { task in
                task.tokenUsage > 0 && selectedRange.contains(task.updatedAt)
            }
            .sorted { lhs, rhs in
                if lhs.tokenUsage != rhs.tokenUsage {
                    return lhs.tokenUsage > rhs.tokenUsage
                }
                return lhs.updatedAt > rhs.updatedAt
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if taskStore.isPrivacyModeEnabled {
                TokenUsageEmptyState(
                    systemImage: "eye.slash",
                    title: "隐私模式已开启",
                    message: "Token 统计在隐私模式下隐藏。"
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        CodexRemainingUsageCard(
                            state: codexUsageLimitState,
                            isRefreshing: isCodexUsageLimitRefreshing,
                            onRefresh: {
                                Task {
                                    await refreshCodexUsageLimits(showLoading: true)
                                }
                            }
                        )

                        ClaudeTokenUsageCard(summary: claudeUsageSummary)

                        if summaries.isEmpty {
                            TokenUsageEmptyState(
                                systemImage: "chart.bar.xaxis",
                                title: "暂无 token 记录",
                                message: "当前时间范围内还没有可统计的本地记录。"
                            )
                            .frame(minHeight: 320)
                        } else {
                            TokenUsageOverview(
                                summaries: summaries,
                                totalTokens: totalTokens,
                                totalRecords: totalRecords
                            )
                            TokenUsageDistributionBar(
                                summaries: summaries,
                                totalTokens: totalTokens
                            )
                            SessionTokenTreemapView(
                                tasks: sessionTasks,
                                totalTokens: totalTokens
                            )
                        }
                    }
                    .padding(.bottom, 18)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            claudeUsageSummary = computeClaudeUsage(from: taskStore.tasks)
            await refreshCodexUsageLimits(showLoading: true)

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else {
                    return
                }
                await refreshCodexUsageLimits(showLoading: false)
            }
        }
        .onChange(of: taskStore.tasks.map(\.updatedAt).max()) { _, _ in
            claudeUsageSummary = computeClaudeUsage(from: taskStore.tasks)
            Task {
                await refreshCodexUsageLimits(showLoading: false)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent Token 统计")
                    .font(.title2.weight(.semibold))
                Text(headerSummary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("时间范围", selection: $selectedRange) {
                ForEach(TokenUsageTimeRange.allCases) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 280)
        }
    }

    private func computeClaudeUsage(from tasks: [AgentTask]) -> ClaudeTokenUsageSummary? {
        let claudeProviderIDs: Set<AgentProviderID> = [.claudeCLI, .claudeDesktop]
        let claudeTasks = tasks.filter { task in
            guard let id = task.providerID else { return false }
            return claudeProviderIDs.contains(id) && task.tokenUsage > 0
        }
        guard !claudeTasks.isEmpty else { return nil }

        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now

        let todayTasks = claudeTasks.filter { calendar.isDateInToday($0.updatedAt) }
        let weekTasks = claudeTasks.filter { $0.updatedAt >= weekStart }

        let primaryModel = claudeTasks
            .sorted { $0.updatedAt > $1.updatedAt }
            .first(where: { !($0.model.isEmpty || $0.model == "unknown") })?
            .model

        let latestAt = claudeTasks.map(\.updatedAt).max() ?? now

        return ClaudeTokenUsageSummary(
            todayTokens: todayTasks.reduce(0) { $0 + $1.tokenUsage },
            weekTokens: weekTasks.reduce(0) { $0 + $1.tokenUsage },
            todaySessions: todayTasks.count,
            weekSessions: weekTasks.count,
            primaryModel: primaryModel,
            observedAt: latestAt
        )
    }

    private func refreshCodexUsageLimits(showLoading: Bool) async {
        let shouldRefresh = await MainActor.run {
            guard !isCodexUsageLimitRefreshing else {
                return false
            }

            isCodexUsageLimitRefreshing = true
            if showLoading, case .unavailable = codexUsageLimitState {
                codexUsageLimitState = .loading
            } else if showLoading, case .loading = codexUsageLimitState {
                codexUsageLimitState = .loading
            }
            return true
        }

        guard shouldRefresh else { return }

        let limits = await CodexLocalProvider().fetchUsageLimits()
        await MainActor.run {
            if let limits {
                codexUsageLimitState = .loaded(limits)
            } else {
                codexUsageLimitState = .unavailable
            }
            isCodexUsageLimitRefreshing = false
        }
    }
}

private struct CodexRemainingUsageCard: View {
    let state: CodexUsageLimitViewState
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch state {
            case .loading:
                CodexRemainingUsageHeader(
                    title: "Codex 剩余用量",
                    subtitle: "读取本地 Codex 快照中",
                    trailingText: "加载中",
                    isRefreshing: isRefreshing,
                    onRefresh: onRefresh
                )
                CodexRemainingUsageSkeleton()
            case .loaded(let summary):
                CodexRemainingUsageHeader(
                    title: "Codex 剩余用量",
                    subtitle: summary.limitName ?? "本地 Codex rate limit",
                    trailingText: "最近 \(Formatters.relative(summary.observedAt))",
                    isRefreshing: isRefreshing,
                    onRefresh: onRefresh
                )
                VStack(spacing: 8) {
                    ForEach(Array(limits(for: summary).enumerated()), id: \.offset) { _, limit in
                        CodexRemainingUsageRow(limit: limit)
                    }
                }
            case .unavailable:
                CodexRemainingUsageHeader(
                    title: "Codex 剩余用量",
                    subtitle: "等待 Codex 写入 rate limit 快照",
                    trailingText: "暂无数据",
                    isRefreshing: isRefreshing,
                    onRefresh: onRefresh
                )
                CodexRemainingUsageUnavailable()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func limits(for summary: CodexUsageLimitSummary) -> [CodexUsageLimit] {
        [summary.primary, summary.secondary].compactMap(\.self)
    }
}

private enum CodexUsageLimitViewState: Equatable {
    case loading
    case loaded(CodexUsageLimitSummary)
    case unavailable
}

private struct CodexRemainingUsageHeader: View {
    let title: String
    let subtitle: String
    let trailingText: String
    let isRefreshing: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.33percent")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(trailingText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 26, height: 26)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 26, height: 26)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("刷新 Codex 余额")
            }
        }
    }
}

private struct CodexRemainingUsageSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            CodexRemainingUsageSkeletonRow(titleWidth: 52, barOpacity: 0.18)
            CodexRemainingUsageSkeletonRow(titleWidth: 34, barOpacity: 0.13)
        }
        .redacted(reason: .placeholder)
    }
}

private struct CodexRemainingUsageSkeletonRow: View {
    let titleWidth: CGFloat
    let barOpacity: Double

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.18))
                .frame(width: titleWidth, height: 18)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.accentColor.opacity(barOpacity))
                .frame(height: 8)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.16))
                .frame(width: 48, height: 18)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.12))
                .frame(width: 64, height: 18)
        }
    }
}

private struct CodexRemainingUsageUnavailable: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("运行一次 Codex 后，余额快照会随 session 日志自动出现。")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48, alignment: .leading)
    }
}

private struct CodexRemainingUsageRow: View {
    let limit: CodexUsageLimit

    private var progress: Double {
        max(0, min(1, limit.remainingPercent / 100))
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(windowTitle)
                    .font(.callout.weight(.semibold))
                    .frame(width: 64, alignment: .leading)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                Text(percentText)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .frame(width: 54, alignment: .trailing)
                Text(resetText)
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
            }
        }
    }

    private var windowTitle: String {
        if limit.windowMinutes % 10_080 == 0 {
            let weeks = limit.windowMinutes / 10_080
            return weeks == 1 ? "1周" : "\(weeks)周"
        }

        if limit.windowMinutes % 1_440 == 0 {
            return "\(limit.windowMinutes / 1_440)天"
        }

        if limit.windowMinutes % 60 == 0 {
            return "\(limit.windowMinutes / 60) 小时"
        }

        return "\(limit.windowMinutes) 分钟"
    }

    private var percentText: String {
        String(format: "%.0f%%", limit.remainingPercent)
    }

    private var resetText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(limit.resetsAt) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: limit.resetsAt)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: limit.resetsAt)
    }
}

private struct TokenUsageOverview: View {
    let summaries: [TokenUsageSummary]
    let totalTokens: Int
    let totalRecords: Int

    private var topSummary: TokenUsageSummary? {
        summaries.first
    }

    private var averageTokensPerRecord: Int {
        guard totalRecords > 0 else {
            return 0
        }
        return totalTokens / totalRecords
    }

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                TokenUsageMetricTile(
                    title: "总消耗",
                    value: Formatters.tokens(totalTokens),
                    subtitle: "\(totalRecords) 条记录"
                )
                TokenUsageMetricTile(
                    title: "最高 Agent",
                    value: topSummary?.agent ?? "-",
                    subtitle: topSummary.map { Formatters.tokens($0.totalTokens) } ?? "无记录",
                    systemImage: "crown"
                )
                TokenUsageMetricTile(
                    title: "单记录均值",
                    value: Formatters.tokens(averageTokensPerRecord),
                    subtitle: "\(summaries.count) 个 Agent",
                    systemImage: "divide"
                )
            }
        }
    }
}

private struct TokenUsageMetricTile: View {
    let title: String
    let value: String
    let subtitle: String
    var systemImage: String?
    var symbolText: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if systemImage != nil || symbolText != nil {
                metricSymbol
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    @ViewBuilder
    private var metricSymbol: some View {
        if let symbolText {
            Text(symbolText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
        } else if let systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
        }
    }
}

private struct TokenUsageDistributionBar: View {
    let summaries: [TokenUsageSummary]
    let totalTokens: Int

    private var visibleSegments: [TokenUsageSummary] {
        Array(summaries.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Token 分布")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("按 Agent 占比")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(Array(visibleSegments.enumerated()), id: \.element.id) { index, summary in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(tokenUsageColor(index))
                            .frame(width: segmentWidth(for: summary, in: proxy.size.width))
                    }
                }
            }
            .frame(height: 18)

            HStack(spacing: 14) {
                ForEach(Array(visibleSegments.prefix(4).enumerated()), id: \.element.id) { index, summary in
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(tokenUsageColor(index))
                            .frame(width: 10, height: 7)
                        Text(summary.agent)
                            .font(.caption)
                            .lineLimit(1)
                        Text(percentText(for: summary.totalTokens, total: totalTokens))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func segmentWidth(for summary: TokenUsageSummary, in availableWidth: CGFloat) -> CGFloat {
        guard totalTokens > 0 else {
            return 0
        }
        let fraction = CGFloat(summary.totalTokens) / CGFloat(totalTokens)
        return max(6, availableWidth * fraction)
    }
}

private struct SessionTokenTreemapView: View {
    let tasks: [AgentTask]
    let totalTokens: Int
    @State private var hoveredEntryID: String?
    @State private var detailEntryID: String?

    private var entries: [SessionTokenTreemapEntry] {
        let threshold = max(1, Int((Double(totalTokens) * 0.01).rounded(.up)))
        let rankedTasks = tasks.enumerated().map { index, task in
            RankedSessionTokenTask(rank: index + 1, colorIndex: index, task: task)
        }
        let visibleTasks = rankedTasks.filter { $0.task.tokenUsage >= threshold }
        let smallTasks = rankedTasks.filter { $0.task.tokenUsage < threshold }
        var entries = visibleTasks.map { rankedTask in
            SessionTokenTreemapEntry(
                id: rankedTask.task.id,
                rank: rankedTask.rank,
                colorIndex: rankedTask.colorIndex,
                title: rankedTask.task.title,
                agent: rankedTask.task.agent,
                model: rankedTask.task.model,
                statusTitle: rankedTask.task.status.title,
                tokenUsage: rankedTask.task.tokenUsage,
                updatedAt: rankedTask.task.updatedAt,
                sessionCount: 1,
                isOther: false
            )
        }

        let otherTokens = smallTasks.reduce(0) { $0 + $1.task.tokenUsage }
        if otherTokens > 0 {
            let latestUpdatedAt = smallTasks.map(\.task.updatedAt).max() ?? Date()
            entries.append(
                SessionTokenTreemapEntry(
                    id: "other-under-one-percent",
                    rank: entries.count + 1,
                    colorIndex: 7,
                    title: "其他 Session",
                    agent: "多个 Agent",
                    model: "\(smallTasks.count) 个小任务",
                    statusTitle: "聚合",
                    tokenUsage: otherTokens,
                    updatedAt: latestUpdatedAt,
                    sessionCount: smallTasks.count,
                    isOther: true
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.tokenUsage != rhs.tokenUsage {
                return lhs.tokenUsage > rhs.tokenUsage
            }
            return lhs.rank < rhs.rank
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Session 任务面积图")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("每个矩形 = 一个 Session")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    ForEach(nodes(in: proxy.size)) { node in
                        let isHovered = hoveredEntryID == node.entry.id
                        let isDetailVisible = detailEntryID == node.entry.id
                        SessionTokenTreemapTile(
                            rank: node.rank,
                            entry: node.entry,
                            totalTokens: totalTokens,
                            color: tokenUsageColor(node.colorIndex),
                            size: node.rect.size,
                            isHovered: isHovered,
                            isDetailVisible: isDetailVisible,
                            onHoverChanged: { hovering in
                                if hovering {
                                    hoveredEntryID = node.entry.id
                                } else if hoveredEntryID == node.entry.id {
                                    hoveredEntryID = nil
                                }
                            },
                            onRightClick: {
                                detailEntryID = isDetailVisible ? nil : node.entry.id
                            }
                        )
                        .frame(width: node.rect.width, height: node.rect.height)
                        .position(x: node.rect.midX, y: node.rect.midY)
                        .zIndex((isHovered || isDetailVisible) ? 1 : 0)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    detailEntryID = nil
                }
            }
            .frame(minHeight: 420)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private func nodes(in size: CGSize) -> [SessionTokenTreemapNode] {
        let rect = CGRect(origin: .zero, size: size)
        return layout(entries, in: rect, splitHorizontally: size.width >= size.height)
    }

    private func layout(
        _ items: [SessionTokenTreemapEntry],
        in rect: CGRect,
        splitHorizontally: Bool
    ) -> [SessionTokenTreemapNode] {
        guard let first = items.first else {
            return []
        }
        guard items.count > 1 else {
            return [
                SessionTokenTreemapNode(
                    rank: first.rank,
                    colorIndex: first.colorIndex,
                    entry: first,
                    rect: rect.insetBy(dx: 2, dy: 2)
                )
            ]
        }

        let total = items.reduce(0) { $0 + $1.tokenUsage }
        guard total > 0 else {
            return []
        }

        let splitIndex = balancedSplitIndex(for: items, total: total)
        let leadingItems = Array(items[..<splitIndex])
        let trailingItems = Array(items[splitIndex...])
        let leadingTotal = leadingItems.reduce(0) { $0 + $1.tokenUsage }
        let leadingFraction = CGFloat(leadingTotal) / CGFloat(total)

        let leadingRect: CGRect
        let trailingRect: CGRect
        if splitHorizontally {
            let leadingWidth = rect.width * leadingFraction
            leadingRect = CGRect(x: rect.minX, y: rect.minY, width: leadingWidth, height: rect.height)
            trailingRect = CGRect(x: rect.minX + leadingWidth, y: rect.minY, width: rect.width - leadingWidth, height: rect.height)
        } else {
            let leadingHeight = rect.height * leadingFraction
            leadingRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: leadingHeight)
            trailingRect = CGRect(x: rect.minX, y: rect.minY + leadingHeight, width: rect.width, height: rect.height - leadingHeight)
        }

        return layout(leadingItems, in: leadingRect, splitHorizontally: !splitHorizontally)
            + layout(trailingItems, in: trailingRect, splitHorizontally: !splitHorizontally)
    }

    private func balancedSplitIndex(for items: [SessionTokenTreemapEntry], total: Int) -> Int {
        var bestIndex = 1
        var bestDifference = Int.max
        var runningTotal = 0

        for index in 0..<(items.count - 1) {
            runningTotal += items[index].tokenUsage
            let difference = abs(total - runningTotal * 2)
            if difference < bestDifference {
                bestDifference = difference
                bestIndex = index + 1
            }
        }

        return bestIndex
    }
}

private struct SessionTokenTreemapTile: View {
    let rank: Int
    let entry: SessionTokenTreemapEntry
    let totalTokens: Int
    let color: Color
    let size: CGSize
    let isHovered: Bool
    let isDetailVisible: Bool
    let onHoverChanged: (Bool) -> Void
    let onRightClick: () -> Void

    private var isLarge: Bool {
        size.width >= 240 && size.height >= 145
    }

    private var isMedium: Bool {
        size.width >= 150 && size.height >= 84
    }

    private var tokenShare: String {
        percentText(for: entry.tokenUsage, total: totalTokens)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            tileBackground

            if isLarge {
                largeContent
            } else if isMedium {
                mediumContent
            } else {
                compactContent
            }

            if isDetailVisible {
                immediateDetail
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .foregroundStyle(.primary)
        .contentShape(Rectangle())
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .overlay(RightClickDetector(onRightClick: onRightClick))
        .scaleEffect(isHovered ? 1.006 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isDetailVisible)
    }

    private var tileBackground: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.primary.opacity(0.065))
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isHovered ? color.opacity(0.55) : Color.primary.opacity(0.035), lineWidth: isHovered ? 1 : 0.5)
            Rectangle()
                .fill(color.opacity(isHovered ? 1 : 0.62))
                .frame(width: isHovered ? 6 : 4)
            VStack(spacing: 0) {
                Rectangle()
                    .fill(color.opacity(isHovered ? 0.9 : 0.28))
                    .frame(height: isLarge ? 4 : 3)
                Spacer(minLength: 0)
            }
        }
    }

    private var largeContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            tileHeader
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                Text(Formatters.tokens(entry.tokenUsage))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 16)
            tileFooter
        }
        .padding(.leading, 8)
    }

    private var mediumContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            tileHeader
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                Text(Formatters.tokens(entry.tokenUsage))
                    .font(.title3.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .padding(.leading, 8)
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("#\(rank)")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(color.opacity(0.16))
            Spacer(minLength: 0)
            Text(tokenShare)
                .font(.caption2.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.leading, 8)
                .padding(.bottom, 6)
        }
        .foregroundStyle(.primary)
    }

    private var tileHeader: some View {
        HStack {
            Text("#\(rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(tokenShare)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(color.opacity(isHovered ? 0.16 : 0.1))
    }

    private var tileFooter: some View {
        HStack {
            Text(entry.agent)
                .foregroundStyle(color)
            Spacer(minLength: 0)
            Text(entry.isOther ? "\(entry.sessionCount) 个 Session" : "最近 \(Formatters.relative(entry.updatedAt))")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.74)
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.04))
    }

    private var immediateDetail: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            VStack(alignment: .leading, spacing: 3) {
                detailRow("Agent", entry.agent)
                detailRow("Model", entry.model)
                detailRow("状态", entry.statusTitle)
                detailRow("Tokens", "\(Formatters.tokens(entry.tokenUsage)) (\(tokenShare))")
                detailRow(entry.isOther ? "数量" : "最近", entry.isOther ? "\(entry.sessionCount) 个 Session" : Formatters.relative(entry.updatedAt))
            }
        }
        .padding(10)
        .frame(width: min(max(size.width * 0.5, 190), 300), alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(color.opacity(0.38), lineWidth: 0.75)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }
}

private struct SessionTokenTreemapEntry: Identifiable {
    let id: String
    let rank: Int
    let colorIndex: Int
    let title: String
    let agent: String
    let model: String
    let statusTitle: String
    let tokenUsage: Int
    let updatedAt: Date
    let sessionCount: Int
    let isOther: Bool
}

private struct RankedSessionTokenTask {
    let rank: Int
    let colorIndex: Int
    let task: AgentTask
}

private struct SessionTokenTreemapNode: Identifiable {
    var id: String { entry.id }
    let rank: Int
    let colorIndex: Int
    let entry: SessionTokenTreemapEntry
    let rect: CGRect
}

private struct RightClickDetector: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> LocalRightClickView {
        let view = LocalRightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: LocalRightClickView, context: Context) {
        nsView.onRightClick = onRightClick
    }
}

private final class LocalRightClickView: NSView {
    var onRightClick: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            removeMonitor()
        } else if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
                guard let self, let window = self.window, event.window === window else {
                    return event
                }

                let point = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(point) {
                    self.onRightClick?()
                }

                return event
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private func tokenUsageColor(_ index: Int) -> Color {
    let colors: [Color] = [
        .cyan,
        .green,
        .orange,
        .blue,
        .pink,
        .teal,
        .purple,
        .mint
    ]
    return colors[index % colors.count]
}

private func percentText(for value: Int, total: Int) -> String {
    guard total > 0 else {
        return "0%"
    }
    let percent = Double(value) / Double(total) * 100
    return String(format: "%.1f%%", percent)
}

private struct TokenUsageEmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Claude Token Usage Card

private struct ClaudeTokenUsageCard: View {
    let summary: ClaudeTokenUsageSummary?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary {
                ClaudeTokenUsageHeader(
                    subtitle: summary.primaryModel ?? "Claude CLI / Desktop",
                    trailingText: "最近 \(Formatters.relative(summary.observedAt))"
                )
                VStack(spacing: 8) {
                    ClaudeTokenUsageRow(
                        title: "今日",
                        tokens: summary.todayTokens,
                        sessions: summary.todaySessions,
                        fraction: summary.weekTokens > 0
                            ? Double(summary.todayTokens) / Double(summary.weekTokens)
                            : 0
                    )
                    ClaudeTokenUsageRow(
                        title: "本周",
                        tokens: summary.weekTokens,
                        sessions: summary.weekSessions,
                        fraction: 1.0
                    )
                }
            } else {
                ClaudeTokenUsageHeader(
                    subtitle: "等待 Claude 会话数据",
                    trailingText: "暂无数据"
                )
                ClaudeTokenUsageUnavailable()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

private struct ClaudeTokenUsageHeader: View {
    let subtitle: String
    let trailingText: String

    private let claudeColor = Color.orange

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(claudeColor)
                .frame(width: 26, height: 26)
                .background(Circle().fill(claudeColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Token 用量")
                    .font(.headline.weight(.semibold))
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(trailingText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ClaudeTokenUsageRow: View {
    let title: String
    let tokens: Int
    let sessions: Int
    let fraction: Double

    private var progress: Double {
        max(0, min(1, fraction))
    }

    private var sessionsText: String {
        "\(sessions) 次会话"
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .frame(width: 64, alignment: .leading)
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color.orange)
                Text(Formatters.tokens(tokens))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .frame(width: 72, alignment: .trailing)
                Text(sessionsText)
                    .font(.callout.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .trailing)
            }
        }
    }
}

private struct ClaudeTokenUsageUnavailable: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("运行一次 Claude 后，token 用量会从本地会话记录中自动统计。")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 48, alignment: .leading)
    }
}
