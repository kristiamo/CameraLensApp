import { ref } from 'vue';
import { registerPlugin } from '@capacitor/core';

const CameraLensPlugin = registerPlugin('CameraLensPlugin');

export function useCamera() {
    const statusMessage = ref('');
    const lastResponse = ref(null);
    const isLoading = ref(false);

    async function setManualLensSettings(isoValue, shutterSpeed, physicalLensType) {
        isLoading.value = true;
        statusMessage.value = 'Configuring camera lens...';
        try {
            const res = await CameraLensPlugin.configureLens({
            iso: isoValue,
            shutter: shutterSpeed,
            lensType: physicalLensType // "UltraWide", "Wide", "Telephoto"
        });
            lastResponse.value = res;
            statusMessage.value = `Lens configured successfully (${physicalLensType})`;
            return res;
        } catch (error) {
            statusMessage.value = `Error: ${error.message || error}`;
            console.error('Error in setManualLensSettings:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    async function testNativeCode(message = 'Hello from JS!') {
        isLoading.value = true;
        statusMessage.value = 'Testing native bridge...';
        try {
            const result = await CameraLensPlugin.deviceAction({ message });
            lastResponse.value = result;
            statusMessage.value = `Received: ${result.value}`;
            return result;
        } catch (error) {
            statusMessage.value = `Bridge Error: ${error.message || error}`;
            console.error('Error invoking native plugin:', error);
            throw error;
        } finally {
            isLoading.value = false;
        }
    }

    return {
        statusMessage,
        lastResponse,
        isLoading,
        setManualLensSettings,
        testNativeCode
    };
}