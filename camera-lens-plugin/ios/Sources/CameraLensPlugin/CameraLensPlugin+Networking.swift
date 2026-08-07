import Foundation
import Capacitor

extension CameraLensPlugin {

    // MARK: - Bridge Actions

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

    internal func disconnectInternal() {
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

        if action == "configureLens" || action == "setCamera" {
            let iso = (json["iso"] as? NSNumber)?.floatValue
            let shutter = (json["shutter"] as? NSNumber)?.floatValue
            let zoom = (json["zoom"] as? NSNumber)?.floatValue
            let lensType = json["lensType"] as? String
            let focus = (json["focus"] as? NSNumber)?.floatValue
            let focusMode = json["focusMode"] as? String
            let wbTemp = (json["wbTemperature"] as? NSNumber)?.floatValue
            let wbTint = (json["wbTint"] as? NSNumber)?.floatValue
            let wbMode = json["wbMode"] as? String

            applyLensConfiguration(
                iso: iso, shutter: shutter, zoom: zoom, lensType: lensType,
                focus: focus, focusMode: focusMode,
                wbTemperature: wbTemp, wbTint: wbTint, wbMode: wbMode
            ) { [weak self] error in
                if error == nil {
                    var payload: [String: Any] = [:]
                    if let iso = iso { payload["iso"] = iso }
                    if let shutter = shutter { payload["shutter"] = shutter }
                    if let zoom = zoom { payload["zoom"] = zoom }
                    if let lensType = lensType { payload["lensType"] = lensType }
                    if let focus = focus { payload["focus"] = focus }
                    if let focusMode = focusMode { payload["focusMode"] = focusMode }
                    if let wbTemp = wbTemp { payload["wbTemperature"] = wbTemp }
                    if let wbTint = wbTint { payload["wbTint"] = wbTint }
                    if let wbMode = wbMode { payload["wbMode"] = wbMode }

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

    // MARK: - H264EncoderDelegate Interface

    public func didEncodeH264Frame(naluData: Data, isKeyFrame: Bool, timestamp: Double) {
        guard isWsConnected, let ws = webSocketTask else { return }

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
}