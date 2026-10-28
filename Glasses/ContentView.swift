import SwiftUI
import Combine
import CoreBluetooth
import UIKit
import Photos
import AIBuds
import AIBudsFoundation
import ABMate

@main
struct GlassesApp: App {
    @StateObject private var model = GlassesViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .tint(AppTheme.accent)
        }
    }
}

enum AppTheme {
    static let accent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.706, green: 0.867, blue: 0.075, alpha: 1)
            : UIColor(red: 0.365, green: 0.510, blue: 0.000, alpha: 1)
    })
}

@MainActor
final class GlassesViewModel: NSObject, ObservableObject, SDKDelegate, DeviceDelegate {
    struct NearbyDevice: Identifiable {
        let id: String
        let name: String
        let rssi: Int
        let found: FoundDeviceConvertible
    }

    struct SavedDevice: Identifiable {
        let id: String
        let name: String
        let device: DeviceConvertible
    }

    struct MediaItem: Identifiable {
        let id: String
        let file: MediaFileInfoModel
    }

    enum Status: Equatable {
        case idle, scanning, connecting, connected, error

        var title: String {
            switch self {
            case .idle: NSLocalizedString("Not connected", comment: "Connection status")
            case .scanning: NSLocalizedString("Searching for glasses…", comment: "Connection status")
            case .connecting: NSLocalizedString("Connecting…", comment: "Connection status")
            case .connected: NSLocalizedString("Connected", comment: "Connection status")
            case .error: NSLocalizedString("Connection issue", comment: "Connection status")
            }
        }

        var symbol: String {
            switch self {
            case .idle: "sunglasses"
            case .scanning: "antenna.radiowaves.left.and.right"
            case .connecting: "arrow.trianglehead.2.clockwise"
            case .connected: "checkmark.circle.fill"
            case .error: "exclamationmark.circle"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var devices: [NearbyDevice] = []
    @Published private(set) var savedDevices: [SavedDevice] = []
    @Published private(set) var connectedName: String?
    @Published private(set) var isVideoRecording = false
    @Published private(set) var isAudioRecording = false
    @Published private(set) var mediaCountText: String?
    @Published private(set) var mediaItems: [MediaItem] = []
    @Published var selectedMediaIDs: Set<String> = []
    @Published private(set) var mediaImportStatus: String?
    @Published private(set) var isMediaImportBusy = false
    @Published private(set) var importedMediaCount = 0
    @Published private(set) var photoExportStatus: String?
    @Published var errorMessage: String?

    private var sdkInitialized = false
    private var currentDevice: DeviceConvertible?
    private var connectionAttemptID = UUID()

    func initialize() {
        guard !sdkInitialized else { return }

        guard AIBudsSDK.initialize([ABMateSDK.shared], delegate: self) else {
            status = .error
            errorMessage = "AIBuds SDK initialization failed. Check the Bluetooth usage descriptions and SDK setup."
            return
        }
        sdkInitialized = true
        loadSavedDevices()
    }

    private func loadSavedDevices() {
        StoredDevicesMgr.loadDevicesInBackgroundWithCompletion { [weak self] devices, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                self.savedDevices = devices.map { device in
                    device.delegate = self
                    device.shouldAutoReconnectWhenAppLaunch = UserDefaults.standard.object(forKey: "autoReconnect") as? Bool ?? true
                    return SavedDevice(id: device.uuid.uuidString, name: device.name, device: device)
                }
            }
        }
    }

    func scan() {
        initialize()
        guard sdkInitialized else { return }
        errorMessage = nil
        devices = []
        status = .scanning
        AIBudsSDK.startScanning(nil, deviceFoundHandler: { [weak self] found, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                let item = NearbyDevice(
                    id: found.peripheral.identifier.uuidString,
                    name: found.peripheral.name ?? "",
                    rssi: found.RSSI?.intValue ?? 0,
                    found: found
                )
                if let index = self.devices.firstIndex(where: { $0.id == item.id }) {
                    self.devices[index] = item
                } else {
                    self.devices.append(item)
                }
            }
        }, completion: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.status == .scanning else { return }
                self.status = .idle
                if self.devices.isEmpty {
                    self.errorMessage = "No compatible AIBuds devices found. Check that the glasses are on and nearby."
                }
            }
        })
    }

    func connect(to nearby: NearbyDevice) {
        AIBudsSDK.stopScanning()
        guard let device = AIBudsSDK.makeStorableDeviceFromDiscovered(nearby.found) else {
            status = .error
            errorMessage = "The SDK could not prepare this discovered device for connection."
            return
        }
        currentDevice = device
        device.delegate = self
        _ = StoredDevicesMgr.addDevice(device)
        StoredDevicesMgr.saveDevicesInBackgroundWithCompletion(nil)
        status = .connecting
        errorMessage = nil
        beginConnectionTimeout()
        device.connect(ConnectParams())
    }

    func connect(to saved: SavedDevice) {
        AIBudsSDK.stopScanning()
        currentDevice = saved.device
        saved.device.delegate = self
        status = .connecting
        errorMessage = nil
        beginConnectionTimeout()
        saved.device.connect(ConnectParams())
    }

    private func beginConnectionTimeout() {
        let attemptID = UUID()
        connectionAttemptID = attemptID
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard let self, self.connectionAttemptID == attemptID, self.status == .connecting else { return }
            self.currentDevice?.disconnect()
            self.currentDevice = nil
            self.status = .error
            self.errorMessage = "The glasses did not finish connecting. Check that they are on and nearby, then try again."
        }
    }

    func disconnect() {
        currentDevice?.disconnect()
    }

    func setAutoReconnect(_ enabled: Bool) {
        savedDevices.forEach { $0.device.shouldAutoReconnectWhenAppLaunch = enabled }
        currentDevice?.shouldAutoReconnectWhenAppLaunch = enabled
    }

    func takePhoto() {
        guard let camera = currentDevice as? DeviceCameraAPI else {
            errorMessage = "Camera control is not available for this device."
            return
        }
        camera.requestPhotoTaking(withCaptureMode: .camera, completion: nil)
    }

    func toggleVideoRecording() {
        guard let camera = currentDevice as? DeviceCameraAPI else {
            errorMessage = "Video control is not available for this device."
            return
        }
        if isVideoRecording {
            camera.requestStopVideoRecording(nil)
        } else {
            camera.requestVideoRecording(nil)
        }
        isVideoRecording.toggle()
    }

    func toggleAudioRecording() {
        guard let audio = currentDevice as? DeviceAudioRecordingAPI else {
            errorMessage = "Audio recording is not available for this device."
            return
        }
        if isAudioRecording {
            audio.requestStopAudioRecording(nil)
        } else {
            audio.requestStartAudioRecording(nil)
        }
        isAudioRecording.toggle()
    }

    func toggleMusic() {
        guard let music = currentDevice as? DeviceMusicControlAPI else {
            errorMessage = "Music control is not available for this device."
            return
        }
        music.playMusic(nil)
    }

    func queryMediaCount() {
        guard let info = currentDevice as? DeviceInfoAPI else {
            errorMessage = "Media information is not available for this device."
            return
        }
        info.requestQueryMediaCountInfo(nil)
        if let count = info.mediaCountInfo {
            mediaCountText = "Photos: \(count.photoCount) · Videos: \(count.videoCount) · Audio: \(count.audioCount)"
        }
    }

    func fetchMediaFiles() {
        guard let mediaAPI = currentDevice as? DeviceMediaFileImportAPI else {
            errorMessage = "Media import is not available for this device."
            return
        }
        isMediaImportBusy = true
        mediaImportStatus = "Preparing the glasses and local network…"
        mediaAPI.fetchMediaFilesInfo(
            configureHotspotStartingHandler: nil,
            hotspotConfigureCompletionHandler: nil,
            enterFileTransferModeStartingHandler: nil,
            enterFileTransferModeCompletedHandler: nil,
            waitingForHotspotOpenHandler: nil,
            connectDeviceHotspotStartingHandler: nil,
            deviceHotspotConnectCompletionHandler: nil
        ) { [weak self] success, files, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMediaImportBusy = false
                if success {
                    self.mediaItems = files.map { MediaItem(id: $0.fileName, file: $0) }
                    self.selectedMediaIDs = Set(self.mediaItems.map(\.id))
                    self.mediaImportStatus = "Found \(files.count) media file(s). Select files to import."
                } else {
                    self.mediaImportStatus = nil
                    self.errorMessage = error?.localizedDescription ?? "The glasses could not provide a media list."
                }
            }
        }
    }

    func importSelectedMedia(autoExport: Bool) {
        guard let mediaAPI = currentDevice as? DeviceMediaFileImportAPI else { return }
        let selected = mediaItems.filter { selectedMediaIDs.contains($0.id) }.map(\.file)
        guard !selected.isEmpty else { return }
        isMediaImportBusy = true
        mediaImportStatus = "Importing media…"
        mediaAPI.importMediaFiles(
            selected,
            dataChunkHandler: nil,
            singleTransferStartingHandler: nil,
            singleTransferCompletionHandler: nil,
            transferSpeedHandler: nil,
            transferBatchProgressHandler: { [weak self] index, total in
                DispatchQueue.main.async {
                    self?.mediaImportStatus = "Importing file \(index + 1) of \(total)…"
                }
            },
            videoStabilizationPhaseBeginHandler: nil,
            videoStabilizationSingleFileProgressHandler: nil,
            videoStabilizationSingleFileCompletionHandler: nil,
            videoStabilizationBatchProgressHandler: nil,
            videoStabilizationPhaseFinishHandler: nil
        ) { [weak self] success, importedFiles, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMediaImportBusy = false
                if success {
                    self.importedMediaCount = importedFiles.count
                    self.mediaImportStatus = "Imported \(importedFiles.count) file(s)."
                    if autoExport {
                        self.exportToPhotos(importedFiles)
                    }
                } else {
                    self.errorMessage = error?.localizedDescription ?? "Media import failed."
                    self.mediaImportStatus = nil
                }
            }
        }
    }

    private func exportToPhotos(_ files: [ImportedMediaFileModel]) {
        let exportable = files.compactMap { file -> (URL, MediaFileType)? in
            guard let url = file.stabilizedFileURL ?? file.localFileURL else { return nil }
            guard file.metadata.fileType == .image || file.metadata.fileType == .video else { return nil }
            return (url, file.metadata.fileType)
        }
        guard !exportable.isEmpty else {
            photoExportStatus = "No photos or videos to save to Photos."
            return
        }

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] authorization in
            guard authorization == .authorized || authorization == .limited else {
                DispatchQueue.main.async { self?.photoExportStatus = "Photos access is required to save imported media." }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for (url, type) in exportable {
                    if type == .image {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    }
                }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.photoExportStatus = "Saved to Photos."
                    } else {
                        self?.photoExportStatus = error?.localizedDescription ?? "Could not save media to Photos."
                    }
                }
            }
        }
    }

    func cancelMediaImport() {
        (currentDevice as? DeviceMediaFileImportAPI)?.cancelMediaFileImport(nil)
        isMediaImportBusy = false
        mediaImportStatus = "Media import cancelled."
    }

    func didStartConnectingDevice(_ device: DeviceConvertible) {
        status = .connecting
    }

    func didConnectedToDevice(_ device: DeviceConvertible) {
        connectionAttemptID = UUID()
        connectedName = device.name
        status = .connected
        errorMessage = nil
    }

    func didFailToConnectDevice(_ device: DeviceConvertible?, error: NSError?) {
        connectionAttemptID = UUID()
        status = .error
        errorMessage = error?.localizedDescription ?? "The SDK could not connect to this device."
    }

    func device(_ device: DeviceConvertible?, didDisconnectWithError error: NSError?) {
        connectionAttemptID = UUID()
        currentDevice = nil
        connectedName = nil
        if let error {
            status = .error
            errorMessage = error.localizedDescription
        } else {
            status = .idle
        }
    }

    func deviceDidReady(_ device: DeviceConvertible) {
        connectionAttemptID = UUID()
        connectedName = device.name
        status = .connected
        errorMessage = nil
    }

    func device(_ device: DeviceConvertible, didMediaCountInfoChanged mediaCountInfo: MediaCountInfoModel) {
        mediaCountText = "Photos: \(mediaCountInfo.photoCount) · Videos: \(mediaCountInfo.videoCount) · Audio: \(mediaCountInfo.audioCount)"
    }
}

struct ContentView: View {
    @ObservedObject var model: GlassesViewModel
    @AppStorage("showImportDisclaimer") private var showImportDisclaimer = true
    @AppStorage("autoExportMedia") private var autoExportMedia = true
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("autoReconnect") private var autoReconnect = true
    @State private var showingImportDisclaimer = false

    var body: some View {
        TabView {
            homeTab
                .tabItem { Label("My Glasses", systemImage: "sunglasses") }
            controlsTab
                .tabItem { Label("Control", systemImage: "slider.horizontal.3") }
            mediaTab
                .tabItem { Label("Media", systemImage: "photo.on.rectangle") }
            settingsTab
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { model.initialize() }
        .preferredColorScheme(appearanceMode == "light" ? .light : appearanceMode == "dark" ? .dark : nil)
        .alert("Experimental media import", isPresented: $showingImportDisclaimer) {
            Button("Cancel", role: .cancel) { }
            Button("Import") { model.importSelectedMedia(autoExport: autoExportMedia) }
            Button("Import & don't show again") {
                showImportDisclaimer = false
                model.importSelectedMedia(autoExport: autoExportMedia)
            }
        } message: {
            Text("Import uses the glasses hotspot and local network. It may be unstable, temporarily interrupt Bluetooth, and save files to Photos. Continue only if you understand these limitations.")
        }
    }

    private var homeTab: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(model.status.title, systemImage: model.status.symbol)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(model.status == .connected ? .green : .primary)
                        if let name = model.connectedName { Text(name).foregroundStyle(.secondary) }
                        if model.status == .connected {
                            Button("Disconnect", role: .destructive, action: model.disconnect)
                        } else {
                            Button(action: model.scan) {
                                Label(model.status == .scanning ? "Scanning" : "Find My Glasses",
                                      systemImage: "antenna.radiowaves.left.and.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.status == .scanning || model.status == .connecting)
                        }
                    }.padding(.vertical, 8)
                }
                if let message = model.errorMessage {
                    Section("Connection issue") {
                        Text(message).foregroundStyle(.red)
                        Button("Try Again", action: model.scan)
                    }
                }
                Section("Discover") {
                    if model.devices.isEmpty {
                        Text(model.status == .scanning ? "Looking for compatible glasses…" : "No nearby glasses found")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.devices) { device in
                        deviceRow(device)
                    }
                }
                if !model.savedDevices.isEmpty {
                    Section("Your Glasses") {
                        ForEach(model.savedDevices) { device in
                            HStack {
                                Label(device.name.isEmpty ? "Unnamed glasses" : device.name, systemImage: "sunglasses")
                                Spacer()
                                Button("Connect") { model.connect(to: device) }
                                    .disabled(model.status == .connecting || model.status == .connected)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Glasses")
        }
    }

    private func deviceRow(_ device: GlassesViewModel.NearbyDevice) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(device.name.isEmpty ? "Unnamed glasses" : device.name).font(.body.weight(.medium))
                Text("RSSI \(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Connect") { model.connect(to: device) }
                .disabled(model.status == .connecting || model.status == .connected)
        }
    }

    private var controlsTab: some View {
        NavigationView {
            List {
                Section("Camera") {
                    Button(action: model.takePhoto) {
                        Label("Take Photo", systemImage: "camera")
                    }
                    .disabled(model.status != .connected)
                    Button(action: model.toggleVideoRecording) {
                        Label(model.isVideoRecording ? "Stop Video" : "Start Video",
                              systemImage: model.isVideoRecording ? "stop.circle.fill" : "video")
                    }
                    .disabled(model.status != .connected)
                }
                Section("Audio") {
                    Button(action: model.toggleAudioRecording) {
                        Label(model.isAudioRecording ? "Stop Audio Recording" : "Start Audio Recording",
                              systemImage: model.isAudioRecording ? "stop.circle.fill" : "waveform")
                    }
                    .disabled(model.status != .connected)
                }
                Section("Music") {
                    Button(action: model.toggleMusic) {
                        Label("Play on Glasses", systemImage: "play.fill")
                    }
                    .disabled(model.status != .connected)
                    Text("Music controls depend on the connected glasses and the SDK-supported firmware.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Storage") {
                    Button("Refresh Media Count", action: model.queryMediaCount)
                        .disabled(model.status != .connected)
                    if let text = model.mediaCountText {
                        Text(text).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Control")
        }
    }

    private var mediaTab: some View {
        NavigationView {
            List {
                Section {
                    Label("Import from your glasses", systemImage: "arrow.down.circle")
                        .font(.headline)
                    Text("Photos and videos are transferred over the glasses hotspot, then saved to your Photos library automatically.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Find Photos and Videos", action: model.fetchMediaFiles)
                        .disabled(model.status != .connected || model.isMediaImportBusy)
                    if let status = model.mediaImportStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if let status = model.photoExportStatus { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if model.isMediaImportBusy { Button("Cancel", role: .cancel, action: model.cancelMediaImport) }
                } footer: {
                    Text("Experimental feature. A disclaimer appears before every import unless disabled in Settings.")
                }
                if !model.mediaItems.isEmpty {
                    Section("Select files") {
                        ForEach(model.mediaItems) { item in
                            Toggle(isOn: Binding(get: {
                                model.selectedMediaIDs.contains(item.id)
                            }, set: { selected in
                                if selected { model.selectedMediaIDs.insert(item.id) }
                                else { model.selectedMediaIDs.remove(item.id) }
                            })) {
                                Label(item.file.fileName, systemImage: item.file.fileType == .video ? "video" : "photo")
                                    .lineLimit(1)
                            }
                        }
                        Button("Import Selected") { beginImport() }
                            .disabled(model.isMediaImportBusy || model.selectedMediaIDs.isEmpty)
                    }
                }
            }
            .navigationTitle("Media")
        }
    }

    private var settingsTab: some View {
        NavigationView {
            Form {
                Section("Import") {
                    Toggle("Show import disclaimer", isOn: $showImportDisclaimer)
                    Toggle("Save imported media to Photos", isOn: $autoExportMedia)
                    Text("The disclaimer explains hotspot, local-network, and Photos access requirements.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.menu)
                }
                Section("Connection") {
                    Toggle("Reconnect automatically", isOn: $autoReconnect)
                        .onChange(of: autoReconnect) { enabled in
                            model.setAutoReconnect(enabled)
                        }
                    Text("Try to reconnect when the app starts and a saved device is available.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Privacy & Access") {
                    Label("Bluetooth", systemImage: "bolt.horizontal.circle")
                    Label("Local network", systemImage: "network")
                    Label("Photos", systemImage: "photo.on.rectangle")
                    Text("Permissions are requested only when a feature needs them. You can change them in iPhone Settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("About") {
                    Label("Glasses", systemImage: "sunglasses")
                    Text("A focused companion for compatible AIBuds smart glasses.")
                        .foregroundStyle(.secondary)
                    Text("Media transfer is experimental and depends on the glasses firmware and iPhone network permissions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func beginImport() {
        if showImportDisclaimer { showingImportDisclaimer = true }
        else { model.importSelectedMedia(autoExport: autoExportMedia) }
    }
}
