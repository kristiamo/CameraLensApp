console.log('[Mock CameraLensPlugin] Registering mock plugin');

let isStreaming = false;
let frameCounter = 0;

const mockCapabilities = {
    minISO: 50,
    maxISO: 1200,
    minShutter: 0.0005,
    maxShutter: 0.1,
    maxZoom: 8.0,
    currentFocus: 0.5,
    focusMode: 'continuous',
    wbTemperature: 5000,
    wbTint: 0,
    wbMode: 'continuous',
    iso: 100,
    shutter: 0.02,
    zoom: 1.0,
    lensType: 'Wide',
    bitrate: 4000000,
    fps: 30
};

export const MockCameraLensPlugin = {
    async startSession(options = {}) {
        isStreaming = true;
        console.log('[Mock CameraLensPlugin] Starting session with:', options);
        if (options.bitrate) mockCapabilities.bitrate = options.bitrate;
        if (options.fps) mockCapabilities.fps = options.fps;
        if (options.lensType) mockCapabilities.lensType = options.lensType;
        return { status: 'started', preset: options.preset || 'hd1920x1080' };
    },

    async stopSession() {
        isStreaming = false;
        console.log('[Mock CameraLensPlugin] Stopped session');
        return { status: 'stopped' };
    },

    async getDeviceCapabilities() {
        console.log('[Mock CameraLensPlugin] Fetching device capabilities');
        return { ...mockCapabilities };
    },

    async configureLens(params = {}) {
        console.log('[Mock CameraLensPlugin] Configuring lens:', params);
        Object.keys(params).forEach((key) => {
            if (params[key] !== undefined) {
                mockCapabilities[key] = params[key];
            }
        });
        return { status: 'success', currentSettings: { ...mockCapabilities } };
    },

    async setISO(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting ISO:', options);
        if (options.iso) mockCapabilities.iso = options.iso;
        if (options.shutter) mockCapabilities.shutter = options.shutter;
        return { status: 'success', iso: mockCapabilities.iso };
    },

    async setShutterSpeed(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting Shutter Speed:', options);
        if (options.shutter) mockCapabilities.shutter = options.shutter;
        if (options.iso) mockCapabilities.iso = options.iso;
        return { status: 'success', shutter: mockCapabilities.shutter };
    },

    async setFocusDistance(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting Focus Distance:', options);
        if (options.focus !== undefined) mockCapabilities.currentFocus = options.focus;
        if (options.mode) mockCapabilities.focusMode = options.mode;
        return { status: 'success', focus: mockCapabilities.currentFocus, mode: mockCapabilities.focusMode };
    },

    async setZoomFactor(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting Zoom Factor:', options);
        if (options.zoom) mockCapabilities.zoom = options.zoom;
        return { status: 'success', zoom: mockCapabilities.zoom };
    },

    async setLensType(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting Lens Type:', options);
        if (options.lensType) mockCapabilities.lensType = options.lensType;
        return { status: 'success', lensType: mockCapabilities.lensType };
    },

    async setWhiteBalance(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting White Balance:', options);
        if (options.temperature) mockCapabilities.wbTemperature = options.temperature;
        if (options.tint !== undefined) mockCapabilities.wbTint = options.tint;
        if (options.mode) mockCapabilities.wbMode = options.mode;
        return { status: 'success', wbTemperature: mockCapabilities.wbTemperature, wbTint: mockCapabilities.wbTint };
    },

    async setEncoderSettings(options = {}) {
        console.log('[Mock CameraLensPlugin] Setting Encoder Settings:', options);
        if (options.bitrate) mockCapabilities.bitrate = options.bitrate;
        if (options.fps) mockCapabilities.fps = options.fps;
        return { status: 'success', bitrate: mockCapabilities.bitrate, fps: mockCapabilities.fps };
    },

    async getEncoderStats() {
        if (isStreaming) {
            frameCounter += mockCapabilities.fps / 2;
        }
        return {
            encodedFrames: Math.floor(frameCounter),
            keyFrames: Math.floor(frameCounter / 30),
            lastFrameBytes: Math.floor(15000 + Math.random() * 5000),
            bitrate: mockCapabilities.bitrate
        };
    },

    async connectWebSocket(options = {}) {
        const url = `ws://${options.ip}:${options.port || 8080}`;
        console.log('[Mock CameraLensPlugin] Connected WebSocket to:', url);
        return { status: 'connected', url };
    },

    async disconnectWebSocket() {
        console.log('[Mock CameraLensPlugin] Disconnected WebSocket');
        return { status: 'disconnected' };
    },

    async addListener(eventName, callback) {
        console.log(`[Mock CameraLensPlugin] Listener attached for: ${eventName}`);
        return {
            remove: async () => {
                console.log(`[Mock CameraLensPlugin] Listener removed for: ${eventName}`);
            }
        };
    }
};
