import SwiftUI
#if os(macOS)
import AppKit
#endif

struct BlockRowView: View {
    @Binding var block: Block
    var listMarker: String?
    var slashState: SlashCommandState?
    var selectedSlashCommandIndex: Int
    var isFocused: Bool
    var focusedBlockID: Binding<UUID?>
    let onTextChange: (String) -> Void
    let onSelectSlashCommand: (BlockKind) -> Void
    let onPressReturn: () -> Void
    let onPressDeleteWhenEmpty: () -> Bool
    let onMoveSlashSelection: (Int) -> Bool
    let onDismissSlashCommand: () -> Bool

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
        #if os(macOS)
        MacBlockTextView(
            text: bindingText,
            kind: block.kind,
            isFocused: isFocused,
            focusedBlockID: focusedBlockID,
            blockID: block.id,
            onTextChange: onTextChange,
            onPressReturn: onPressReturn,
            onPressDeleteWhenEmpty: onPressDeleteWhenEmpty,
            onMoveSlashSelection: onMoveSlashSelection,
            onDismissSlashCommand: onDismissSlashCommand
        )
        .frame(minHeight: 22)
        .padding(.vertical, verticalPadding)
        #else
        TextField("", text: bindingText, axis: usesMultilineField ? .vertical : .horizontal)
            .textFieldStyle(.plain)
            .font(contentFont)
            .foregroundStyle(contentColor)
            .lineLimit(usesMultilineField ? 2...30 : 1...4)
            .padding(.vertical, verticalPadding)
            .onChange(of: block.text) { _, newValue in
                onTextChange(newValue)
            }
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

#if os(macOS)
private struct MacBlockTextView: NSViewRepresentable {
    @Binding var text: String
    let kind: BlockKind
    let isFocused: Bool
    var focusedBlockID: Binding<UUID?>
    let blockID: UUID
    let onTextChange: (String) -> Void
    let onPressReturn: () -> Void
    let onPressDeleteWhenEmpty: () -> Bool
    let onMoveSlashSelection: (Int) -> Bool
    let onDismissSlashCommand: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> BlockNSTextView {
        let view = BlockNSTextView()
        view.delegate = context.coordinator
        configure(view)
        return view
    }

    func updateNSView(_ view: BlockNSTextView, context: Context) {
        context.coordinator.parent = self
        configure(view)
        if view.string != text {
            view.string = text
            view.invalidateIntrinsicContentSize()
        }
        if isFocused, view.window?.firstResponder !== view {
            DispatchQueue.main.async {
                guard view.window?.makeFirstResponder(view) == true else { return }
                view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
            }
        }
    }

    private func configure(_ view: BlockNSTextView) {
        view.font = font
        view.textColor = kind == .quote ? .secondaryLabelColor : .labelColor
        view.onPressReturn = onPressReturn
        view.onPressDeleteWhenEmpty = onPressDeleteWhenEmpty
        view.onMoveSlashSelection = onMoveSlashSelection
        view.onDismissSlashCommand = onDismissSlashCommand
    }

    private var font: NSFont {
        switch kind {
        case .heading1: .systemFont(ofSize: 30, weight: .bold)
        case .heading2: .systemFont(ofSize: 22, weight: .bold)
        case .heading3: .systemFont(ofSize: 20, weight: .semibold)
        case .code: .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        default: .systemFont(ofSize: NSFont.systemFontSize)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacBlockTextView

        init(_ parent: MacBlockTextView) {
            self.parent = parent
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.focusedBlockID.wrappedValue = parent.blockID
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
            parent.onTextChange(view.string)
            view.invalidateIntrinsicContentSize()
        }
    }
}

private final class BlockNSTextView: NSTextView {
    var onPressReturn: () -> Void = {}
    var onPressDeleteWhenEmpty: () -> Bool = { false }
    var onMoveSlashSelection: (Int) -> Bool = { _ in false }
    var onDismissSlashCommand: () -> Bool = { false }

    init() {
        let container = NSTextContainer(size: NSSize(width: 1, height: CGFloat.greatestFiniteMagnitude))
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
        isRichText = false
        isEditable = true
        isSelectable = true
        drawsBackground = false
        isHorizontallyResizable = false
        isVerticallyResizable = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        autoresizingMask = [.width]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: 22)
        }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: max(22, ceil(height)))
    }

    override func layout() {
        super.layout()
        textContainer?.containerSize = NSSize(width: max(1, bounds.width), height: CGFloat.greatestFiniteMagnitude)
        invalidateIntrinsicContentSize()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            if string.isEmpty && onPressDeleteWhenEmpty() {
                return
            }
            super.keyDown(with: event)
            return
        case 36:
            if event.modifierFlags.contains(.shift) {
                super.keyDown(with: event)
            } else {
                onPressReturn()
            }
            return
        case 126 where onMoveSlashSelection(-1):
            return
        case 125 where onMoveSlashSelection(1):
            return
        case 53 where onDismissSlashCommand():
            return
        default:
            super.keyDown(with: event)
        }
    }
}
#endif
