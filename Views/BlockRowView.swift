import SwiftUI

struct BlockRowView: View {
    @Binding var block: Block
    var listMarker: String?
    var slashState: SlashCommandState?
    var selectedSlashCommandIndex: Int
    var isFocused: Bool
    var focusedBlockID: FocusState<UUID?>.Binding
    let onTextChange: (String) -> Void
    let onSelectSlashCommand: (BlockKind) -> Void
    let onPressReturn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                if let listMarker {
                    Text(listMarker)
                        .font(markerFont)
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                        .padding(.top, markerTopPadding)
                }

                if block.kind == .divider {
                    Divider()
                        .padding(.vertical, 12)
                } else {
                    field
                }
            }

            if isFocused, slashState != nil {
                SlashCommandMenu(
                    filter: slashState?.filter ?? "",
                    selectedIndex: selectedSlashCommandIndex
                ) { kind in
                    onSelectSlashCommand(kind)
                }
                .padding(.leading, listMarker == nil ? 0 : 28)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        TextField("", text: bindingText, axis: usesMultilineField ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .font(contentFont)
            .foregroundStyle(contentColor)
            .lineLimit(usesMultilineField ? 2...30 : 1...4)
            .padding(.vertical, verticalPadding)
            .focused(focusedBlockID, equals: block.id)
            .onChange(of: block.text) { _, newValue in
                onTextChange(newValue)
            }
            #if os(macOS)
            .onKeyPress(phases: .down) { press in
                guard press.key == .return else { return .ignored }
                if press.modifiers.contains(.shift) {
                    block.text.append("\n")
                    return .handled
                }
                onPressReturn()
                return .handled
            }
            #endif
            #if os(iOS)
            .textInputAutocapitalization(.sentences)
            #endif
    }

    private var usesMultilineField: Bool {
        true
    }

    private var bindingText: Binding<String> {
        Binding(
            get: { block.text },
            set: { block.text = $0 }
        )
    }

    private var contentFont: Font {
        switch block.kind {
        case .heading1: .system(size: 30, weight: .bold)
        case .heading2: .title.bold()
        case .heading3: .title3.weight(.semibold)
        case .code: .body.monospaced()
        case .quote: .body.italic()
        default: .body
        }
    }

    private var contentColor: Color {
        block.kind == .quote ? .secondary : .primary
    }

    private var verticalPadding: CGFloat {
        switch block.kind {
        case .heading1: 4
        case .heading2, .heading3: 2
        default: 1
        }
    }

    private var markerFont: Font {
        .body
    }

    private var markerTopPadding: CGFloat {
        block.kind == .heading1 ? 10 : 6
    }
}
