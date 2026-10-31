import SwiftUI

struct SlashCommandMenu: View {
    let filter: String
    let onSelect: (BlockKind) -> Void

    private var options: [BlockKind] {
        let query = filter.lowercased()
        let all = BlockKind.allCases.filter { $0 != .paragraph || query.isEmpty }
        guard !query.isEmpty else { return all }
        return all.filter { kind in
            kind.menuTitle.lowercased().contains(query)
                || kind.menuKeywords.contains(where: { $0.hasPrefix(query) || $0.contains(query) })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Blocks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if options.isEmpty {
                Text("No results")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(options) { kind in
                    Button {
                        onSelect(kind)
                    } label: {
                        Label(kind.menuTitle, systemImage: kind.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    #if os(macOS)
                    .background(.quaternary.opacity(0.001))
                    #endif
                }
            }
        }
        .frame(width: 260, alignment: .leading)
        #if os(macOS)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(radius: 8, y: 4)
        #else
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        #endif
    }
}
