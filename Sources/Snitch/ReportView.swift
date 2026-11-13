import AppKit
import Observation
import SnitchCore
import SwiftUI

struct DraftImage {
    let fileName: String
    let image: NSImage
}

struct DestinationOption: Equatable {
    let identifier: String
    let name: String
}

@Observable
final class ReportDraftModel {
    var images: [DraftImage] = []
    var destinationOptions: [DestinationOption] = []
    var selectedDestinationIdentifier = ""
    var kind = ReportKind.bug
    var areaName = ""
    var areaSuggestions: [String] = []
    var comment = ""
    var notice: String?
    var focusRequestCount = 0

    @ObservationIgnored var onSend: () -> Void = {}
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var onAddScreenshot: () -> Void = {}
    @ObservationIgnored var onRemoveImage: (String) -> Void = { _ in }
    @ObservationIgnored var onDestinationChange: () -> Void = {}

    var trimmedComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAreaName: String {
        areaName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSend: Bool {
        !trimmedComment.isEmpty && !trimmedAreaName.isEmpty && !images.isEmpty
    }
}

struct ReportView: View {
    @Bindable var model: ReportDraftModel
    @FocusState private var isCommentFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.images, id: \.fileName) { draftImage in
                        thumbnail(for: draftImage)
                    }
                }
            }
            .frame(height: 170)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                if model.destinationOptions.count > 1 {
                    GridRow {
                        Text("Pagina")
                        Picker("Pagina", selection: $model.selectedDestinationIdentifier) {
                            ForEach(model.destinationOptions, id: \.identifier) { option in
                                Text(option.name).tag(option.identifier)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                GridRow {
                    Text("Tipo")
                        .gridColumnAlignment(.trailing)
                    Picker("Tipo", selection: $model.kind) {
                        ForEach(ReportKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    Text("Area")
                    AreaComboBox(
                        text: $model.areaName,
                        suggestions: model.areaSuggestions,
                        onSubmit: { model.onSend() }
                    )
                    .frame(width: 260)
                }
                GridRow {
                    Text("Descrizione")
                    TextField("Che cosa non va?", text: $model.comment)
                        .textFieldStyle(.roundedBorder)
                        .focused($isCommentFocused)
                        .onSubmit { model.onSend() }
                }
            }

            if let notice = model.notice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Aggiungi screenshot") { model.onAddScreenshot() }
                Spacer()
                Button("Annulla") { model.onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Invia") { model.onSend() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canSend)
            }
        }
        .padding(16)
        .frame(width: 500)
        .onAppear { isCommentFocused = true }
        .onChange(of: model.focusRequestCount) { isCommentFocused = true }
        .onChange(of: model.selectedDestinationIdentifier) { model.onDestinationChange() }
    }

    private func thumbnail(for draftImage: DraftImage) -> some View {
        Image(nsImage: draftImage.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 300, maxHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            .overlay(alignment: .topTrailing) {
                if model.images.count > 1 {
                    Button {
                        model.onRemoveImage(draftImage.fileName)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help("Rimuovi questo screenshot")
                }
            }
    }
}

struct AreaComboBox: NSViewRepresentable {
    @Binding var text: String
    let suggestions: [String]
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.usesDataSource = false
        comboBox.completes = true
        comboBox.numberOfVisibleItems = 10
        comboBox.placeholderString = "Scegli o scrivi un'area"
        comboBox.delegate = context.coordinator
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if (comboBox.objectValues as? [String]) != suggestions {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: suggestions)
        }
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: AreaComboBox
        private var isListOpen = false

        init(parent: AreaComboBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox else {
                return
            }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let comboBox = notification.object as? NSComboBox,
                  comboBox.indexOfSelectedItem >= 0,
                  let selectedName = comboBox.itemObjectValue(at: comboBox.indexOfSelectedItem) as? String else {
                return
            }
            parent.text = selectedName
        }

        func comboBoxWillPopUp(_ notification: Notification) {
            isListOpen = true
        }

        func comboBoxWillDismiss(_ notification: Notification) {
            isListOpen = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)), !isListOpen else {
                return false
            }
            parent.text = control.stringValue
            let submit = parent.onSubmit
            DispatchQueue.main.async {
                submit()
            }
            return false
        }
    }
}
