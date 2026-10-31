import SwiftUI

struct BlockEditorView: View {
    @Bindable var noteStore: NoteStore
    @FocusState private var focusedBlockID: UUID?
    @State private var slashStates: [UUID: SlashCommandState] = [:]
    @State private var selectedSlashCommandIndices: [UUID: Int] = [:]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(noteStore.editorBlocks.enumerated()), id: \.element.id) { index, block in
                    blockRow(at: index, block: block)
                }

                Color.clear
                    .frame(height: 120)
                    .contentShape(Rectangle())
                    .onTapGesture { appendParagraphAtEnd() }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(noteStore.selectedNote?.title ?? "Note")
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
            focusedBlockID = noteStore.editorBlocks.first?.id
        }
        #if os(macOS)
        .onKeyPress(phases: .down) { press in
            if press.key == .delete {
                deleteEmptyFocusedBlock()
                return .ignored
            }

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
            Text("Type / for block types · ↩ for a new text block · ⇧↩ for a line break")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func blockRow(at index: Int, block: Block) -> some View {
        BlockRowView(
            block: binding(for: index),
            listMarker: listMarker(for: block, at: index),
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
                } else {
                    insertBlock(after: block.id, kind: .paragraph)
                }
            }
        )
    }

    private func binding(for index: Int) -> Binding<Block> {
        Binding(
            get: { noteStore.editorBlocks[index] },
            set: { noteStore.editorBlocks[index] = $0 }
        )
    }

    private func listMarker(for block: Block, at index: Int) -> String? {
        switch block.kind {
        case .bullet:
            return "•"
        case .numbered:
            let number = noteStore.editorBlocks[..<index].filter { $0.kind == .numbered }.count + 1
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
        guard let index = noteStore.editorBlocks.firstIndex(where: { $0.id == blockID }) else { return }
        var block = noteStore.editorBlocks[index]
        if let slash = slashStates[blockID] {
            block.text = String(block.text.dropLast(slash.suffixLength))
        }
        block.kind = kind
        if kind == .divider {
            block.text = ""
        }
        noteStore.editorBlocks[index] = block
        slashStates[blockID] = nil
        selectedSlashCommandIndices[blockID] = nil
        noteStore.commitEditorBlocks(noteStore.editorBlocks)

        if kind == .divider {
            insertBlock(after: blockID, kind: .paragraph)
        }
        focusedBlockID = blockID
    }

    private func insertBlock(after blockID: UUID, kind: BlockKind) {
        guard let index = noteStore.editorBlocks.firstIndex(where: { $0.id == blockID }) else { return }
        let newBlock = Block(kind: kind)
        noteStore.editorBlocks.insert(newBlock, at: index + 1)
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = newBlock.id
    }

    private func appendParagraphAtEnd() {
        let block = Block(kind: .paragraph)
        noteStore.editorBlocks.append(block)
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = block.id
    }

    private func deleteEmptyFocusedBlock() {
        guard let id = focusedBlockID,
              let index = noteStore.editorBlocks.firstIndex(where: { $0.id == id }),
              noteStore.editorBlocks[index].text.isEmpty,
              noteStore.editorBlocks.count > 1
        else { return }

        let previousID = index > 0 ? noteStore.editorBlocks[index - 1].id : nil
        noteStore.editorBlocks.remove(at: index)
        noteStore.commitEditorBlocks(noteStore.editorBlocks)
        focusedBlockID = previousID ?? noteStore.editorBlocks.first?.id
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

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
