import SwiftUI

struct NoteEditorView: View {
    @Bindable var noteStore: NoteStore

    var body: some View {
        BlockEditorView(noteStore: noteStore)
    }
}
