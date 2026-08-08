import Foundation
import Capacitor
import AVFoundation
import UIKit

extension CameraLensPlugin {
    
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
                
                // Configure native video output orientation
                if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
                    connection.videoOrientation = self.getCurrentVideoOrientation()
                }
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

    // MARK: - Device Capabilities Query

    @objc func getDeviceCapabilities(_ call: CAPPluginCall) {
        sessionQueue.async { [weak self] in
            guard let self = self, let device = self.activeDevice else {
                call.reject("No active camera device available")
                return
            }

            let minISO = Float(device.activeFormat.minISO)
            let maxISO = Float(device.activeFormat.maxISO)
            let minShutter = Float(device.activeFormat.minExposureDuration.seconds)
            let maxShutter = Float(device.activeFormat.maxExposureDuration.seconds)
            let minZoom = Float(device.minAvailableVideoZoomFactor)
            let maxZoom = Float(device.maxAvailableVideoZoomFactor)

            let currentISO = device.iso
            let currentShutter = Float(device.exposureDuration.seconds)
            let currentZoom = Float(device.videoZoomFactor)
            let currentFocus = device.lensPosition
            let focusModeStr = (device.focusMode == .locked) ? "locked" : "continuous"

            let currentGains = device.deviceWhiteBalanceGains
            let tempAndTint = device.temperatureAndTintValues(for: currentGains)
            let wbModeStr = (device.whiteBalanceMode == .locked) ? "locked" : "continuous"

            let caps: [String: Any] = [
                "minISO": minISO,
                "maxISO": maxISO,
                "minShutter": minShutter,
                "maxShutter": maxShutter,
                "minZoom": minZoom,
                "maxZoom": maxZoom,
                "currentISO": currentISO,
                "currentShutter": currentShutter,
                "currentZoom": currentZoom,
                "currentFocus": currentFocus,
                "focusMode": focusModeStr,
                "wbTemperature": tempAndTint.temperature,
                "wbTint": tempAndTint.tint,
                "wbMode": wbModeStr,
                "supportsManualFocus": device.isFocusModeSupported(.locked),
                "supportsCustomExposure": device.isExposureModeSupported(.custom),
                "supportsManualWB": device.isWhiteBalanceModeSupported(.locked),
                "activeLens": self.getLensTypeString(from: device.deviceType)
            ]

            call.resolve(caps)
        }
    }

    // MARK: - Hardware Controls

    @objc func configureLens(_ call: CAPPluginCall) {
        let iso = call.getFloat("iso")
        let shutter = call.getFloat("shutter")
        let zoom = call.getFloat("zoom")
        let lensType = call.getString("lensType")
        let focus = call.getFloat("focus")
        let focusMode = call.getString("focusMode")
        let wbTemp = call.getFloat("wbTemperature")
        let wbTint = call.getFloat("wbTint")
        let wbMode = call.getString("wbMode")

        applyLensConfiguration(
            iso: iso, shutter: shutter, zoom: zoom, lensType: lensType,
            focus: focus, focusMode: focusMode,
            wbTemperature: wbTemp, wbTint: wbTint, wbMode: wbMode
        ) { error in
            if let err = error {
                call.reject(err)
            } else {
                call.resolve(["status": "success"])
            }
        }
    }

    @objc func setISO(_ call: CAPPluginCall) {
        guard let iso = call.getFloat("iso") else {
            call.reject("ISO value required")
            return
        }
        let shutter = call.getFloat("shutter")
        applyLensConfiguration(iso: iso, shutter: shutter, zoom: nil, lensType: nil, focus: nil, focusMode: nil, wbTemperature: nil, wbTint: nil, wbMode: nil) { err in
            if let err = err { call.reject(err) } else { call.resolve(["status": "success"]) }
        }
    }

    @objc func setShutterSpeed(_ call: CAPPluginCall) {
        guard let shutter = call.getFloat("shutter") else {
            call.reject("Shutter value required")
            return
        }
        let iso = call.getFloat("iso")
        applyLensConfiguration(iso: iso, shutter: shutter, zoom: nil, lensType: nil, focus: nil, focusMode: nil, wbTemperature: nil, wbTint: nil, wbMode: nil) { err in
            if let err = err { call.reject(err) } else { call.resolve(["status": "success"]) }
        }
    }

    @objc func setFocusDistance(_ call: CAPPluginCall) {
        let focus = call.getFloat("focus")
        let mode = call.getString("mode") ?? (focus != nil ? "locked" : "continuous")
        applyLensConfiguration(iso: nil, shutter: nil, zoom: nil, lensType: nil, focus: focus, focusMode: mode, wbTemperature: nil, wbTint: nil, wbMode: nil) { err in
            if let err = err { call.reject(err) } else { call.resolve(["status": "success"]) }
        }
    }

    @objc func setZoomFactor(_ call: CAPPluginCall) {
        guard let zoom = call.getFloat("zoom") else {
            call.reject("Zoom value required")
            return
        }
        applyLensConfiguration(iso: nil, shutter: nil, zoom: zoom, lensType: nil, focus: nil, focusMode: nil, wbTemperature: nil, wbTint: nil, wbMode: nil) { err in
            if let err = err { call.reject(err) } else { call.resolve(["status": "success"]) }
        }
    }

    @objc func setLensType(_ call: CAPPluginCall) {
        guard let lensType = call.getString("lensType") else {
            call.reject("lensType string required")
            return
        }
        applyLensConfiguration(iso: nil, shutter: nil, zoom: nil, lensType: lensType, focus: nil, focusMode: nil, wbTemperature: nil, wbTint: nil, wbMode: nil) { err in
            if let err = err { call.reject(err) } else { call.resolve(["status": "success"]) }
        }
    }

    @objc func setWhiteBalance(_ call: CAPPluginCall) {
        let temp = call.getFloat("temperature")
        let tint = call.getFloat("tint")
        let mode = call.getString("mode") ?? ((temp != nil || tint != nil) ? "locked" : "continuous")
        applyLensConfiguration(iso: nil, shutter: nil, zoom: nil, lensType: nil, focus: nil, focusMode: nil, wbTemperature: temp, wbTint: tint, wbMode: mode) { err in
            if let err = err { call.reject(err) } else { call.resolve(["status": "success"]) }
        }
    }

    internal func applyLensConfiguration(
        iso: Float?, shutter: Float?, zoom: Float?, lensType: String?,
        focus: Float?, focusMode: String?,
        wbTemperature: Float?, wbTint: Float?, wbMode: String?,
        completion: @escaping (String?) -> Void
    ) {
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
            
                // Exposure Controls
                if iso != nil || shutter != nil {
                    let targetISO = iso ?? device.iso
                    let targetShutter = shutter ?? Float(device.exposureDuration.seconds)

                    let clampedISO = min(max(targetISO, device.activeFormat.minISO), device.activeFormat.maxISO)
                    let duration = CMTime(seconds: Double(targetShutter), preferredTimescale: 1000000)
                    let clampedDuration = max(min(duration, device.activeFormat.maxExposureDuration), device.activeFormat.minExposureDuration)
            
                    if device.isExposureModeSupported(.custom) {
                    device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO, completionHandler: nil)
                }
                }

                // Digital Zoom Control
                if let targetZoom = zoom {
                    let clampedZoom = min(max(CGFloat(targetZoom), device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                    device.videoZoomFactor = clampedZoom
            }
            
                // Focus Control
                if let fMode = focusMode, fMode == "continuous" {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                } else if let targetFocus = focus {
                    if device.isFocusModeSupported(.locked) {
                        let clampedFocus = min(max(targetFocus, 0.0), 1.0)
                        device.focusMode = .locked
                        device.setFocusModeLocked(lensPosition: clampedFocus, completionHandler: nil)
                    }
                }

                // White Balance Control
                if let wMode = wbMode, wMode == "continuous" {
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                } else if wbTemperature != nil || wbTint != nil {
                    if device.isWhiteBalanceModeSupported(.locked) {
                        let currentTT = device.temperatureAndTintValues(for: device.deviceWhiteBalanceGains)
                        let targetTemp = wbTemperature ?? currentTT.temperature
                        let targetTint = wbTint ?? currentTT.tint

                        let tempTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: targetTemp, tint: targetTint)
                        var gains = device.deviceWhiteBalanceGains(for: tempTint)
                        let maxGain = device.maxWhiteBalanceGain

                        gains.redGain = min(max(gains.redGain, 1.0), maxGain)
                        gains.greenGain = min(max(gains.greenGain, 1.0), maxGain)
                        gains.blueGain = min(max(gains.blueGain, 1.0), maxGain)

                        device.whiteBalanceMode = .locked
                        device.setWhiteBalanceModeLocked(with: gains, completionHandler: nil)
                    }
                }
            
            device.unlockForConfiguration()
                completion(nil)
        } catch {
                completion("Failed to lock device configuration: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Internal Helpers

    internal func setupPreviewLayer() {
        guard let webView = self.bridge?.webView, let superview = webView.superview else {
            return
        }
    
        self.previewLayer?.removeFromSuperlayer()

        let layer = AVCaptureVideoPreviewLayer(session: self.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = webView.bounds

        let orientation = self.getCurrentVideoOrientation()
        if let connection = layer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = orientation
        }

        superview.layer.insertSublayer(layer, below: webView.layer)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        self.previewLayer = layer
        self.setupWebViewBoundsObserver()
    }

    internal func switchLensHardware(to lensType: String) {
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

        if let connection = videoOutput?.connection(with: .video), connection.isVideoOrientationSupported {
            connection.videoOrientation = getCurrentVideoOrientation()
        }
    }

    internal func getDevice(for lensType: String) -> AVCaptureDevice? {
        let deviceType = getDeviceType(from: lensType)
        return AVCaptureDevice.default(deviceType, for: .video, position: .back)
    }

    internal func getDeviceType(from lensType: String) -> AVCaptureDevice.DeviceType {
        switch lensType {
        case "UltraWide":
            return .builtInUltraWideCamera
        case "Telephoto":
            return .builtInTelephotoCamera
        default:
            return .builtInWideAngleCamera
        }
    }

    internal func getLensTypeString(from deviceType: AVCaptureDevice.DeviceType) -> String {
        switch deviceType {
        case .builtInUltraWideCamera:
            return "UltraWide"
        case .builtInTelephotoCamera:
            return "Telephoto"
        default:
            return "Wide"
        }
    }

    internal func getCapturePreset(from presetString: String) -> AVCaptureSession.Preset {
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