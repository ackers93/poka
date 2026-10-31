import SwiftUI

struct SlashCommandMenu: View {
    let filter: String
    let selectedIndex: Int
    let onSelect: (BlockKind) -> Void

    static func options(matching filter: String) -> [BlockKind] {
        let query = filter.lowercased()
        let all = BlockKind.allCases.filter { $0 != .paragraph || query.isEmpty }
        guard !query.isEmpty else { return all }
        return all.filter { kind in
            kind.menuTitle.lowercased().contains(query)
                || kind.menuKeywords.contains(where: { $0.hasPrefix(query) || $0.contains(query) })
        }
    }

    private var options: [BlockKind] {
        Self.options(matching: filter)
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
                ForEach(Array(options.enumerated()), id: \.element.id) { index, kind in
                    Button {
                        onSelect(kind)
                    } label: {
                        Label(kind.menuTitle, systemImage: kind.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background {
                                if index == selectedIndex {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.2))
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 4)
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
