import SwiftUI
import VaniScriptCore

struct DetailRouterView: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        switch store.workflow.screen {
        case .upload:
            UploadWorkspaceView()
        case .config:
            ConfigWorkspaceView()
        case .processing:
            ProcessingWorkspaceView()
        case .review:
            ReviewWorkspaceView()
        case .export:
            ExportWorkspaceView()
        case .visualEditor:
            if let draft = store.visualEditorDraft {
                ClipVisualEditorWorkspace(
                    draft: draft,
                    onCancel: { store.closeVisualEditor() },
                    onSave: { store.saveVisualEditor($0) }
                )
            } else {
                ExportWorkspaceView()
            }
        }
    }
}
