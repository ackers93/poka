import SwiftUI
import UniformTypeIdentifiers

struct BlockEditorView: View {
    @Bindable var noteStore: NoteStore
    @State private var focusedBlockID: UUID?
    @State private var slashStates: [UUID: SlashCommandState] = [:]
    @State private var selectedSlashCommandIndices: [UUID: Int] = [:]
    @State private var selectedIDs: Set<UUID> = []
    private struct InsertionPoint: Equatable {
        let blockID: UUID
        let after: Bool
    }

    @GestureState private var selectingRange = false
    @GestureState private var insertionPoint: InsertionPoint?
    @State private var rowFrames: [UUID: CGRect] = [:]
    @FocusState private var selectionFocused: Bool
    @State private var draggedBlockID: UUID?
    @State private var expandedToggleIDs: Set<UUID> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                blockTree(noteStore.editorBlocks)

                Color.clear
                    .frame(height: 120)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIDs.removeAll()
                        appendParagraphAtEnd()
                    }
                    .onDrop(of: [.pokaBlock], delegate: BlockDropDelegate(
                        destinationID: nil,
                        draggedBlockID: $draggedBlockID,
                        moveBlock: moveBlock
                    ))
            }
            .coordinateSpace(name: "blockSelection")
            .onPreferenceChange(BlockFrames.self) { rowFrames = $0 }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(noteStore.selectedNote?.title ?? "Note")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                NoteIconPicker(icon: noteStore.selectedNote?.frontmatter.icon) { icon in
                    noteStore.setSelectedNoteIcon(icon)
                }
            }
        }
        #if os(macOS)
        .navigationSubtitle(noteStore.selectedNote?.fileURL.lastPathComponent ?? "")
        #endif
        .onAppear {
            if focusedBlockID == nil {
                focusedBlockID = noteStore.editorBlocks.first?.id
            }
        }
        .onChange(of: noteStore.selectedNoteID) { _, _ in
            slashStates = [:]
            selectedSlashCommandIndices = [:]
            selectedIDs = []
            draggedBlockID = nil
            expandedToggleIDs = []
            focusedBlockID = noteStore.editorBlocks.first?.id
        }
        #if os(macOS)
        .onKeyPress(phases: .down) { press in
            guard let blockID = focusedBlockID, slashStates[blockID] != nil else {
                return .ignored
            }

            switch press.key {
            case .upArrow:
                moveSlashCommandSelection(for: blockID, by: -1)
                return .handled
            case .downArrow:
                moveSlashCommandSelection(for: blockID, by: 1)
                return .handled
            case .escape:
                slashStates[blockID] = nil
                selectedSlashCommandIndices[blockID] = nil
                return .handled
            default:
                return .ignored
            }
        }
        #endif
        .safeAreaInset(edge: .bottom) {
            if !selectedIDs.isEmpty {
                HStack {
                    Text("\(selectedIDs.count) selected")
                    Button("Delete", role: .destructive) { deleteSelection() }
                    Button("Deselect") { selectedIDs.removeAll() }
                }
                .padding(6)
                #if os(macOS)
                .background(SelectionKeyboardTarget(
                    delete: deleteSelection,
                    deselect: { selectedIDs.removeAll() }
                ))
                #else
                .focusable()
                .focused($selectionFocused)
                .onAppear { selectionFocused = true }
                .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                    deleteSelection()
                    return .handled
                }
                .onKeyPress(.escape) {
                    selectedIDs.removeAll()
                    return .handled
                }
                #endif
            } else {
                Text("Drag in the left margin to select blocks · Type / for block types · ↩ for a new block")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
        }
    }

    private func blockTree(_ blocks: [Block]) -> AnyView {
        AnyView(ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
            VStack(alignment: .leading, spacing: 2) {
                blockRow(at: index, siblings: blocks, block: block)
                    .simultaneousGesture(TapGesture().onEnded { selectedIDs.removeAll() })
                    .padding(.leading, 20)
                    .overlay(alignment: .leading) {
                        Color.clear
                            .frame(width: 20)
                            .contentShape(Rectangle())
                            .help("Drag to select blocks")
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("blockSelection"))
                                .updating($selectingRange) { _, active, _ in active = true }
                                .onChanged { drag in
                                    let range = min(drag.startLocation.y, drag.location.y)...max(drag.startLocation.y, drag.location.y)
                                    selectedIDs = Set(rowFrames.compactMap { id, frame in
                                        range.overlaps(frame.minY...frame.maxY) ? id : nil
                                    })
                                    focusedBlockID = nil
                                    #if !os(macOS)
                                    selectionFocused = true
                                    #endif
                                })
                    }
                    .background(selectedIDs.contains(block.id) ? Color.accentColor.opacity(0.15) : Color.clear)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: BlockFrames.self, value: [block.id: proxy.frame(in: .named("blockSelection"))])
                    })
                    .overlay {
                        if selectedIDs.contains(block.id), !selectingRange {
                            // Capture the drag above text views, cell editors and the selection gutter.
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(selectionMoveGesture)
                                .onTapGesture { selectedIDs.removeAll() }
                                .help("Drag selected blocks to move them")
                        }
                    }
                    .overlay(alignment: insertionPoint?.after == true ? .bottom : .top) {
                        if insertionPoint?.blockID == block.id {
                            Rectangle().fill(Color.accentColor).frame(height: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .onDrop(of: [.pokaBlock], delegate: BlockDropDelegate(
                        destinationID: block.id,
                        draggedBlockID: $draggedBlockID,
                        moveBlock: moveBlock
                    ))

                if block.kind == .toggle, expandedToggleIDs.contains(block.id) {
                    blockTree(block.children)
                        .padding(.leading, 34)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                                .frame(width: 1)
                        }
                }
            }
        })
    }

    private var selectionMoveGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("blockSelection"))
            .updating($insertionPoint) { drag, point, _ in
                point = dropPosition(at: drag.location.y)
            }
            .onEnded { drag in
                guard let point = dropPosition(at: drag.location.y) else { return }
                moveBlocks(selectedIDs, relativeTo: point.blockID, after: point.after)
            }
    }

    private func dropPosition(at y: CGFloat) -> InsertionPoint? {
        let nearest = rowFrames.min {
            max($0.value.minY - y, y - $0.value.maxY) < max($1.value.minY - y, y - $1.value.maxY)
        }
        guard let (id, frame) = nearest, !selectedIDs.contains(id) else { return nil }
        return InsertionPoint(blockID: id, after: y >= frame.midY)
    }

    private func blockRow(at index: Int, siblings: [Block], block: Block) -> some View {
        BlockRowView(
            block: binding(for: block),
            listMarker: listMarker(for: block, at: index, siblings: siblings),
            slashState: slashStates[block.id],
            selectedSlashCommandIndex: selectedSlashCommandIndices[block.id] ?? 0,
            isFocused: focusedBlockID == block.id,
            focusedBlockID: $focusedBlockID,
            onTextChange: { text in
                updateSlashState(for: block.id, text: text)
                noteStore.commitEditorBlocks(noteStore.editorBlocks)
            },
            onSelectSlashCommand: { kind in
                applySlashCommand(blockID: block.id, kind: kind)
            },
            onPressReturn: {
                if slashStates[block.id] != nil {
                    selectHighlightedSlashCommand(for: block.id)
                } else if block.kind == .toggle {
                    insertChildBlock(in: block.id)
                } else if [.bullet, .numbered].contains(block.kind), block.text.isEmpty {
                    changeBlockKind(blockID: block.id, to: .paragraph)
                } else {
                    let continuationKind: BlockKind = [.bullet, .numbered].contains(block.kind)
                        ? block.kind
                        : .paragraph
                    insertBlock(after: block.id, kind: continuationKind)
                }
            },
            onPressDeleteWhenEmpty: {
                deleteEmptyFocusedBlock(id: block.id)
            },
            onPressDeleteDivider: {
                deleteDivider(id: block.id)
            },
            onPressReturnFromDivider: {
                insertBlock(after: block.id, kind: .paragraph)
            },
            onMoveSlashSelection: { offset in
                guard slashStates[block.id] != nil else { return false }
                moveSlashCommandSelection(for: block.id, by: offset)
                return true
            },
            onDismissSlashCommand: {
                guard slashStates[block.id] != nil else { return false }
                slashStates[block.id] = nil
                selectedSlashCommandIndices[block.id] = nil
                return true
            },
            onAddBlock: {
                if block.kind == .toggle {
                    insertChildBlock(in: block.id)
                } else {
                    insertBlock(after: block.id, kind: .paragraph)
                }
            },
            onChangeKind: { kind in
                changeBlockKind(blockID: block.id, to: kind)
            },
            onDeleteBlock: {
                if selectedIDs.contains(block.id) { deleteSelection() }
                else { deleteBlock(id: block.id) }
            },
            onDragStart: {
                if !selectedIDs.contains(block.id) { selectedIDs.removeAll() }
                draggedBlockID = block.id
            },
            isToggleExpanded: expandedToggleIDs.contains(block.id),
            onToggleExpanded: {
                if expandedToggleIDs.contains(block.id) {
                    expandedToggleIDs.remove(block.id)
                } else {
                    expandedToggleIDs.insert(block.id)
                }
            }
        )
    }

    private func binding(for block: Block) -> Binding<Block> {
        Binding(
            get: {
                findBlock(id: block.id, in: noteStore.editorBlocks) ?? block
            },
            set: { updatedBlock in
                guard replaceBlock(updatedBlock, id: block.id, in: &noteStore.editorBlocks) else { return }
                if updatedBlock.kind == .table { noteStore.commitEditorBlocks(noteStore.editorBlocks) }
            }
        )
    }

    private func listMarker(for block: Block, at index: Int, siblings: [Block]) -> String? {
        switch block.kind {
        case .bullet:
            return "•"
        case .numbered:
            let number = siblings[..<index].filter { $0.kind == .numbered }.count + 1
            return "\(number)."
        default:
            return nil
        }
    }

    private func updateSlashState(for blockID: UUID, text: String) {
        if let state = SlashCommandParser.activeCommand(in: text) {
            slashStates[blockID] = state
            let optionCount = SlashCommandMenu.options(matching: state.filter).count
            if optionCount > 0 {
                selectedSlashCommandIndices[blockID] = min(
                    selectedSlashCommandIndices[blockID] ?? 0,
                    optionCount - 1
                )
            } else {
                selectedSlashCommandIndices[blockID] = nil
            }
        } else {
            slashStates[blockID] = nil
            selectedSlashCommandIndices[blockID] = nil
        }
    }

    private func applySlashCommand(blockID: UUID, kind: BlockKind) {
        guard var block = findBlock(id: blockID, in: noteStore.editorBlocks) else { return }
        if let slash = slashStates[blockID] {
            block.text = String(block.text.dropLast(slash.suffixLength))
        }
        updateBlockKind(&block, to: kind)
        _ = replaceBlock(block, id: blockID, in: &noteStore.editorBlocks)
        slashStates[blockID] = nil
        selectedSlashCommandIndices[blockID] = nil
        noteStore.commitEditorBlocks(noteStore.editorBlocks)

        if kind == .divider {
            insertBlock(after: blockID, kind: .paragraph)
        }
        focusedBlockID = blockID
    }

    private func changeBlockKind(blockID: UUID, to kind: BlockKind) {
        guard var block = findBlock(id: blockID, in: noteStore.editorBlocks) else { return }
        updateBlockKind(&block, to: kind)
        _ = replaceBlock(block, id: blockID, in: &noteStore.editorBlocks)
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = blockID

        if kind == .divider {
            insertBlock(after: blockID, kind: .paragraph)
        }
    }

    private func updateBlockKind(_ block: inout Block, to kind: BlockKind) {
        if kind == .table, block.kind != .table {
            block.tableRows = Block.newTable(title: block.text)
            block.text = ""
        } else if block.kind == .table, kind != .table {
            block.text = MarkdownCodec.serialize([block])
            block.tableRows = nil
        }
        block.kind = kind
        if kind == .divider {
            block.text = ""
        }
    }

    private func insertBlock(after blockID: UUID, kind: BlockKind) {
        let newBlock = Block(kind: kind)
        guard insertSibling(newBlock, after: blockID, in: &noteStore.editorBlocks) else { return }
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = newBlock.id
    }

    private func appendParagraphAtEnd() {
        let block = Block(kind: .paragraph)
        noteStore.editorBlocks.append(block)
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = block.id
    }

    private func insertChildBlock(in toggleID: UUID) {
        let child = Block()
        guard appendChild(child, to: toggleID, in: &noteStore.editorBlocks) else { return }
        expandedToggleIDs.insert(toggleID)
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = child.id
    }

    private func deleteEmptyFocusedBlock(id: UUID) -> Bool {
        guard let block = findBlock(id: id, in: noteStore.editorBlocks), block.text.isEmpty,
              totalBlockCount(noteStore.editorBlocks) > 1
        else { return false }
        let focusTargetID = adjacentBlockID(to: id, in: noteStore.editorBlocks)
        focusedBlockID = focusTargetID
        guard removeBlock(id: id, from: &noteStore.editorBlocks) else { return false }
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        return true
    }

    private func deleteDivider(id: UUID) -> Bool {
        guard let block = findBlock(id: id, in: noteStore.editorBlocks), block.kind == .divider
        else { return false }

        if totalBlockCount(noteStore.editorBlocks) == 1 {
            _ = replaceBlock(Block(id: id), id: id, in: &noteStore.editorBlocks)
            focusedBlockID = id
        } else {
            _ = removeBlock(id: id, from: &noteStore.editorBlocks)
            focusedBlockID = noteStore.editorBlocks.first?.id
        }
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        return true
    }

    private func deleteBlock(id: UUID) {
        guard findBlock(id: id, in: noteStore.editorBlocks) != nil else { return }

        if totalBlockCount(noteStore.editorBlocks) == 1 {
            _ = replaceBlock(Block(id: id), id: id, in: &noteStore.editorBlocks)
            focusedBlockID = id
        } else {
            _ = removeBlock(id: id, from: &noteStore.editorBlocks)
            focusedBlockID = noteStore.editorBlocks.first?.id
        }
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
    }

    private func moveBlock(from sourceID: UUID, before destinationID: UUID?) {
        let ids: Set<UUID> = selectedIDs.contains(sourceID) ? selectedIDs : [sourceID]
        moveBlocks(ids, relativeTo: destinationID, after: false)
    }

    private func moveBlocks(_ ids: Set<UUID>, relativeTo destinationID: UUID?, after: Bool) {
        var remaining = noteStore.editorBlocks
        let moving = extract(ids, from: &remaining)
        guard !moving.isEmpty else { return }
        if let destinationID {
            guard insert(moving, relativeTo: destinationID, after: after, in: &remaining) else { return }
        } else {
            remaining.append(contentsOf: moving)
        }
        noteStore.commitEditorBlocks(remaining)
    }

    private func deleteSelection() {
        var remaining = noteStore.editorBlocks
        _ = extract(selectedIDs, from: &remaining)
        if remaining.isEmpty { remaining.append(Block()) }
        selectedIDs.removeAll()
        noteStore.commitEditorBlocks(remaining)
        focusedBlockID = remaining.first?.id
    }

    private func extract(_ ids: Set<UUID>, from blocks: inout [Block]) -> [Block] {
        var extracted: [Block] = []
        for index in blocks.indices {
            if ids.contains(blocks[index].id) {
                extracted.append(blocks[index])
            } else {
                extracted += extract(ids, from: &blocks[index].children)
            }
        }
        blocks.removeAll { ids.contains($0.id) }
        return extracted
    }

    private func insert(_ moving: [Block], relativeTo id: UUID, after: Bool, in blocks: inout [Block]) -> Bool {
        if let position = blocks.firstIndex(where: { $0.id == id }) {
            blocks.insert(contentsOf: moving, at: after ? position + 1 : position)
            return true
        }
        for index in blocks.indices {
            if insert(moving, relativeTo: id, after: after, in: &blocks[index].children) { return true }
        }
        return false
    }

    private func findBlock(id: UUID, in blocks: [Block]) -> Block? {
        for block in blocks {
            if block.id == id { return block }
            if let found = findBlock(id: id, in: block.children) { return found }
        }
        return nil
    }

    private func replaceBlock(_ updated: Block, id: UUID, in blocks: inout [Block]) -> Bool {
        for index in blocks.indices {
            if blocks[index].id == id {
                blocks[index] = updated
                return true
            }
            if replaceBlock(updated, id: id, in: &blocks[index].children) { return true }
        }
        return false
    }

    private func insertSibling(_ newBlock: Block, after id: UUID, in blocks: inout [Block]) -> Bool {
        for index in blocks.indices {
            if blocks[index].id == id {
                blocks.insert(newBlock, at: index + 1)
                return true
            }
            if insertSibling(newBlock, after: id, in: &blocks[index].children) { return true }
        }
        return false
    }

    private func appendChild(_ child: Block, to toggleID: UUID, in blocks: inout [Block]) -> Bool {
        for index in blocks.indices {
            if blocks[index].id == toggleID, blocks[index].kind == .toggle {
                blocks[index].children.append(child)
                return true
            }
            if appendChild(child, to: toggleID, in: &blocks[index].children) { return true }
        }
        return false
    }

    private func removeBlock(id: UUID, from blocks: inout [Block]) -> Bool {
        if let index = blocks.firstIndex(where: { $0.id == id }) {
            blocks.remove(at: index)
            return true
        }
        for index in blocks.indices {
            if removeBlock(id: id, from: &blocks[index].children) { return true }
        }
        return false
    }

    private func totalBlockCount(_ blocks: [Block]) -> Int {
        blocks.reduce(0) { $0 + 1 + totalBlockCount($1.children) }
    }

    private func adjacentBlockID(to id: UUID, in blocks: [Block]) -> UUID? {
        let ids = flattenedBlockIDs(in: blocks)
        guard let index = ids.firstIndex(of: id) else { return nil }
        if index > ids.startIndex {
            return ids[ids.index(before: index)]
        }
        let nextIndex = ids.index(after: index)
        return nextIndex < ids.endIndex ? ids[nextIndex] : nil
    }

    private func flattenedBlockIDs(in blocks: [Block]) -> [UUID] {
        blocks.flatMap { [$0.id] + flattenedBlockIDs(in: $0.children) }
    }

    private func moveSlashCommandSelection(for blockID: UUID, by offset: Int) {
        guard let slashState = slashStates[blockID] else { return }
        let options = SlashCommandMenu.options(matching: slashState.filter)
        guard !options.isEmpty else { return }
        let current = selectedSlashCommandIndices[blockID] ?? 0
        selectedSlashCommandIndices[blockID] = (current + offset + options.count) % options.count
    }

    private func selectHighlightedSlashCommand(for blockID: UUID) {
        guard let slashState = slashStates[blockID] else { return }
        let options = SlashCommandMenu.options(matching: slashState.filter)
        guard let kind = options[safe: selectedSlashCommandIndices[blockID] ?? 0] else { return }
        applySlashCommand(blockID: blockID, kind: kind)
    }
}

#if os(macOS)
private struct SelectionKeyboardTarget: NSViewRepresentable {
    let delete: () -> Void
    let deselect: () -> Void

    func makeNSView(context: Context) -> SelectionResponder {
        SelectionResponder()
    }

    func updateNSView(_ view: SelectionResponder, context: Context) {
        view.delete = delete
        view.deselect = deselect
    }
}

private final class SelectionResponder: NSView {
    var delete: () -> Void = {}
    var deselect: () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117:
            if !event.isARepeat { delete() }
        case 53:
            deselect()
        default:
            super.keyDown(with: event)
        }
    }
}
#endif

private struct BlockFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension UTType {
    static let pokaBlock = UTType(exportedAs: "app.poka.notes.block")
}

private struct BlockDropDelegate: DropDelegate {
    let destinationID: UUID?
    @Binding var draggedBlockID: UUID?
    let moveBlock: (UUID, UUID?) -> Void

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceID = draggedBlockID else { return false }
        moveBlock(sourceID, destinationID)
        draggedBlockID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct NoteIconPicker: View {
    let icon: String?
    let onSelect: (String?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Text(icon ?? "📝")
                .font(.system(size: 18))
                .frame(width: 26, height: 26)
                .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            EmojiPalette(selectedIcon: icon) { emoji in
                onSelect(emoji)
                isPresented = false
            }
        }
        .help("Choose note icon")
        .accessibilityLabel("Choose note icon")
    }
}

private struct EmojiPalette: View {
    let selectedIcon: String?
    let onSelect: (String?) -> Void

    @State private var query = ""
    @State private var category = "Frequently used"

    private let categories: [(name: String, icon: String, emojis: [String])] = [
        ("Frequently used", "clock", ["😀", "😊", "😂", "🥰", "😍", "😎", "🤔", "😭", "👍", "👋", "❤️", "🔥", "✨", "⭐️", "✅", "❌", "🎉", "🚀", "💡", "📌", "📝", "📚", "💼", "🏠", "☕️", "🎵", "🌱", "🌍", "⚙️", "🔒"]),
        ("Smileys & people", "face.smiling", ["😀", "😃", "😄", "😁", "😆", "🥹", "😅", "😂", "🙂", "🙃", "🫠", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😗", "☺️", "😚", "😋", "😛", "😜", "🤪", "😎", "🥳", "🤓", "🧐", "🤠", "🥸", "🤗", "🫡", "🤔", "🫢", "🤭", "🤫", "🤥", "😶", "😐", "😑", "😬", "🫤", "🙄", "😏", "😣", "😥", "😮", "🤐", "😯", "😪", "😫", "🥱", "😴", "😌", "🤤", "😓", "😔", "😕", "🫨", "😲", "☹️", "🙁", "😖", "😞", "😟", "😤", "😢", "😭", "😦", "😧", "😨", "😩", "🤯", "😬", "😰", "😱", "🥵", "🥶", "😳", "🤪", "😵", "😡", "😠", "🤬", "😈", "💀", "☠️", "👋", "🤚", "🖐️", "✋", "🫱", "🫲", "👌", "🤌", "🤏", "✌️", "🤞", "🫶", "🤟", "🤘", "🤙", "👈", "👉", "👆", "👇", "☝️", "👍", "👎", "✊", "👊", "🤝", "🙏", "💪", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💔", "❣️", "💕", "💖", "💗", "💓", "💞", "💘"]),
        ("Animals & nature", "leaf", ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔", "🐧", "🐦", "🦄", "🐝", "🦋", "🐢", "🐙", "🐳", "🐬", "🌸", "🌹", "🌺", "🌻", "🌼", "🌷", "🌱", "🪴", "🌲", "🌳", "🌴", "🍀", "☘️", "🌿", "🍁", "🍂", "🍄", "🌍", "🌎", "🌏", "🌙", "⭐️", "🌟", "✨", "⚡️", "🔥", "🌈", "☀️", "🌤️", "⛅️", "🌧️", "❄️"]),
        ("Food & drink", "fork.knife", ["🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🥑", "🥦", "🥕", "🌽", "🌶️", "🥐", "🍞", "🧀", "🥚", "🍔", "🍟", "🍕", "🌭", "🌮", "🌯", "🥗", "🍝", "🍜", "🍣", "🍱", "🍙", "🍘", "🍰", "🎂", "🍪", "🍫", "🍬", "🍩", "☕️", "🫖", "🍵", "🧃", "🥤", "🍺", "🍷", "🍸"]),
        ("Activities", "gamecontroller", ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏆", "🥇", "🏅", "🎯", "🎮", "🎲", "🧩", "🎨", "🎭", "🎬", "🎤", "🎧", "🎼", "🎵", "🎹", "🥁", "🎸", "📷", "🎥", "✈️", "🚀", "🛸", "🚲", "🏕️", "🏖️", "🗺️"]),
        ("Objects", "lightbulb", ["⌚️", "📱", "💻", "⌨️", "🖥️", "🖨️", "💡", "🔦", "📚", "📖", "📝", "📌", "📍", "📎", "🔗", "📁", "📂", "🗂️", "📅", "📆", "🗓️", "✏️", "🖊️", "🖋️", "✂️", "📏", "🔒", "🔑", "🔨", "🛠️", "⚙️", "🧰", "🧲", "🧪", "💊", "💰", "💳", "🎁", "🎈", "🪄", "🧸", "🛋️", "🛏️", "🚪", "🪴"]),
        ("Symbols", "number", ["✅", "☑️", "✔️", "❌", "❎", "➕", "➖", "➗", "✖️", "‼️", "⁉️", "❓", "❗️", "〽️", "⚠️", "🚫", "♻️", "🔱", "📛", "🔰", "⭕️", "🛑", "💯", "💢", "♠️", "♥️", "♦️", "♣️", "🔔", "🔕", "🔇", "🔊", "📶", "♻️", "⚜️", "🔆", "🔅"])
    ]

    private var shownEmojis: [String] {
        let emojis = categories.first(where: { $0.name == category })?.emojis ?? []
        guard !query.isEmpty else { return emojis }
        return categories.flatMap(\.emojis).filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose an icon")
                    .font(.headline)
                Spacer()
                Button("Remove") { onSelect(nil) }
                    .disabled(selectedIcon == nil)
            }
            .padding()

            TextField("Search emoji", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 10)

            HStack(spacing: 3) {
                ForEach(categories, id: \.name) { item in
                    Button {
                        category = item.name
                        query = ""
                    } label: {
                        Image(systemName: item.icon)
                            .frame(width: 28, height: 26)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(category == item.name ? Color.accentColor : .secondary)
                    .help(item.name)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34)), count: 8), spacing: 4) {
                    ForEach(shownEmojis, id: \.self) { emoji in
                        Button { onSelect(emoji) } label: {
                            Text(emoji)
                                .font(.system(size: 22))
                                .frame(width: 34, height: 34)
                                .background(selectedIcon == emoji ? Color.accentColor.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .frame(width: 340, height: 410)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
