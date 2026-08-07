import { ref } from 'vue';
import { registerPlugin } from '@capacitor/core';

const CameraLensPlugin = registerPlugin('CameraLensPlugin', {
    web: () => import('../mocks/custom-plugins.js').then(m => m.MockCameraLensPlugin),
});

export function useCamera() {
    const statusMessage = ref('');
    const lastResponse = ref(null);
    const isLoading = ref(false);
    const isStreaming = ref(false);
    const encoderStats = ref(null);

    // Dynamic Hardware Device Capabilities
    const deviceCapabilities = ref(null);

    // Extended Camera Controls Reactive State
    const focusValue = ref(0.5);
    const focusMode = ref('continuous'); // 'continuous' or 'locked'
    const wbTemperature = ref(5000);
    const wbTint = ref(0);
    const wbMode = ref('continuous'); // 'continuous' or 'locked'

    // WebSocket Reactive State
    const wsConnected = ref(false);
    const wsServerUrl = ref('');

    async function startCameraSession(preset = 'hd1920x1080', lensType = 'Wide', bitrate = 4000000, fps = 30) {
        isLoading.value = true;
        statusMessage.value = 'Starting camera capture session & encoder...';
        try {
            document.documentElement.style.backgroundColor = 'transparent';
            document.body.style.backgroundColor = 'transparent';

            const res = await CameraLensPlugin.startSession({ preset, lensType, bitrate, fps });
            lastResponse.value = res;
            isStreaming.value = true;
            statusMessage.value = `Camera & Encoder Active (${preset}, ${bitrate / 1000000}Mbps)`;
            
            // Query hardware capabilities after starting capture session
            await fetchDeviceCapabilities();
            return res;
        } catch (error) {
            statusMessage.value = `Start Session Error: ${error.message || error}`;
            console.error('Error in startCameraSession:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    async function stopCameraSession() {
        isLoading.value = true;
        statusMessage.value = 'Stopping session & encoder...';
        try {
            const res = await CameraLensPlugin.stopSession();
            lastResponse.value = res;
            isStreaming.value = false;
            deviceCapabilities.value = null;
            statusMessage.value = 'Camera session stopped';
            return res;
        } catch (error) {
            statusMessage.value = `Stop Session Error: ${error.message || error}`;
            console.error('Error in stopCameraSession:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    async function fetchDeviceCapabilities() {
        try {
            const caps = await CameraLensPlugin.getDeviceCapabilities();
            deviceCapabilities.value = caps;
            if (caps.currentFocus !== undefined) focusValue.value = caps.currentFocus;
            if (caps.focusMode !== undefined) focusMode.value = caps.focusMode;
            if (caps.wbTemperature !== undefined) wbTemperature.value = caps.wbTemperature;
            if (caps.wbTint !== undefined) wbTint.value = caps.wbTint;
            if (caps.wbMode !== undefined) wbMode.value = caps.wbMode;
            return caps;
        } catch (error) {
            console.error('Failed to query device capabilities:', error);
        }
    }

    async function setManualLensSettings(params) {
        statusMessage.value = 'Updating camera parameters...';
        try {
            const res = await CameraLensPlugin.configureLens({
                iso: params.iso ? parseFloat(params.iso) : undefined,
                shutter: params.shutter ? parseFloat(params.shutter) : undefined,
                zoom: params.zoom ? parseFloat(params.zoom) : undefined,
                lensType: params.lensType || undefined,
                focus: params.focus !== undefined ? parseFloat(params.focus) : undefined,
                focusMode: params.focusMode || undefined,
                wbTemperature: params.wbTemperature ? parseFloat(params.wbTemperature) : undefined,
                wbTint: params.wbTint !== undefined ? parseFloat(params.wbTint) : undefined,
                wbMode: params.wbMode || undefined
            });
            lastResponse.value = res;
            statusMessage.value = 'Camera settings updated';
            return res;
        } catch (error) {
            statusMessage.value = `Configure Error: ${error.message || error}`;
            console.error('Error in setManualLensSettings:', error);
            throw error;
        }
    }

    async function setISO(iso, shutter) {
        try {
            return await CameraLensPlugin.setISO({ iso: parseFloat(iso), shutter: shutter ? parseFloat(shutter) : undefined });
        } catch (e) {
            statusMessage.value = `ISO Error: ${e.message || e}`;
        }
    }

    async function setShutterSpeed(shutter, iso) {
        try {
            return await CameraLensPlugin.setShutterSpeed({ shutter: parseFloat(shutter), iso: iso ? parseFloat(iso) : undefined });
        } catch (e) {
            statusMessage.value = `Shutter Error: ${e.message || e}`;
        }
    }

    async function setFocusDistance(focus, mode = 'locked') {
        try {
            focusValue.value = focus;
            focusMode.value = mode;
            return await CameraLensPlugin.setFocusDistance({ focus: parseFloat(focus), mode });
        } catch (e) {
            statusMessage.value = `Focus Error: ${e.message || e}`;
        }
    }

    async function setZoomFactor(zoom) {
        try {
            return await CameraLensPlugin.setZoomFactor({ zoom: parseFloat(zoom) });
        } catch (e) {
            statusMessage.value = `Zoom Error: ${e.message || e}`;
        }
    }

    async function setLensType(lensType) {
        try {
            const res = await CameraLensPlugin.setLensType({ lensType });
            await fetchDeviceCapabilities();
            return res;
        } catch (e) {
            statusMessage.value = `Lens Error: ${e.message || e}`;
        }
    }

    async function setWhiteBalance(temperature, tint = 0, mode = 'locked') {
        try {
            wbTemperature.value = temperature;
            wbTint.value = tint;
            wbMode.value = mode;
            return await CameraLensPlugin.setWhiteBalance({
                temperature: parseFloat(temperature),
                tint: parseFloat(tint),
                mode
            });
        } catch (e) {
            statusMessage.value = `White Balance Error: ${e.message || e}`;
        }
    }

    async function updateEncoderSettings(bitrate, fps, gop = 30) {
        try {
            const res = await CameraLensPlugin.setEncoderSettings({
                bitrate: parseInt(bitrate),
                fps: parseInt(fps),
                gop: parseInt(gop)
            });
            lastResponse.value = res;
            statusMessage.value = `Encoder updated: ${bitrate / 1000000}Mbps @ ${fps}FPS`;
            return res;
        } catch (error) {
            statusMessage.value = `Encoder Config Error: ${error.message || error}`;
            throw error;
        }
    }

    async function fetchEncoderStats() {
        try {
            const res = await CameraLensPlugin.getEncoderStats();
            encoderStats.value = res;
            return res;
        } catch (error) {
            console.error('Failed to query encoder stats:', error);
        }
    }

    async function connectWebSocket(ip, port = 8080) {
        isLoading.value = true;
        statusMessage.value = `Connecting to WebSocket ws://${ip}:${port}...`;
        try {
            const res = await CameraLensPlugin.connectWebSocket({ ip, port: parseInt(port) });
            wsConnected.value = true;
            wsServerUrl.value = res.url;
            statusMessage.value = `WebSocket connected to ${res.url}`;
            return res;
        } catch (error) {
            wsConnected.value = false;
            statusMessage.value = `WebSocket Connection Error: ${error.message || error}`;
            console.error('Error connecting WebSocket:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    async function disconnectWebSocket() {
        isLoading.value = true;
        try {
            const res = await CameraLensPlugin.disconnectWebSocket();
            wsConnected.value = false;
            wsServerUrl.value = '';
            statusMessage.value = 'WebSocket disconnected';
            return res;
        } catch (error) {
            statusMessage.value = `WebSocket Disconnect Error: ${error.message || error}`;
            console.error('Error disconnecting WebSocket:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    /**
     * Register listeners for remote control actions dispatched by Desktop App via WS
     */
    function setupRemoteListeners(onCameraConfig, onEncoderConfig) {
        const camListener = CameraLensPlugin.addListener('remoteCameraConfig', (data) => {
            if (data.focus !== undefined) focusValue.value = data.focus;
            if (data.focusMode !== undefined) focusMode.value = data.focusMode;
            if (data.wbTemperature !== undefined) wbTemperature.value = data.wbTemperature;
            if (data.wbTint !== undefined) wbTint.value = data.wbTint;
            if (data.wbMode !== undefined) wbMode.value = data.wbMode;

            if (onCameraConfig) onCameraConfig(data);
        });

        const encListener = CameraLensPlugin.addListener('remoteEncoderConfig', (data) => {
            if (onEncoderConfig) onEncoderConfig(data);
        });

        return () => {
            camListener.then(l => l.remove());
            encListener.then(l => l.remove());
        };
    }

    return {
        statusMessage,
        lastResponse,
        isLoading,
        isStreaming,
        encoderStats,
        deviceCapabilities,
        focusValue,
        focusMode,
        wbTemperature,
        wbTint,
        wbMode,
        wsConnected,
        wsServerUrl,
        startCameraSession,
        stopCameraSession,
        fetchDeviceCapabilities,
        setManualLensSettings,
        setISO,
        setShutterSpeed,
        setFocusDistance,
        setZoomFactor,
        setLensType,
        setWhiteBalance,
        updateEncoderSettings,
        fetchEncoderStats,
        connectWebSocket,
        disconnectWebSocket,
        setupRemoteListeners
    };
}