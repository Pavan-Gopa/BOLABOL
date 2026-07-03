import SwiftUI

struct ProcessingWorkspaceView: View {
    @EnvironmentObject private var store: WorkflowStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            LogoHeader(compact: true)
                .padding(.bottom, 32)

            VStack(spacing: 20) {
                ProgressView()
                    .controlSize(.large)
                    .tint(VaniScriptTheme.accent)
                Text("Processing Data...")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(VaniScriptTheme.text0)
                ProgressView(value: store.workflow.processingProgress)
                    .tint(VaniScriptTheme.accent)
                    .frame(width: 360)
                Text(store.workflow.processingMessage.isEmpty ? "Preparing chunks" : store.workflow.processingMessage)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(VaniScriptTheme.accent)
                Text("This may take a moment depending on the length of the audio track.")
                    .font(.system(size: 11))
                    .foregroundStyle(VaniScriptTheme.text2)
            }
            .frame(width: 480)
            .padding(48)
            .glassPanel()

            AppFooter()
                .padding(.top, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
