import NativeBolabolCore
import SwiftUI

struct GlossaryCategoryPicker: View {
    @EnvironmentObject private var generalSettingsStore: GeneralSettingsStore
    @Binding var category: String
    let categories: [String]

    @State private var isAddingCustomCategory = false

    var body: some View {
        HStack(spacing: 8) {
            Picker(generalSettingsStore.text(.category), selection: selectionBinding) {
                Text(generalSettingsStore.text(.noCategory)).tag(GlossaryCategorySelection.noneID)
                if !categories.isEmpty {
                    Divider()
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                Divider()
                Text(generalSettingsStore.text(.addCategory)).tag(GlossaryCategorySelection.customID)
            }
            .labelsHidden()
            .frame(width: 190)

            if showsCustomField {
                TextField(generalSettingsStore.text(.newCategory), text: $category)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var selectionBinding: Binding<String> {
        Binding(
            get: {
                if isAddingCustomCategory {
                    return GlossaryCategorySelection.customID
                }
                return GlossaryCategorySelection.selectionID(
                    for: category,
                    categories: categories
                )
            },
            set: { selectionID in
                isAddingCustomCategory = selectionID == GlossaryCategorySelection.customID
                category = GlossaryCategorySelection.categoryValue(
                    for: selectionID,
                    currentCategory: category,
                    categories: categories
                )
            }
        )
    }

    private var showsCustomField: Bool {
        isAddingCustomCategory
            || GlossaryCategorySelection.selectionID(
                for: category,
                categories: categories
            ) == GlossaryCategorySelection.customID
    }
}
