import { ref } from 'vue';
import { registerPlugin } from '@capacitor/core';

const CameraLensPlugin = registerPlugin('CameraLensPlugin');

export function useCamera() {
    const statusMessage = ref('');
    const lastResponse = ref(null);
    const isLoading = ref(false);
    const isStreaming = ref(false);
    const encoderStats = ref(null);

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

    async function setManualLensSettings({ iso, shutter, zoom, lensType }) {
        statusMessage.value = 'Updating camera parameters...';
        try {
            const res = await CameraLensPlugin.configureLens({
                iso: iso ? parseFloat(iso) : undefined,
                shutter: shutter ? parseFloat(shutter) : undefined,
                zoom: zoom ? parseFloat(zoom) : undefined,
                lensType: lensType || undefined
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

    /**
     * Dynamically update hardware H.264 encoder parameters
     */
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

    /**
     * Poll real-time hardware encoder performance statistics
     */
    async function fetchEncoderStats() {
        try {
            const res = await CameraLensPlugin.getEncoderStats();
            encoderStats.value = res;
            return res;
        } catch (error) {
            console.error('Failed to query encoder stats:', error);
        }
    }

    return {
        statusMessage,
        lastResponse,
        isLoading,
        isStreaming,
        encoderStats,
        startCameraSession,
        stopCameraSession,
        setManualLensSettings,
        updateEncoderSettings,
        fetchEncoderStats
    };
}