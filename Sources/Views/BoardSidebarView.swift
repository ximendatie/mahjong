import SwiftUI

struct BoardSidebarView: View {
    @Binding var selectedTab: BoardTab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("视图")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 16)

            VStack(spacing: 6) {
                ForEach(BoardTab.allCases) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 18)
                            Text(tab.title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()
        }
        .frame(width: 176, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.035))
    }
}

