import SwiftUI

struct NoteEditorView: View {
    @Bindable var noteStore: NoteStore
    @Binding var showPreview: Bool

    var body: some View {
        Group {
            if showPreview {
                HSplitOrVStack {
                    editor
                    Divider()
                    preview
                }
            } else {
                editor
            }
        }
        .navigationTitle(noteStore.selectedNote?.title ?? "Note")
        #if os(macOS)
        .navigationSubtitle(noteStore.selectedNote?.fileURL.lastPathComponent ?? "")
        #endif
    }

    private var editor: some View {
        TextEditor(text: Binding(
            get: { noteStore.editorText },
            set: { noteStore.updateEditorText($0) }
        ))
        .font(.body.monospaced())
        .scrollContentBackground(.hidden)
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preview: some View {
        ScrollView {
            Group {
                if let rendered = try? AttributedString(
                    markdown: noteStore.editorText,
                    options: .init(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
                ) {
                    Text(rendered)
                } else {
                    Text(noteStore.editorText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .background(Color(nsColor: .textBackgroundColor))
        #else
        .background(Color(uiColor: .secondarySystemBackground))
        #endif
    }
}

/// Side-by-side on macOS, stacked on iPhone.
private struct HSplitOrVStack<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        HStack(spacing: 0, content: content)
        #else
        VStack(spacing: 0, content: content)
        #endif
    }
}
