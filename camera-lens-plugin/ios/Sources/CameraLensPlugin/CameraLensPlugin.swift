import Foundation
import Capacitor
import AVFoundation
import VideoToolbox
import UIKit

// Frame delegate interface for H.264 video pipeline
public protocol H264EncoderDelegate: AnyObject {
    func didEncodeH264Frame(naluData: Data, isKeyFrame: Bool, timestamp: Double)
}

@objc(CameraLensPlugin)
public class CameraLensPlugin: CAPPlugin, CAPBridgedPlugin, AVCaptureVideoDataOutputSampleBufferDelegate, H264EncoderDelegate, URLSessionWebSocketDelegate {
    public let identifier = "CameraLensPlugin" 
    public let jsName = "CameraLensPlugin" 
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "deviceAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configureLens", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEncoderSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getEncoderStats", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "connectWebSocket", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnectWebSocket", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getWebSocketStatus", returnType: CAPPluginReturnPromise)
    ]
    
    // Capture Session Objects
    private let captureSession = AVCaptureSession()
    private var activeDevice: AVCaptureDevice?
    private var activeInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // VideoToolbox Encoder Objects
    private var compressionSession: VTCompressionSession?
    private var currentEncoderWidth: Int32 = 0
    private var currentEncoderHeight: Int32 = 0
    private var targetBitrate: Int32 = 4_000_000 // Default 4 Mbps
    private var targetFPS: Int32 = 30
    private var maxKeyFrameInterval: Int32 = 30 // Keyframe every 1s at 30fps

    // Encoder Statistics & Delegates
    public weak var encoderDelegate: H264EncoderDelegate?
    private var encodedFrameCount: Int64 = 0
    private var keyFrameCount: Int64 = 0
    private var lastEncodedFrameBytes: Int = 0

    // Networking (WebSocket) State
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isWsConnected = false
    private var serverAddress: String = ""

    // Dispatch Queues
    private let sessionQueue = DispatchQueue(label: "com.cameralens.sessionQueue")
    private let frameProcessingQueue = DispatchQueue(label: "com.cameralens.frameQueue", qos: .userInitiated)
    private let wsQueue = DispatchQueue(label: "com.cameralens.wsQueue", qos: .userInitiated)

    override public func load() {
        super.load()
        self.encoderDelegate = self
    }

    // MARK: - Legacy / Test Action
    @objc func deviceAction(_ call: CAPPluginCall) {
        let inputMessage = call.getString("message") ?? "No message provided"
        call.resolve(["value": "Native iOS received: \(inputMessage)"])
    }
    
    // MARK: - Session Lifecycle

    @objc func startSession(_ call: CAPPluginCall) {
        let presetString = call.getString("preset") ?? "hd1920x1080"
        let lensType = call.getString("lensType") ?? "Wide"
        
        if let bitrate = call.getInt("bitrate") { self.targetBitrate = Int32(bitrate) }
        if let fps = call.getInt("fps") { self.targetFPS = Int32(fps) }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                call.resolve(["status": "already_running"])
                return
            }

            self.captureSession.beginConfiguration()

            let preset = self.getCapturePreset(from: presetString)
            if self.captureSession.canSetSessionPreset(preset) {
                self.captureSession.sessionPreset = preset
            }

            guard let device = self.getDevice(for: lensType) else {
                self.captureSession.commitConfiguration()
                call.reject("Failed to find camera device for lens: \(lensType)")
                return
            }
            self.activeDevice = device

            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.activeInput = input
                } else {
                    self.captureSession.commitConfiguration()
                    call.reject("Cannot add input to capture session")
                    return
                }
            } catch {
                self.captureSession.commitConfiguration()
                call.reject("Error creating input device: \(error.localizedDescription)")
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
            
            output.setSampleBufferDelegate(self, queue: self.frameProcessingQueue)

            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
                self.videoOutput = output
            } else {
                self.captureSession.commitConfiguration()
                call.reject("Cannot add video data output to session")
                return
            }

            self.captureSession.commitConfiguration()

            DispatchQueue.main.async {
                self.setupPreviewLayer()
            }

            self.captureSession.startRunning()
            call.resolve(["status": "started", "preset": presetString, "lens": lensType])
        }
    }

    @objc func stopSession(_ call: CAPPluginCall) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()

                self.captureSession.beginConfiguration()
                if let input = self.activeInput {
                    self.captureSession.removeInput(input)
                }
                if let output = self.videoOutput {
                    self.captureSession.removeOutput(output)
                }
                self.captureSession.commitConfiguration()

                self.activeDevice = nil
                self.activeInput = nil
                self.videoOutput = nil

                self.teardownEncoder()

                DispatchQueue.main.async {
                    self.previewLayer?.removeFromSuperlayer()
                    self.previewLayer = nil
                }

                call.resolve(["status": "stopped"])
            } else {
                call.resolve(["status": "not_running"])
            }
        }
    }

    // MARK: - Hardware & Encoder Configurations

    @objc func configureLens(_ call: CAPPluginCall) {
        let iso = call.getFloat("iso")
        let shutter = call.getFloat("shutter")
        let zoom = call.getFloat("zoom")
        let lensType = call.getString("lensType")

        applyLensConfiguration(iso: iso, shutter: shutter, zoom: zoom, lensType: lensType) { error in
            if let err = error {
                call.reject(err)
            } else {
                call.resolve(["status": "success"])
            }
        }
    }

    private func applyLensConfiguration(iso: Float?, shutter: Float?, zoom: Float?, lensType: String?, completion: @escaping (String?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else {
                completion("Plugin instance unavailable")
                return
            }

            if let targetLens = lensType, let currentDev = self.activeDevice {
                let targetDevType = self.getDeviceType(from: targetLens)
                if currentDev.deviceType != targetDevType {
                    self.switchLensHardware(to: targetLens)
                }
            }

            guard let device = self.activeDevice else {
                completion("No active camera device available")
            return
        }
        
        do {
            try device.lockForConfiguration()
            
                if let targetISO = iso, let targetShutter = shutter {
                    let clampedISO = min(max(targetISO, device.activeFormat.minISO), device.activeFormat.maxISO)
                    let duration = CMTime(seconds: Double(targetShutter), preferredTimescale: 1000000)
                    let clampedDuration = max(min(duration, device.activeFormat.maxExposureDuration), device.activeFormat.minExposureDuration)
            
                    device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
                }

                if let targetZoom = zoom {
                    let clampedZoom = min(max(CGFloat(targetZoom), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                    device.videoZoomFactor = clampedZoom
            }
            
            device.unlockForConfiguration()
                completion(nil)
        } catch {
                completion("Failed to lock device configuration: \(error.localizedDescription)")
            }
        }
    }

    @objc func setEncoderSettings(_ call: CAPPluginCall) {
        let bitrate = call.getInt("bitrate") ?? Int(self.targetBitrate)
        let fps = call.getInt("fps") ?? Int(self.targetFPS)
        let gop = call.getInt("gop") ?? Int(self.maxKeyFrameInterval)

        applyEncoderSettings(bitrate: bitrate, fps: fps, gop: gop)
        call.resolve(["status": "updated", "bitrate": bitrate, "fps": fps, "gop": gop])
    }

    private func applyEncoderSettings(bitrate: Int, fps: Int, gop: Int) {
        frameProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.targetBitrate = Int32(bitrate)
            self.targetFPS = Int32(fps)
            self.maxKeyFrameInterval = Int32(gop)
            
            self.teardownEncoder()
        }
    }

    @objc func getEncoderStats(_ call: CAPPluginCall) {
        frameProcessingQueue.async { [weak self] in
            guard let self = self else {
                call.reject("Plugin unavailable")
                return
            }
            call.resolve([
                "encodedFrames": self.encodedFrameCount,
                "keyFrames": self.keyFrameCount,
                "lastFrameBytes": self.lastEncodedFrameBytes,
                "bitrate": self.targetBitrate,
                "fps": self.targetFPS
            ])
        }
    }

    // MARK: - Native WebSocket Management (Phase 3)

    @objc func connectWebSocket(_ call: CAPPluginCall) {
        guard let ip = call.getString("ip"), !ip.isEmpty else {
            call.reject("IP address is required")
            return
        }
        let port = call.getInt("port") ?? 8080
        let urlString = "ws://\(ip):\(port)"

        guard let url = URL(string: urlString) else {
            call.reject("Invalid WebSocket URL: \(urlString)")
            return
        }

        wsQueue.async { [weak self] in
            guard let self = self else { return }

            self.disconnectInternal()

            self.serverAddress = urlString
            let configuration = URLSessionConfiguration.default
            self.urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
            self.webSocketTask = self.urlSession?.webSocketTask(with: url)
            self.webSocketTask?.resume()

            self.isWsConnected = true
            self.listenWebSocketMessages()

            call.resolve(["status": "connected", "url": urlString])
        }
    }

    @objc func disconnectWebSocket(_ call: CAPPluginCall) {
        wsQueue.async { [weak self] in
            self?.disconnectInternal()
            call.resolve(["status": "disconnected"])
        }
    }

    @objc func getWebSocketStatus(_ call: CAPPluginCall) {
        wsQueue.async { [weak self] in
            guard let self = self else { return }
            call.resolve([
                "connected": self.isWsConnected,
                "server": self.serverAddress
            ])
        }
    }

    private func disconnectInternal() {
        if isWsConnected {
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
            urlSession?.invalidateAndCancel()
            urlSession = nil
            isWsConnected = false
            serverAddress = ""
        }
    }

    private func listenWebSocketMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self, self.isWsConnected else { return }

            switch result {
            case .failure(let error):
                print("[WebSocket] Receive Error: \(error.localizedDescription)")
                self.wsQueue.async {
                    self.disconnectInternal()
                }
            case .success(let message):
                switch message {
                case .string(let text):
                    self.handleInboundControlMessage(text)
                case .data(_):
                    break
                @unknown default:
                    break
                }
                // Recursively listen for next inbound message
                self.listenWebSocketMessages()
            }
        }
    }

    private func handleInboundControlMessage(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return
        }

        if action == "configureLens" {
            let iso = (json["iso"] as? NSNumber)?.floatValue
            let shutter = (json["shutter"] as? NSNumber)?.floatValue
            let zoom = (json["zoom"] as? NSNumber)?.floatValue
            let lensType = json["lensType"] as? String

            applyLensConfiguration(iso: iso, shutter: shutter, zoom: zoom, lensType: lensType) { [weak self] error in
                if error == nil {
                    var payload: [String: Any] = [:]
                    if let iso = iso { payload["iso"] = iso }
                    if let shutter = shutter { payload["shutter"] = shutter }
                    if let zoom = zoom { payload["zoom"] = zoom }
                    if let lensType = lensType { payload["lensType"] = lensType }
                    self?.notifyListeners("remoteCameraConfig", data: payload)
                }
            }
        } else if action == "setEncoderSettings" {
            let bitrate = json["bitrate"] as? Int ?? Int(self.targetBitrate)
            let fps = json["fps"] as? Int ?? Int(self.targetFPS)
            let gop = json["gop"] as? Int ?? Int(self.maxKeyFrameInterval)

            applyEncoderSettings(bitrate: bitrate, fps: fps, gop: gop)
            
            let payload: [String: Any] = ["bitrate": bitrate, "fps": fps, "gop": gop]
            self.notifyListeners("remoteEncoderConfig", data: payload)
        }
    }

    // MARK: - H264EncoderDelegate Interface (Phase 3 Networking Output)

    public func didEncodeH264Frame(naluData: Data, isKeyFrame: Bool, timestamp: Double) {
        guard isWsConnected, let ws = webSocketTask else { return }

        // Packet Structure (Header: 9 bytes):
        // [Byte 0: Flags (0x01 if keyframe, 0x00 if P-frame)]
        // [Bytes 1..8: Timestamp (UInt64 big endian milliseconds)]
        // [Bytes 9..N: Annex-B NALU Data]
        var packet = Data(capacity: 9 + naluData.count)
        var flags: UInt8 = isKeyFrame ? 0x01 : 0x00
        let timeMs = UInt64(timestamp * 1000)
        var bigEndianTime = timeMs.bigEndian

        packet.append(&flags, count: 1)
        withUnsafeBytes(of: &bigEndianTime) { packet.append(contentsOf: $0) }
        packet.append(naluData)

        ws.send(.data(packet)) { error in
            if let error = error {
                print("[WebSocket] Frame delivery error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

        if compressionSession == nil || currentEncoderWidth != width || currentEncoderHeight != height {
            setupEncoder(width: width, height: height)
        }

        guard let session = compressionSession else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)

        var flags: VTEncodeInfoFlags = []
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: duration,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
    }

    // MARK: - VideoToolbox Encoder Core

    private func setupEncoder(width: Int32, height: Int32) {
        teardownEncoder()

        currentEncoderWidth = width
        currentEncoderHeight = height

        let callback: VTCompressionOutputCallback = { refcon, sourceFrameRefCon, status, flags, sampleBuffer in
            guard status == noErr, let sampleBuffer = sampleBuffer, let refcon = refcon else { return }
            let plugin = Unmanaged<CameraLensPlugin>.fromOpaque(refcon).takeUnretainedValue()
            plugin.processEncodedFrame(sampleBuffer: sampleBuffer)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: width,
            height: height,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: callback,
            refcon: refcon,
            compressionSessionOut: &compressionSession
        )

        guard status == noErr, let session = compressionSession else {
            print("VideoToolbox: Session creation failed with status: \(status)")
            return
        }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: targetBitrate as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: targetFPS as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: maxKeyFrameInterval as CFNumber)

        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    private func teardownEncoder() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        currentEncoderWidth = 0
        currentEncoderHeight = 0
    }

    private func processEncodedFrame(sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let isKeyFrame: Bool = {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
                  let first = attachments.first else { return true }
            return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        }()

        var naluPayload = Data()
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

        if isKeyFrame {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var spsSize: Int = 0
                var spsCount: Int = 0
                var spsPointer: UnsafePointer<UInt8>?
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: nil) == noErr, let sps = spsPointer {
                    naluPayload.append(contentsOf: startCode)
                    naluPayload.append(sps, count: spsSize)
                }

                var ppsSize: Int = 0
                var ppsCount: Int = 0
                var ppsPointer: UnsafePointer<UInt8>?
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, parameterSetIndex: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: nil) == noErr, let pps = ppsPointer {
                    naluPayload.append(contentsOf: startCode)
                    naluPayload.append(pps, count: ppsSize)
                }
            }
            keyFrameCount += 1
        }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        if CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr, let ptr = dataPointer {
            var bufferOffset = 0
            let avccHeaderLength = 4

            while bufferOffset < totalLength - avccHeaderLength {
                var naluLength: UInt32 = 0
                memcpy(&naluLength, ptr + bufferOffset, avccHeaderLength)
                naluLength = CFSwapInt32BigToHost(naluLength)

                naluPayload.append(contentsOf: startCode)
                naluPayload.append(UnsafeRawPointer(ptr + bufferOffset + avccHeaderLength).assumingMemoryBound(to: UInt8.self), count: Int(naluLength))

                bufferOffset += avccHeaderLength + Int(naluLength)
            }
        }

        encodedFrameCount += 1
        lastEncodedFrameBytes = naluPayload.count
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        encoderDelegate?.didEncodeH264Frame(naluData: naluPayload, isKeyFrame: isKeyFrame, timestamp: pts)
    }

    // MARK: - Internal Helpers

    private func setupPreviewLayer() {
        guard let webView = self.bridge?.webView, let superview = webView.superview else {
            print("[CameraLensPlugin] WebView or Superview is nil")
            return
        }
    
        self.previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = webView.bounds

        superview.layer.insertSublayer(layer, below: webView.layer)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        self.previewLayer = layer
    }

    private func switchLensHardware(to lensType: String) {
        guard let newDevice = getDevice(for: lensType) else { return }

        captureSession.beginConfiguration()

        if let currentInput = activeInput {
            captureSession.removeInput(currentInput)
        }

        do {
            let newInput = try AVCaptureDeviceInput(device: newDevice)
            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                activeInput = newInput
                activeDevice = newDevice
            }
        } catch {
            print("Failed switching hardware lens: \(error)")
        }

        captureSession.commitConfiguration()
    }

    private func getDevice(for lensType: String) -> AVCaptureDevice? {
        let deviceType = getDeviceType(from: lensType)
        return AVCaptureDevice.default(deviceType, for: .video, position: .back)
    }

    private func getDeviceType(from lensType: String) -> AVCaptureDevice.DeviceType {
        switch lensType {
        case "UltraWide":
            return .builtInUltraWideCamera
        case "Telephoto":
            return .builtInTelephotoCamera
        default:
            return .builtInWideAngleCamera
        }
    }

    private func getCapturePreset(from presetString: String) -> AVCaptureSession.Preset {
        switch presetString {
        case "hd1280x720":
            return .hd1280x720
        case "hd4K3840x2160":
            return .hd4K3840x2160
        default:
            return .hd1920x1080
        }
    }
}