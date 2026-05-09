import AVFoundation
import CoreAudio
import CoreMedia
import Foundation

/// Captures microphone audio via `AVCaptureSession` pinned to the built-in
/// microphone, converts it to 16 kHz mono PCM16 on-the-fly, and returns a
/// valid WAV blob on `stop()`.
///
/// AVCaptureSession (not AVAudioEngine) is used on purpose: it lets us pick
/// the exact input device without touching the system-wide audio routing.
/// In particular, when the user has AirPods connected playing A2DP audio,
/// pinning to the built-in mic keeps the AirPods in A2DP mode — no
/// A2DP→HFP profile switch, no "ducking" of music/video playback.
final class AudioCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {

    enum AudioCaptureError: LocalizedError {
        case permissionDenied
        case noInputDevice
        case deviceInputFailed(String)
        case converterUnavailable
        case sessionConfigurationFailed

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "Microphone permission was denied. Enable it in System Settings → Privacy & Security → Microphone."
            case .noInputDevice:
                return "Blitz couldn't find an audio input device."
            case .deviceInputFailed(let reason):
                return "Could not open the microphone: \(reason)"
            case .converterUnavailable:
                return "Could not create the 16 kHz mono audio converter."
            case .sessionConfigurationFailed:
                return "Audio capture session could not be configured."
            }
        }
    }

    private static let targetSampleRate: Double = 16_000
    private static let targetChannels: AVAudioChannelCount = 1
    private static let bitsPerSample: UInt16 = 16

    private let session = AVCaptureSession()
    private let processingQueue = DispatchQueue(
        label: "com.elyasmirzazadeh.blitz.audio",
        qos: .userInteractive
    )

    private var currentInput: AVCaptureDeviceInput?
    private var currentOutput: AVCaptureAudioDataOutput?

    // Guarded by `lock`.
    private let lock = NSLock()
    private var pcmBuffer = Data()
    private var running = false
    private var sourceFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    override init() {
        super.init()
    }

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    func start() throws {
        lock.lock()
        if running { lock.unlock(); return }
        lock.unlock()

        try ensureMicrophonePermission()

        guard let device = Self.selectInputDevice() else {
            throw AudioCaptureError.noInputDevice
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw AudioCaptureError.deviceInputFailed(error.localizedDescription)
        }

        let output = AVCaptureAudioDataOutput()

        session.beginConfiguration()
        for oldInput in session.inputs { session.removeInput(oldInput) }
        for oldOutput in session.outputs { session.removeOutput(oldOutput) }

        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AudioCaptureError.sessionConfigurationFailed
        }
        session.addInput(input)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AudioCaptureError.sessionConfigurationFailed
        }
        session.addOutput(output)
        session.commitConfiguration()

        output.setSampleBufferDelegate(self, queue: processingQueue)

        lock.lock()
        pcmBuffer.removeAll(keepingCapacity: false)
        sourceFormat = nil
        converter = nil
        currentInput = input
        currentOutput = output
        running = true
        lock.unlock()

        session.startRunning()
    }

    func stop() -> Data {
        lock.lock()
        let wasRunning = running
        running = false
        let input = currentInput
        let output = currentOutput
        lock.unlock()

        if wasRunning {
            session.stopRunning()
            session.beginConfiguration()
            if let input { session.removeInput(input) }
            if let output { session.removeOutput(output) }
            session.commitConfiguration()
        }

        // Drain any in-flight delegate callbacks.
        processingQueue.sync {}

        lock.lock()
        let samples = pcmBuffer
        pcmBuffer.removeAll(keepingCapacity: false)
        sourceFormat = nil
        converter = nil
        currentInput = nil
        currentOutput = nil
        lock.unlock()

        guard !samples.isEmpty else { return Data() }
        return wavEncode(pcm16LE: samples,
                         sampleRate: UInt32(Self.targetSampleRate),
                         channels: UInt16(Self.targetChannels),
                         bitsPerSample: Self.bitsPerSample)
    }

    // MARK: - Device selection

    private static func selectInputDevice() -> AVCaptureDevice? {
        // 1) Find the built-in input device via CoreAudio HAL (authoritative).
        //    Match it back to AVCaptureDevice by CoreAudio UID.
        if let uid = builtInDeviceUID(),
           let match = AVCaptureDevice(uniqueID: uid) {
            return match
        }

        // 2) Fallback: look for a mic whose name identifies it as internal.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        let hints = ["built-in", "macbook", "internal", "imac", "mac mini", "mac studio"]
        if let byName = discovery.devices.first(where: { dev in
            let n = dev.localizedName.lowercased()
            return hints.contains { n.contains($0) }
        }) {
            return byName
        }

        // 3) Last resort: whichever default the system provides.
        if let any = discovery.devices.first { return any }
        return AVCaptureDevice.default(for: .audio)
    }

    /// CoreAudio UID of the first built-in input device, or nil.
    private static func builtInDeviceUID() -> String? {
        var listAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let systemObj = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObj, &listAddr, 0, nil, &size) == noErr,
              size > 0
        else { return nil }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var devices = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(systemObj, &listAddr, 0, nil, &size, &devices) == noErr
        else { return nil }

        for device in devices {
            guard deviceHasInputStreams(device) else { continue }
            guard deviceTransportType(device) == kAudioDeviceTransportTypeBuiltIn else { continue }
            if let uid = deviceUID(device) { return uid }
        }
        return nil
    }

    private static func deviceHasInputStreams(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func deviceTransportType(_ device: AudioDeviceID) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr
        else { return nil }
        return transport
    }

    private static func deviceUID(_ device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &uid)
        guard status == noErr, let cf = uid?.takeRetainedValue() else { return nil }
        return cf as String
    }

    // MARK: - Permission

    private func ensureMicrophonePermission() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw AudioCaptureError.permissionDenied
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                granted = ok
                sem.signal()
            }
            sem.wait()
            if !granted { throw AudioCaptureError.permissionDenied }
        @unknown default:
            throw AudioCaptureError.permissionDenied
        }
    }

    // MARK: - Sample buffer delegate

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else { return }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }

        let asbd = asbdPtr.pointee

        // Re-use or build a source AVAudioFormat + converter to 16 kHz mono Int16.
        guard let (srcFormat, conv) = ensureConverter(for: asbd) else { return }

        guard let srcBuffer = AVAudioPCMBuffer(
            pcmFormat: srcFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else { return }
        srcBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy raw PCM data from the CMSampleBuffer into the AVAudioPCMBuffer.
        var ablSize: Int = 0
        var blockBuffer: CMBlockBuffer?
        let listStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &ablSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard listStatus == noErr, ablSize > 0 else { return }

        let listPtr = UnsafeMutableRawPointer.allocate(
            byteCount: ablSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { listPtr.deallocate() }
        let typedList = listPtr.bindMemory(to: AudioBufferList.self, capacity: 1)

        let fillStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: typedList,
            bufferListSize: ablSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard fillStatus == noErr else { return }

        // Copy AudioBufferList → AVAudioPCMBuffer's backing storage.
        let destABLPtr = srcBuffer.mutableAudioBufferList
        let srcBuffers = UnsafeMutableAudioBufferListPointer(typedList)
        let destBuffers = UnsafeMutableAudioBufferListPointer(destABLPtr)
        let n = min(srcBuffers.count, destBuffers.count)
        for i in 0..<n {
            let src = srcBuffers[i]
            let bytes = min(src.mDataByteSize, destBuffers[i].mDataByteSize)
            if let srcData = src.mData, let dstData = destBuffers[i].mData, bytes > 0 {
                memcpy(dstData, srcData, Int(bytes))
                destBuffers[i].mDataByteSize = bytes
            }
        }

        // Estimate output capacity based on sample-rate ratio + headroom.
        let inRate = srcFormat.sampleRate
        guard inRate > 0 else { return }
        let ratio = Self.targetSampleRate / inRate
        let estimated = Double(frameCount) * ratio
        let cap = AVAudioFrameCount(max(1024.0, estimated.rounded(.up) + 1024.0))

        guard let targetFormat = conv.outputFormat as AVAudioFormat?,
              let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: cap)
        else { return }

        let box = InputBox(buffer: srcBuffer)
        var convError: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if box.supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            box.supplied = true
            outStatus.pointee = .haveData
            return box.buffer
        }

        let status = conv.convert(to: outBuffer, error: &convError, withInputFrom: inputBlock)
        guard status != .error, convError == nil else { return }

        appendInt16(outBuffer)
    }

    private final class InputBox {
        let buffer: AVAudioPCMBuffer
        var supplied = false
        init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    }

    private func ensureConverter(for asbd: AudioStreamBasicDescription) -> (AVAudioFormat, AVAudioConverter)? {
        lock.lock()
        if let srcFormat = sourceFormat,
           let conv = converter,
           srcFormat.streamDescription.pointee.mSampleRate == asbd.mSampleRate,
           srcFormat.streamDescription.pointee.mChannelsPerFrame == asbd.mChannelsPerFrame {
            lock.unlock()
            return (srcFormat, conv)
        }
        lock.unlock()

        var mutableASBD = asbd
        guard let newSrc = AVAudioFormat(streamDescription: &mutableASBD) else { return nil }
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.targetSampleRate,
            channels: Self.targetChannels,
            interleaved: true
        ) else { return nil }
        guard let conv = AVAudioConverter(from: newSrc, to: target) else { return nil }

        lock.lock()
        sourceFormat = newSrc
        converter = conv
        lock.unlock()
        return (newSrc, conv)
    }

    private func appendInt16(_ outBuffer: AVAudioPCMBuffer) {
        guard outBuffer.frameLength > 0 else { return }
        guard let int16Ptr = outBuffer.int16ChannelData else { return }

        let frames = Int(outBuffer.frameLength)
        let channels = Int(outBuffer.format.channelCount)
        let interleaved = outBuffer.format.isInterleaved
        let sampleCount = frames * channels
        let byteCount = sampleCount * MemoryLayout<Int16>.size

        var chunk = Data(count: byteCount)
        chunk.withUnsafeMutableBytes { rawDst in
            guard let dst = rawDst.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            if interleaved {
                dst.update(from: int16Ptr[0], count: sampleCount)
            } else {
                for frame in 0..<frames {
                    for ch in 0..<channels {
                        dst[frame * channels + ch] = int16Ptr[ch][frame]
                    }
                }
            }
        }

        lock.lock()
        pcmBuffer.append(chunk)
        lock.unlock()
    }

    // MARK: - WAV encoder

    private func wavEncode(pcm16LE: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate: UInt32 = sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let subchunk2Size: UInt32 = UInt32(pcm16LE.count)
        let chunkSize: UInt32 = 36 + subchunk2Size

        var header = Data(capacity: 44)
        header.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        header.appendUInt32LE(chunkSize)
        header.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        header.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        header.appendUInt32LE(16)                            // PCM fmt chunk size
        header.appendUInt16LE(1)                             // PCM
        header.appendUInt16LE(channels)
        header.appendUInt32LE(sampleRate)
        header.appendUInt32LE(byteRate)
        header.appendUInt16LE(blockAlign)
        header.appendUInt16LE(bitsPerSample)
        header.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        header.appendUInt32LE(subchunk2Size)

        var out = Data(capacity: header.count + pcm16LE.count)
        out.append(header)
        out.append(pcm16LE)
        return out
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { self.append(contentsOf: $0) }
    }
}
