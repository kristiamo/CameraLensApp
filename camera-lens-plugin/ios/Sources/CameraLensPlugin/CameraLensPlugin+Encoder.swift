import Foundation
import Capacitor
import AVFoundation
import VideoToolbox

extension CameraLensPlugin {

    // MARK: - Capacitor Bridge Actions

    @objc func setEncoderSettings(_ call: CAPPluginCall) {
        let bitrate = call.getInt("bitrate") ?? Int(self.targetBitrate)
        let fps = call.getInt("fps") ?? Int(self.targetFPS)
        let gop = call.getInt("gop") ?? Int(self.maxKeyFrameInterval)

        applyEncoderSettings(bitrate: bitrate, fps: fps, gop: gop)
        call.resolve(["status": "updated", "bitrate": bitrate, "fps": fps, "gop": gop])
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
    
    internal func applyEncoderSettings(bitrate: Int, fps: Int, gop: Int) {
        frameProcessingQueue.async { [weak self] in
            guard let self = self else { return }
            self.targetBitrate = Int32(bitrate)
            self.targetFPS = Int32(fps)
            self.maxKeyFrameInterval = Int32(gop)
            
            self.teardownEncoder()
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

    // MARK: - VideoToolbox Core

    internal func setupEncoder(width: Int32, height: Int32) {
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

    internal func teardownEncoder() {
        if let session = compressionSession {
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
        currentEncoderWidth = 0
        currentEncoderHeight = 0
    }

    internal func processEncodedFrame(sampleBuffer: CMSampleBuffer) {
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
}