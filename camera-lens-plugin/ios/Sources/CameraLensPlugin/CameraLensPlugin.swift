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
        CAPPluginMethod(name: "configureLens", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopSession", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setEncoderSettings", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getEncoderStats", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "connectWebSocket", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disconnectWebSocket", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getWebSocketStatus", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDeviceCapabilities", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setISO", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setShutterSpeed", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setFocusDistance", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setZoomFactor", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setLensType", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setWhiteBalance", returnType: CAPPluginReturnPromise)
    ]
    
    // Capture Session Objects
    internal let captureSession = AVCaptureSession()
    internal var activeDevice: AVCaptureDevice?
    internal var activeInput: AVCaptureDeviceInput?
    internal var videoOutput: AVCaptureVideoDataOutput?
    internal var previewLayer: AVCaptureVideoPreviewLayer?

    // VideoToolbox Encoder Objects
    internal var compressionSession: VTCompressionSession?
    internal var currentEncoderWidth: Int32 = 0
    internal var currentEncoderHeight: Int32 = 0
    internal var targetBitrate: Int32 = 4_000_000 // Default 4 Mbps
    internal var targetFPS: Int32 = 30
    internal var maxKeyFrameInterval: Int32 = 30 // Keyframe every 1s at 30fps

    // Encoder Statistics & Delegates
    public weak var encoderDelegate: H264EncoderDelegate?
    internal var encodedFrameCount: Int64 = 0
    internal var keyFrameCount: Int64 = 0
    internal var lastEncodedFrameBytes: Int = 0

    // Networking (WebSocket) State
    internal var webSocketTask: URLSessionWebSocketTask?
    internal var urlSession: URLSession?
    internal var isWsConnected = false
    internal var serverAddress: String = ""

    // Dispatch Queues
    internal let sessionQueue = DispatchQueue(label: "com.cameralens.sessionQueue")
    internal let frameProcessingQueue = DispatchQueue(label: "com.cameralens.frameQueue", qos: .userInitiated)
    internal let wsQueue = DispatchQueue(label: "com.cameralens.wsQueue", qos: .userInitiated)

    // Layout Observer
    internal var boundsObservation: NSKeyValueObservation?

    override public func load() {
        super.load()
        self.encoderDelegate = self
        
        DispatchQueue.main.async {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleOrientationChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(self.handleOrientationChange),
                name: UIApplication.didChangeStatusBarOrientationNotification,
                object: nil
            )

            self.setupWebViewBoundsObserver()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        boundsObservation?.invalidate()
    }

    internal func setupWebViewBoundsObserver() {
        guard boundsObservation == nil, let webView = self.bridge?.webView else { return }
        boundsObservation = webView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
            self?.handleOrientationChange()
        }
    }

    // MARK: - Orientation Management

    @objc internal func handleOrientationChange() {
        updateOrientationAndBounds()
    }

    internal func updateOrientationAndBounds() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            let orientation = self.getCurrentVideoOrientation()
            
            // 1. Update Capture Output Orientation
            if let connection = self.videoOutput?.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = orientation
            }
            
            // 2. Update Preview Layer Bounds and Orientation on Main Thread
            DispatchQueue.main.async {
                if let webView = self.bridge?.webView, let previewLayer = self.previewLayer {
                    previewLayer.frame = webView.bounds
                    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                        connection.videoOrientation = orientation
                    }
                }
            }
        }
    }

    internal func getCurrentVideoOrientation() -> AVCaptureVideoOrientation {
        if #available(iOS 13.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                switch windowScene.interfaceOrientation {
                case .portrait:
                    return .portrait
                case .portraitUpsideDown:
                    return .portraitUpsideDown
                case .landscapeLeft:
                    return .landscapeLeft
                case .landscapeRight:
                    return .landscapeRight
                @unknown default:
                    return .portrait
                }
            }
        }
        
        switch UIDevice.current.orientation {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }
}