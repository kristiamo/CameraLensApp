import Foundation
import Capacitor
import AVFoundation

@objc(CameraLensPlugin)
public class CameraLensPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "CameraLensPlugin" 
    public let jsName = "CameraLensPlugin" 
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "deviceAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "configureLens", returnType: CAPPluginReturnPromise)
    ]
    
    @objc func deviceAction(_ call: CAPPluginCall) {
        // Retrieve data sent from JavaScript
        let inputMessage = call.getString("message") ?? "No message provided"
        
        // Execute native iOS logic here (e.g., triggering haptics, checking system settings)
        let resultString = "Native iOS received: \(inputMessage)"
        
        // Resolve the promise back to JavaScript
        call.resolve([
            "value": resultString
        ])
    }
    
    private var captureSession: AVCaptureSession?
    private var activeDevice: AVCaptureDevice?

    @objc func configureLens(_ call: CAPPluginCall) {
        let iso = call.getFloat("iso") ?? 100.0
        let shutter = call.getFloat("shutter") ?? 0.02
        let lensType = call.getString("lensType") ?? "Wide"
        
        // Target specific physical lens hardware bypassing dual/triple fusion engines
        var deviceType: AVCaptureDevice.DeviceType = .builtInWideAngleCamera
        if lensType == "UltraWide" { deviceType = .builtInUltraWideCamera }
        if lensType == "Telephoto" { deviceType = .builtInTelephotoCamera }

        guard let device = AVCaptureDevice.default(deviceType, for: .video, position: .back) else {
            call.reject("Requested lens not found")
            return
        }
        
        do {
            // Gain total control over the lens pipeline
            try device.lockForConfiguration()
            
            // Set fully manual exposure mode
            let duration = CMTime(seconds: Double(shutter), preferredTimescale: 1000000)
            device.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            
            // Lock focus to prevent hunting
            if device.isFocusModeSupported(.locked) {
                device.focusMode = .locked
            }
            
            device.unlockForConfiguration()
            call.resolve(["status": "success", "lens": lensType])
        } catch {
            call.reject("Could not lock camera hardware configuration")
        }
    }
}