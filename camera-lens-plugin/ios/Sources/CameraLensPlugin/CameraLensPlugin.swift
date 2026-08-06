import Foundation
import Capacitor
import AVFoundation
import UIKit

@objc(CameraLensPlugin)
public class CameraLensPlugin: CAPPlugin, CAPBridgedPlugin, AVCaptureVideoDataOutputSampleBufferDelegate {
    public let identifier = "CameraLensPlugin" 
    public let jsName = "CameraLensPlugin" 
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "deviceAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configureLens", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSession", returnType: CAPPluginReturnPromise)
    ]
    
    // Capture Session Objects
    private let captureSession = AVCaptureSession()
    private var activeDevice: AVCaptureDevice?
    private var activeInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    // Dispatch Queues to avoid locking the UI thread
    private let sessionQueue = DispatchQueue(label: "com.cameralens.sessionQueue")
    private let frameProcessingQueue = DispatchQueue(label: "com.cameralens.frameQueue", qos: .userInitiated)

    // MARK: - Legacy / Test Action
    @objc func deviceAction(_ call: CAPPluginCall) {
        let inputMessage = call.getString("message") ?? "No message provided"
        call.resolve(["value": "Native iOS received: \(inputMessage)"])
    }
    
    // MARK: - Phase 1: Camera Session Lifecycle

    @objc func startSession(_ call: CAPPluginCall) {
        let presetString = call.getString("preset") ?? "hd1920x1080"
        let lensType = call.getString("lensType") ?? "Wide"
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                call.resolve(["status": "already_running"])
                return
            }

            self.captureSession.beginConfiguration()

            // 1. Set Resolution Preset
            let preset = self.getCapturePreset(from: presetString)
            if self.captureSession.canSetSessionPreset(preset) {
                self.captureSession.sessionPreset = preset
            }

            // 2. Select Device Lens Hardware
            guard let device = self.getDevice(for: lensType) else {
                self.captureSession.commitConfiguration()
                call.reject("Failed to find camera device for lens: \(lensType)")
                return
            }
            self.activeDevice = device

            // 3. Attach Input Device
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

            // 4. Attach Video Frame Data Output
            let output = AVCaptureVideoDataOutput()
            // Drop frames automatically if processing pipeline backs up
            output.alwaysDiscardsLateVideoFrames = true
            // YUV 420 format is optimized for VideoToolbox H.264 encoding in Phase 2
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

            // 5. Setup Local Viewfinder Preview Layer on Main Thread
            DispatchQueue.main.async {
                self.setupPreviewLayer()
            }

            // 6. Start Capture Session
            self.captureSession.startRunning()
            call.resolve(["status": "started", "preset": presetString, "lens": lensType])
        }
    }

    @objc func stopSession(_ call: CAPPluginCall) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()

                // Cleanup inputs/outputs
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

    // MARK: - Dynamic Lens and Manual Controls Configuration

    @objc func configureLens(_ call: CAPPluginCall) {
        let iso = call.getFloat("iso")
        let shutter = call.getFloat("shutter")
        let zoom = call.getFloat("zoom")
        let lensType = call.getString("lensType")

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // Handle lens switch if requested lens differs from active device
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
            
                // Apply ISO and Shutter Speed
                if let targetISO = iso, let targetShutter = shutter {
                    let clampedISO = min(max(targetISO, device.activeFormat.minISO), device.activeFormat.maxISO)
                    let duration = CMTime(seconds: Double(targetShutter), preferredTimescale: 1000000)
                    let clampedDuration = max(min(duration, device.activeFormat.maxExposureDuration), device.activeFormat.minExposureDuration)
            
                    device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
                }

                // Apply Zoom
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

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Core video buffer capture callback running on frameProcessingQueue
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // --- PHASE 1 PLACEHOLDER ---
        // Raw CMSampleBuffer is captured here in real-time.
        // In Phase 2, this CMSampleBuffer will be passed directly into VTCompressionSession (H.264 Encoder).
    }

    // MARK: - Helper Methods

    private func setupPreviewLayer() {
        guard let webView = self.bridge?.webView else { return }

        // Remove previous layer if existing
        previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = webView.bounds

        // Insert the native camera preview beneath the Capacitor WebView
        webView.superview?.layer.insertSublayer(layer, below: webView.layer)
        // Ensure webview background is transparent so preview layer shows through
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