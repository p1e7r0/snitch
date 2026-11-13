import AppKit
import Observation
import ServiceManagement
import SnitchCore
import SwiftUI

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ isEnabled: Bool) -> Bool {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}

@Observable
final class SettingsModel {
    let settings: AppSettings
    var newAddress = ""
    var listMessage = ""
    var destinationMessages: [String: String] = [:]
    var verifyingIdentifiers: Set<String> = []
    var tokenInputs: [String: String] = [:]
    var hostsWithToken: Set<String> = []
    var tokenMessage = ""
    var launchAtLogin: Bool
    var language: AppLanguage
    var newPageTitle = ""
    var newPageParentAddress = ""
    var creationMessage = ""
    var isCreating = false

    @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }
    @ObservationIgnored var onTokenSaved: () -> Void = {}
    @ObservationIgnored var onRestart: () -> Void = {}
    @ObservationIgnored private let launchLanguage: AppLanguage

    init(settings: AppSettings, launchLanguage: AppLanguage) {
        self.settings = settings
        self.launchLanguage = launchLanguage
        launchAtLogin = LaunchAtLogin.isEnabled
        language = AppLanguage.selected
        refreshTokenState()
    }

    var hosts: [String] {
        var hosts: [String] = []
        for address in settings.destinations.map(\.address) + [newAddress, newPageParentAddress] {
            if let host = PageReference(pageAddress: address)?.host, !hosts.contains(host) {
                hosts.append(host)
            }
        }
        return hosts
    }

    func refreshTokenState() {
        hostsWithToken = Set(hosts.filter { TokenStore.read(host: $0) != nil })
    }

    func addDestination() {
        let address = newAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reference = PageReference(pageAddress: address) else {
            listMessage = String(localized: "Address not recognized: paste the https address of the page as it appears in the browser.")
            return
        }
        guard settings.destination(for: reference) == nil else {
            listMessage = String(localized: "This page is already in the list.")
            return
        }
        let destination = settings.addDestination(address: address)
        newAddress = ""
        listMessage = ""
        verify(destination.identifier)
    }

    func removeDestination(_ identifier: String) {
        settings.removeDestination(withIdentifier: identifier)
        destinationMessages[identifier] = nil
    }

    func verify(_ identifier: String) {
        verifyingIdentifiers.insert(identifier)
        destinationMessages[identifier] = nil
        Task {
            defer { verifyingIdentifiers.remove(identifier) }
            do {
                let summary = try await settings.refreshDestination(withIdentifier: identifier)
                if !summary.hasTable {
                    destinationMessages[identifier] = String(localized: "Connected. \(FailureDescription.missingTableText)")
                } else if summary.areaNames.isEmpty {
                    destinationMessages[identifier] = String(localized: "Connected. The table is empty.")
                } else {
                    destinationMessages[identifier] = String(localized: "Connected: \(summary.rowCount) rows. Areas: \(summary.areaNames.joined(separator: ", ")).")
                }
            } catch {
                destinationMessages[identifier] = FailureDescription.text(for: error)
            }
        }
    }

    func saveToken(forHost host: String) {
        let token = (tokenInputs[host] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return
        }
        guard TokenStore.save(token, host: host) else {
            tokenMessage = String(localized: "Could not save the token to the Keychain.")
            return
        }
        tokenInputs[host] = ""
        tokenMessage = String(localized: "Token for \(host) saved to the Keychain.")
        refreshTokenState()
        for destination in settings.destinations where destination.host == host {
            verify(destination.identifier)
        }
        onTokenSaved()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        LaunchAtLogin.setEnabled(isEnabled)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    var needsRestartToChangeLanguage: Bool {
        language != launchLanguage
    }

    func setLanguage(_ language: AppLanguage) {
        AppLanguage.select(language)
        self.language = language
    }

    func createPage() {
        let title = newPageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            creationMessage = String(localized: "Enter the title of the new page.")
            return
        }
        guard let parent = PageReference(pageAddress: newPageParentAddress) else {
            creationMessage = String(localized: "Parent page address not recognized.")
            return
        }
        isCreating = true
        creationMessage = ""
        Task {
            defer { isCreating = false }
            do {
                let client = try TokenStore.makeClient(for: parent)
                let parentPage = try await client.fetchPage(parent.pageIdentifier)
                let pageIdentifier = try await client.createPage(
                    title: title,
                    spaceKey: parentPage.spaceKey,
                    parentIdentifier: parent.pageIdentifier,
                    storage: PageTemplate.storage(language: .current)
                )
                let reference = PageReference(baseURL: parent.baseURL, pageIdentifier: pageIdentifier)
                let destination = settings.addDestination(address: reference.viewURL.absoluteString, title: title)
                settings.lastDestinationIdentifier = destination.identifier
                newPageTitle = ""
                creationMessage = String(localized: "Page “\(title)” created under “\(parentPage.title)” and added to the list.")
                NSWorkspace.shared.open(reference.viewURL)
            } catch {
                creationMessage = FailureDescription.text(for: error)
            }
        }
    }
}

struct SettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section("Pages") {
                if model.settings.destinations.isEmpty {
                    Text("No pages: add one below or create one from the template.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.settings.destinations, id: \.identifier) { destination in
                    destinationRow(for: destination)
                }
                HStack {
                    TextField(
                        "Add",
                        text: $model.newAddress,
                        prompt: Text(verbatim: "https://…/pages/viewpage.action?pageId=…")
                    )
                    .onSubmit { model.addDestination() }
                    Button("Add") { model.addDestination() }
                        .disabled(model.newAddress.isEmpty)
                }
                if !model.listMessage.isEmpty {
                    caption(model.listMessage)
                }
            }

            Section("Access tokens") {
                if model.hosts.isEmpty {
                    Text("Add a page: the field for its Confluence token will appear here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.hosts, id: \.self) { host in
                    HStack {
                        SecureField(
                            host,
                            text: Binding(
                                get: { model.tokenInputs[host] ?? "" },
                                set: { model.tokenInputs[host] = $0 }
                            ),
                            prompt: Text(
                                model.hostsWithToken.contains(host)
                                    ? String(localized: "Saved in the Keychain")
                                    : String(localized: "Paste the personal access token")
                            )
                        )
                        .onSubmit { model.saveToken(forHost: host) }
                        Button("Save") { model.saveToken(forHost: host) }
                            .disabled((model.tokenInputs[host] ?? "").isEmpty)
                    }
                }
                if !model.tokenMessage.isEmpty {
                    caption(model.tokenMessage)
                }
            }

            Section("Usage") {
                LabeledContent("Shortcut") {
                    ShortcutRecorderView(
                        combination: model.settings.hotKey,
                        onRecordingChange: { model.onRecordingChange($0) },
                        onChange: { model.settings.hotKey = $0 }
                    )
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Picker("Language", selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                if model.needsRestartToChangeLanguage {
                    HStack {
                        caption(String(localized: "The language changes when Snitch restarts."))
                        Spacer()
                        Button("Restart now") { model.onRestart() }
                    }
                }
            }

            Section("New page from template") {
                Text("Creates a page with the empty table (\(PageTemplate.columnTitles(in: .current).joined(separator: ", "))) and adds it to the list.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Title", text: $model.newPageTitle, prompt: Text("Project bugs"))
                TextField(
                    "Parent page",
                    text: $model.newPageParentAddress,
                    prompt: Text("Address of the page to create it under")
                )
                HStack {
                    Button("Create page") { model.createPage() }
                        .disabled(model.isCreating)
                    if model.isCreating {
                        ProgressView().controlSize(.small)
                    }
                }
                if !model.creationMessage.isEmpty {
                    caption(model.creationMessage)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 580)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.hosts) { model.refreshTokenState() }
    }

    private func destinationRow(for destination: Destination) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if destination.title != nil {
                    Text(destination.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let message = model.destinationMessages[destination.identifier] {
                    caption(message)
                }
            }
            Spacer()
            if model.verifyingIdentifiers.contains(destination.identifier) {
                ProgressView().controlSize(.small)
            }
            Button("Verify") { model.verify(destination.identifier) }
                .disabled(model.verifyingIdentifiers.contains(destination.identifier))
            Button {
                model.removeDestination(destination.identifier)
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove the page from the list (the page on Confluence is not touched)")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct ShortcutRecorderView: View {
    let combination: HotKeyCombination
    let onRecordingChange: (Bool) -> Void
    let onChange: (HotKeyCombination) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    private static let escapeKeyCode: UInt16 = 53

    var body: some View {
        Button(isRecording ? String(localized: "Press the new shortcut…") : combination.display) {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == Self.escapeKeyCode {
                stopRecording()
            } else if let newCombination = HotKeyCombination.from(event: event) {
                onChange(newCombination)
                stopRecording()
            }
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else {
            return
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        isRecording = false
        onRecordingChange(false)
    }
}
