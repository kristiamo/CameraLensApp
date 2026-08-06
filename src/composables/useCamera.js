import { ref } from 'vue';
import { registerPlugin } from '@capacitor/core';

const CameraLensPlugin = registerPlugin('CameraLensPlugin');

export function useCamera() {
    const statusMessage = ref('');
    const lastResponse = ref(null);
    const isLoading = ref(false);
    const isStreaming = ref(false);

    /**
     * Start the native capture session with resolution & lens parameters
     * @param {string} preset - Resolution preset ("hd1280x720", "hd1920x1080", "hd3840x2160")
     * @param {string} lensType - "Wide", "UltraWide", or "Telephoto"
     */
    async function startCameraSession(preset = 'hd1920x1080', lensType = 'Wide') {
        isLoading.value = true;
        statusMessage.value = 'Starting camera capture session...';
        try {
            // Ensure HTML document background is transparent so native layer reveals
            document.documentElement.style.backgroundColor = 'transparent';
            document.body.style.backgroundColor = 'transparent';

            const res = await CameraLensPlugin.startSession({ preset, lensType });
            lastResponse.value = res;
            isStreaming.value = true;
            statusMessage.value = `Camera session active (${preset}, ${lensType})`;
            return res;
        } catch (error) {
            statusMessage.value = `Start Session Error: ${error.message || error}`;
            console.error('Error in startCameraSession:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    /**
     * Stop the native capture session and clean up memory/preview layer
     */
    async function stopCameraSession() {
        isLoading.value = true;
        statusMessage.value = 'Stopping camera capture session...';
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

    /**
     * Dynamically update manual hardware configurations on the fly
     */
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
            statusMessage.value = 'Camera settings updated successfully';
            return res;
        } catch (error) {
            statusMessage.value = `Configure Error: ${error.message || error}`;
            console.error('Error in setManualLensSettings:', error);
            throw error;
        }
    }

    return {
        statusMessage,
        lastResponse,
        isLoading,
        isStreaming,
        startCameraSession,
        stopCameraSession,
        setManualLensSettings
    };
}