import SwiftUI
import VaniScriptCore

struct SidebarView: View {
    @Binding var selection: UniversalWorkflowScreen?

    var body: some View {
        List(selection: $selection) {
            ForEach(UniversalWorkflowScreen.allCases) { screen in
                Label(screen.title, systemImage: screen.systemImage)
                    .tag(screen)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("VaniScript")
    }
}
