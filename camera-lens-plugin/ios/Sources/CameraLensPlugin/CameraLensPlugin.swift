import Foundation
import Capacitor
import AVFoundation
import VideoToolbox
import UIKit

// Frame delegate interface for Phase 3 (WebSocket sender)
public protocol H264EncoderDelegate: AnyObject {
    func didEncodeH264Frame(naluData: Data, isKeyFrame: Bool, timestamp: Double)
}

@objc(CameraLensPlugin)
public class CameraLensPlugin: CAPPlugin, CAPBridgedPlugin, AVCaptureVideoDataOutputSampleBufferDelegate {
    public let identifier = "CameraLensPlugin" 
    public let jsName = "CameraLensPlugin" 
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "deviceAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configureLens", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEncoderSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getEncoderStats", returnType: CAPPluginReturnPromise)
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

    // Dispatch Queues
    private let sessionQueue = DispatchQueue(label: "com.cameralens.sessionQueue")
    private let frameProcessingQueue = DispatchQueue(label: "com.cameralens.frameQueue", qos: .userInitiated)

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

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            if let targetLens = lensType, let currentDev = self.activeDevice {
                let targetDevType = self.getDeviceType(from: targetLens)
                if currentDev.deviceType != targetDevType {
                    self.switchLensHardware(to: targetLens)
                }
            }

            guard let device = self.activeDevice else {
                call.reject("No active camera device available")
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
                call.resolve(["status": "success"])
        } catch {
                call.reject("Failed to lock device configuration: \(error.localizedDescription)")
            }
        }
    }

    @objc func setEncoderSettings(_ call: CAPPluginCall) {
        let bitrate = call.getInt("bitrate") ?? Int(self.targetBitrate)
        let fps = call.getInt("fps") ?? Int(self.targetFPS)
        let gop = call.getInt("gop") ?? Int(self.maxKeyFrameInterval)

        frameProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.targetBitrate = Int32(bitrate)
            self.targetFPS = Int32(fps)
            self.maxKeyFrameInterval = Int32(gop)
            
            // Forces encoder recreation on the next frame with new parameters
            self.teardownEncoder()
            call.resolve(["status": "updated", "bitrate": bitrate, "fps": fps, "gop": gop])
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

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
        let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

        // Initialize or re-create encoder if dimensions changed
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
            sourceFrameRefCon: nil,
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

        // Configure Low Latency / Real-Time Encoding Settings
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse) // No B-Frames for real-time latency
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

    // Convert AVCC format buffers to Annex-B Elementary Stream format with 0x00 0x00 0x00 0x01 start codes
    private func processEncodedFrame(sampleBuffer: CMSampleBuffer) {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        let isKeyFrame: Bool = {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
                  let first = attachments.first else { return true }
            return !(first[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        }()

        var naluPayload = Data()
        let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]

        // On IDR Keyframes, extract and prepend SPS and PPS parameter sets
        if isKeyFrame {
            if let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
                var spsSize: Int = 0
                var spsCount: Int = 0
                var spsPointer: UnsafePointer<UInt8>?
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, index: 0, parameterSetPointerOut: &spsPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, naluHeaderSizeOut: nil) == noErr, let sps = spsPointer {
                    naluPayload.append(contentsOf: startCode)
                    naluPayload.append(sps, count: spsSize)
                }

                var ppsSize: Int = 0
                var ppsCount: Int = 0
                var ppsPointer: UnsafePointer<UInt8>?
                if CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDesc, index: 1, parameterSetPointerOut: &ppsPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, naluHeaderSizeOut: nil) == noErr, let pps = ppsPointer {
                    naluPayload.append(contentsOf: startCode)
                    naluPayload.append(pps, count: ppsSize)
                }
            }
            keyFrameCount += 1
        }

        // Extract slice NAL units from CMBlockBuffer (AVCC format) and convert to Annex-B
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        if CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer) == noErr, let ptr = dataPointer {
            var bufferOffset = 0
            let avccHeaderLength = 4 // 4-byte length prefix

            while bufferOffset < totalLength - avccHeaderLength {
                var naluLength: UInt32 = 0
                memcpy(&naluLength, ptr + bufferOffset, avccHeaderLength)
                naluLength = CFSwapInt32BigToHost(naluLength) // Big endian conversion

                naluPayload.append(contentsOf: startCode)
                naluPayload.append(UnsafeRawPointer(ptr + bufferOffset + avccHeaderLength).assumingMemoryBound(to: UInt8.self), count: Int(naluLength))

                bufferOffset += avccHeaderLength + Int(naluLength)
            }
        }

        encodedFrameCount += 1
        lastEncodedFrameBytes = naluPayload.count
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // Forward encoded Annex-B frame to Phase 3 delegate (WebSocket client)
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