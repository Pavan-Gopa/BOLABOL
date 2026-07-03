import NativeSmartScribeCore
import SwiftUI

struct GlossaryCategoryPicker: View {
    @Binding var category: String
    let categories: [String]

    @State private var isAddingCustomCategory = false

    var body: some View {
        HStack(spacing: 8) {
            Picker("Category", selection: selectionBinding) {
                Text("No category").tag(GlossaryCategorySelection.noneID)
                if !categories.isEmpty {
                    Divider()
                    ForEach(categories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                }
                Divider()
                Text("Add Category...").tag(GlossaryCategorySelection.customID)
            }
            .labelsHidden()
            .frame(width: 190)

            if showsCustomField {
                TextField("New category", text: $category)
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
