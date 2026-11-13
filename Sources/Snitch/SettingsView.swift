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
    var newPageTitle = ""
    var newPageParentAddress = ""
    var creationMessage = ""
    var isCreating = false

    @ObservationIgnored var onRecordingChange: (Bool) -> Void = { _ in }
    @ObservationIgnored var onTokenSaved: () -> Void = {}

    init(settings: AppSettings) {
        self.settings = settings
        launchAtLogin = LaunchAtLogin.isEnabled
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
            listMessage = "Indirizzo non riconosciuto: incolla l'indirizzo https della pagina come compare nel browser."
            return
        }
        guard settings.destination(for: reference) == nil else {
            listMessage = "Questa pagina è già nell'elenco."
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
                    destinationMessages[identifier] = "Collegata. \(FailureDescription.missingTableText)"
                } else if summary.areaNames.isEmpty {
                    destinationMessages[identifier] = "Collegata. La tabella è vuota."
                } else {
                    destinationMessages[identifier] = "Collegata: \(summary.rowCount) righe. Aree: \(summary.areaNames.joined(separator: ", "))."
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
            tokenMessage = "Non riesco a salvare il token nel Portachiavi."
            return
        }
        tokenInputs[host] = ""
        tokenMessage = "Token per \(host) salvato nel Portachiavi."
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

    func createPage() {
        let title = newPageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            creationMessage = "Scrivi il titolo della nuova pagina."
            return
        }
        guard let parent = PageReference(pageAddress: newPageParentAddress) else {
            creationMessage = "Indirizzo della pagina madre non riconosciuto."
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
                    storage: PageTemplate.storage()
                )
                let reference = PageReference(baseURL: parent.baseURL, pageIdentifier: pageIdentifier)
                let destination = settings.addDestination(address: reference.viewURL.absoluteString, title: title)
                settings.lastDestinationIdentifier = destination.identifier
                newPageTitle = ""
                creationMessage = "Pagina «\(title)» creata sotto «\(parentPage.title)» e aggiunta all'elenco."
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
            Section("Pagine") {
                if model.settings.destinations.isEmpty {
                    Text("Nessuna pagina: aggiungine una qui sotto o creane una dal modello.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.settings.destinations, id: \.identifier) { destination in
                    destinationRow(for: destination)
                }
                HStack {
                    TextField(
                        "Aggiungi",
                        text: $model.newAddress,
                        prompt: Text("https://…/pages/viewpage.action?pageId=…")
                    )
                    .onSubmit { model.addDestination() }
                    Button("Aggiungi") { model.addDestination() }
                        .disabled(model.newAddress.isEmpty)
                }
                if !model.listMessage.isEmpty {
                    caption(model.listMessage)
                }
            }

            Section("Token di accesso") {
                if model.hosts.isEmpty {
                    Text("Aggiungi una pagina: qui comparirà il campo per il token del suo Confluence.")
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
                            prompt: Text(model.hostsWithToken.contains(host) ? "Salvato nel Portachiavi" : "Incolla il token personale")
                        )
                        .onSubmit { model.saveToken(forHost: host) }
                        Button("Salva") { model.saveToken(forHost: host) }
                            .disabled((model.tokenInputs[host] ?? "").isEmpty)
                    }
                }
                if !model.tokenMessage.isEmpty {
                    caption(model.tokenMessage)
                }
            }

            Section("Uso") {
                LabeledContent("Scorciatoia") {
                    ShortcutRecorderView(
                        combination: model.settings.hotKey,
                        onRecordingChange: { model.onRecordingChange($0) },
                        onChange: { model.settings.hotKey = $0 }
                    )
                }
                Toggle("Avvia al login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            Section("Nuova pagina da modello") {
                Text("Crea una pagina con la tabella vuota (\(PageTemplate.columnTitles.joined(separator: ", "))) e la aggiunge all'elenco.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Titolo", text: $model.newPageTitle, prompt: Text("Bug del progetto"))
                TextField(
                    "Pagina madre",
                    text: $model.newPageParentAddress,
                    prompt: Text("Indirizzo della pagina sotto cui crearla")
                )
                HStack {
                    Button("Crea pagina") { model.createPage() }
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
            Button("Verifica") { model.verify(destination.identifier) }
                .disabled(model.verifyingIdentifiers.contains(destination.identifier))
            Button {
                model.removeDestination(destination.identifier)
            } label: {
                Image(systemName: "trash")
            }
            .help("Togli la pagina dall'elenco (la pagina su Confluence non viene toccata)")
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
        Button(isRecording ? "Premi la nuova scorciatoia…" : combination.display) {
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
