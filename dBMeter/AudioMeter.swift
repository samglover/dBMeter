import AVFoundation
import AudioToolbox
import Combine
import Foundation

struct AudioInputDevice: Identifiable, Hashable {
    let id: String
    let name: String
}

private let systemDefaultInputID = "__system_default_input__"

@MainActor
final class AudioMeter: ObservableObject {
    enum AlertLevel {
        case none
        case yellow
        case red
    }

    @Published private(set) var decibelLevel: Float = -80.0
    @Published private(set) var peakLevel: Float = -80.0
    @Published private(set) var statusText: String = "Requesting microphone access..."
    @Published private(set) var isRunning = false
    @Published private(set) var availableInputs: [AudioInputDevice] = []
    @Published private(set) var isFlashVisible = true

    @Published var selectedInputID: String = ""
    @Published var yellowThreshold: Float = 65.0
    @Published var redThreshold: Float = 75.0
    @Published var smoothing: Double = 0.65

    private let engine = AVAudioEngine()
    private var flashTimer: Timer?
    private var hasStarted = false

    private var smoothedLevel: Float = -80.0
    private var lastPeakUpdate = Date()
    private var lastSampleTime = Date()

    private let minDb: Float = -80.0
    private let maxDb: Float = 0.0
    private let displayOffsetDb: Float = 100.0
    private let peakHoldSeconds: TimeInterval = 1.5
    private let peakDecayPerSecond: Float = 12.0
    private let mutedFloorThresholdDb: Float = -79.5

    var readout: String {
        guard isRunning else { return "--.- dB" }
        guard !isEffectivelyMuted else { return "--.- dB" }
        return formatDecibels(displayedDecibelLevel, precision: 1)
    }

    var peakReadout: String {
        isRunning ? formatDecibels(displayedPeakLevel, precision: 1) : "--.- dB"
    }

    var menuBarTitle: String {
        guard isRunning else { return "-- dB" }
        guard !isEffectivelyMuted else { return "-- dB" }
        return formatDecibels(displayedDecibelLevel, precision: 0)
    }

    var isEffectivelyMuted: Bool {
        decibelLevel <= mutedFloorThresholdDb
    }

    var normalizedLevel: Double {
        let clamped = max(min(decibelLevel, maxDb), minDb)
        return Double((clamped - minDb) / abs(minDb))
    }

    var normalizedPeakLevel: Double {
        let clamped = max(min(peakLevel, maxDb), minDb)
        return Double((clamped - minDb) / abs(minDb))
    }

    var smoothingPercent: Int {
        Int((smoothing * 100).rounded())
    }

    var yellowThresholdReadout: String {
        formatDecibels(yellowThreshold, precision: 0)
    }

    var redThresholdReadout: String {
        formatDecibels(redThreshold, precision: 0)
    }

    var activeInputName: String {
        if selectedInputID == systemDefaultInputID {
            if let defaultID = Self.defaultInputDeviceID(), let name = Self.deviceName(deviceID: defaultID) {
                return "System Default (\(name))"
            }
            return "System Default"
        }

        if let selected = availableInputs.first(where: { $0.id == selectedInputID }) {
            return selected.name
        }

        return "Unknown"
    }

    var displayedDecibelLevel: Float {
        max(decibelLevel + displayOffsetDb, 0)
    }

    var displayedPeakLevel: Float {
        max(peakLevel + displayOffsetDb, 0)
    }

    var alertLevel: AlertLevel {
        if displayedDecibelLevel >= redThreshold {
            return .red
        }
        if displayedDecibelLevel >= yellowThreshold {
            return .yellow
        }
        return .none
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        startMonitoring()
    }

    func startMonitoring() {
        hasStarted = true
        selectedInputID = systemDefaultInputID
        refreshInputDevices()
        requestMicrophonePermissionAndStart()
    }

    func toggleRunning() {
        isRunning ? stopMetering() : startMetering()
    }

    func refreshInputDevices() {
        var devices: [AudioInputDevice] = [AudioInputDevice(id: systemDefaultInputID, name: "System default")]
        devices.append(contentsOf: Self.fetchInputDevices())
        availableInputs = devices

        let ids = Set(devices.map(\.id))
        if !ids.contains(selectedInputID) {
            selectedInputID = systemDefaultInputID
        }
    }

    func setSelectedInput(id: String) {
        guard selectedInputID != id else { return }
        selectedInputID = id

        guard isRunning else { return }
        restartMetering(reason: "Switching input device …")
    }

    func setYellowThreshold(_ value: Double) {
        setThresholdValue(&yellowThreshold, to: value, minValue: 40.0, maxValue: 110.0, otherThreshold: redThreshold, relationType: .lessThan)
    }

    func setRedThreshold(_ value: Double) {
        setThresholdValue(&redThreshold, to: value, minValue: 41.0, maxValue: 120.0, otherThreshold: yellowThreshold, relationType: .greaterThan)
    }

    private func requestMicrophonePermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMetering()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if granted {
                        self.startMetering()
                    } else {
                        self.statusText = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
                    }
                }
            }
        case .denied, .restricted:
            statusText = "Microphone access denied. Enable it in System Settings > Privacy & Security > Microphone."
        @unknown default:
            statusText = "Unable to access microphone permission state."
        }
    }

    private func startMetering() {
        guard !isRunning else { return }

        guard startEngineCapture() else {
            statusText = "Failed to start microphone capture."
            return
        }

        isRunning = true
        smoothedLevel = decibelLevel
        lastSampleTime = Date()
        lastPeakUpdate = Date()
        startFlashTimer()
        statusText = "Listening (\(activeInputName))"
    }

    private func stopMetering() {
        guard isRunning else { return }

        flashTimer?.invalidate()
        flashTimer = nil
        isFlashVisible = true

        stopEngineCapture()

        isRunning = false
        statusText = "Paused"
    }

    private func restartMetering(reason: String) {
        stopMetering()
        statusText = reason
        startMetering()
    }

    private func startEngineCapture() -> Bool {
        stopEngineCapture()
        engine.reset()

        guard applySelectedInputDeviceIfNeeded() else {
            return false
        }

        let inputNode = engine.inputNode
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        guard hardwareFormat.channelCount > 0, hardwareFormat.sampleRate > 0 else {
            return false
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let rawDb = Self.calculateDecibels(from: buffer)
            Task { @MainActor in
                self.processSample(rawDecibels: rawDb)
            }
        }

        do {
            engine.prepare()
            try engine.start()
            return true
        } catch {
            inputNode.removeTap(onBus: 0)
            return false
        }
    }

    private func stopEngineCapture() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func startFlashTimer() {
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.alertLevel == .none {
                    self.isFlashVisible = true
                } else {
                    self.isFlashVisible.toggle()
                }
            }
        }
    }

    private func applySelectedInputDeviceIfNeeded() -> Bool {
        guard let deviceID = selectedAudioDeviceID() else {
            return true
        }

        guard let audioUnit = engine.inputNode.audioUnit else {
            statusText = "Unable to access audio input unit."
            return false
        }

        var mutableDeviceID = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableDeviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            statusText = "Failed to select input device."
            return false
        }

        return true
    }

    private func selectedAudioDeviceID() -> AudioDeviceID? {
        if selectedInputID == systemDefaultInputID {
            return Self.defaultInputDeviceID()
        }
        return Self.deviceID(forUID: selectedInputID)
    }

    private static func fetchInputDevices() -> [AudioInputDevice] {
        guard let deviceIDs = getDeviceIDArray(selector: kAudioHardwarePropertyDevices) else { return [] }

        let mapped = deviceIDs.compactMap { deviceID -> AudioInputDevice? in
            guard hasInputChannels(deviceID: deviceID) else { return nil }
            guard let uid = getAudioProperty(deviceID, selector: kAudioDevicePropertyDeviceUID), !uid.isEmpty else { return nil }
            let name = getAudioProperty(deviceID, selector: kAudioObjectPropertyName) ?? "Unknown input"
            return AudioInputDevice(id: uid, name: name)
        }

        return mapped.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr else { return nil }
        return deviceID
    }

    private static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard let deviceIDs = getDeviceIDArray(selector: kAudioHardwarePropertyDevices) else { return nil }

        for deviceID in deviceIDs where hasInputChannels(deviceID: deviceID) {
            if getAudioProperty(deviceID, selector: kAudioDevicePropertyDeviceUID) as String? == uid {
                return deviceID
            }
        }
        return nil
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let bufferListPointer = raw.bindMemory(to: AudioBufferList.self, capacity: 1)

        var mutableDataSize = dataSize
        let readStatus = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &mutableDataSize, bufferListPointer)
        guard readStatus == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func deviceName(deviceID: AudioDeviceID) -> String? {
        getAudioProperty(deviceID, selector: kAudioObjectPropertyName)
    }

    private static func deviceUID(deviceID: AudioDeviceID) -> String? {
        getAudioProperty(deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private static func getAudioProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else { return nil }
        return value?.takeUnretainedValue() as String?
    }

    private static func getDeviceIDArray(selector: AudioObjectPropertySelector) -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr, dataSize > 0 else { return nil }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)

        let readStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )
        guard readStatus == noErr else { return nil }
        return deviceIDs
    }

    private func processSample(rawDecibels: Float) {
        let adjusted = max(min(rawDecibels, maxDb), minDb)

        let riseResponse = Float(max(0.02, min(0.35, 1.0 - smoothing)))
        let fallResponse = max(0.01, riseResponse * 0.55)
        let response = adjusted > smoothedLevel ? riseResponse : fallResponse

        smoothedLevel += (adjusted - smoothedLevel) * response
        decibelLevel = smoothedLevel

        let now = Date()
        let dt = max(Float(now.timeIntervalSince(lastSampleTime)), 0)
        lastSampleTime = now

        updatePeakLevel(now: now, timeDelta: dt)
    }

    private func updatePeakLevel(now: Date, timeDelta: Float) {
        if decibelLevel >= peakLevel {
            peakLevel = decibelLevel
            lastPeakUpdate = now
            return
        }

        if now.timeIntervalSince(lastPeakUpdate) > peakHoldSeconds {
            let decayedPeak = peakLevel - (peakDecayPerSecond * timeDelta)
            peakLevel = max(decibelLevel, decayedPeak)
        }
    }

    private func formatDecibels(_ value: Float, precision: Int) -> String {
        String(format: "%.*f dB", precision, value)
    }

    private enum ThresholdRelation {
        case lessThan
        case greaterThan
    }

    private func setThresholdValue(_ threshold: inout Float, to value: Double, minValue: Double, maxValue: Double, otherThreshold: Float, relationType: ThresholdRelation) {
        let clamped = Float(min(max(value, minValue), maxValue))
        switch relationType {
        case .lessThan:
            threshold = min(clamped, otherThreshold - 1)
        case .greaterThan:
            threshold = max(clamped, otherThreshold + 1)
        }
    }

    private static func calculateDecibels(from buffer: AVAudioPCMBuffer) -> Float {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0, let channelData = buffer.floatChannelData else { return -80.0 }

        let channelCount = max(Int(buffer.format.channelCount), 1)
        var sumSquares: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for index in 0..<frameLength {
                let s = samples[index]
                sumSquares += s * s
            }
        }

        let sampleCount = frameLength * channelCount
        guard sampleCount > 0 else { return -80.0 }

        let rms = sqrt(sumSquares / Float(sampleCount))
        return rms > 0 ? max(20 * log10(rms), -80.0) : -80.0
    }
}
