<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useCamera } from './composables/useCamera';

const { 
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
  setManualLensSettings, 
  setFocusDistance,
  setWhiteBalance,
  updateEncoderSettings,
  fetchEncoderStats,
  connectWebSocket,
  disconnectWebSocket,
  setupRemoteListeners
} = useCamera();

// WebSocket Control State
const desktopIp = ref('192.168.1.166');
const desktopPort = ref(8080);

// Selection & Parameters
const selectedPreset = ref('hd1920x1080');
const selectedLens = ref('Wide');
const targetBitrate = ref(4000000); // 4 Mbps
const targetFPS = ref(30);

const isoValue = ref(100);
const shutterSpeed = ref(0.02);
const zoomValue = ref(1.0);

let statsInterval = null;
let removeListeners = null;

// Dynamic device range compute helpers
const minISO = computed(() => deviceCapabilities.value?.minISO || 50);
const maxISO = computed(() => deviceCapabilities.value?.maxISO || 1200);
const minShutter = computed(() => deviceCapabilities.value?.minShutter || 0.0005);
const maxShutter = computed(() => deviceCapabilities.value?.maxShutter || 0.1);
const maxZoom = computed(() => deviceCapabilities.value?.maxZoom || 8.0);

async function handleStartSession() {
  await startCameraSession(selectedPreset.value, selectedLens.value, targetBitrate.value, targetFPS.value);
  statsInterval = setInterval(fetchEncoderStats, 500);
}

async function handleStopSession() {
  if (statsInterval) clearInterval(statsInterval);
  await stopCameraSession();
}

async function handleUpdateEncoder() {
  await updateEncoderSettings(targetBitrate.value, targetFPS.value);
}

async function handleApplyCameraSettings() {
  await setManualLensSettings({
    iso: isoValue.value,
    shutter: shutterSpeed.value,
    zoom: zoomValue.value,
    lensType: selectedLens.value,
    focus: focusMode.value === 'locked' ? focusValue.value : undefined,
    focusMode: focusMode.value,
    wbTemperature: wbMode.value === 'locked' ? wbTemperature.value : undefined,
    wbTint: wbMode.value === 'locked' ? wbTint.value : undefined,
    wbMode: wbMode.value
  });
}

async function handleToggleFocusMode() {
  const newMode = focusMode.value === 'continuous' ? 'locked' : 'continuous';
  await setFocusDistance(focusValue.value, newMode);
}

async function handleToggleWBMode() {
  const newMode = wbMode.value === 'continuous' ? 'locked' : 'continuous';
  await setWhiteBalance(wbTemperature.value, wbTint.value, newMode);
}

async function handleToggleWebSocket() {
  if (wsConnected.value) {
    await disconnectWebSocket();
  } else {
    await connectWebSocket(desktopIp.value, desktopPort.value);
  }
}

onMounted(() => {
  // Synchronize state when desktop modifies parameters remotely over WebSocket
  removeListeners = setupRemoteListeners(
    (camConfig) => {
      if (camConfig.iso !== undefined) isoValue.value = camConfig.iso;
      if (camConfig.shutter !== undefined) shutterSpeed.value = camConfig.shutter;
      if (camConfig.zoom !== undefined) zoomValue.value = camConfig.zoom;
      if (camConfig.lensType !== undefined) selectedLens.value = camConfig.lensType;
    },
    (encConfig) => {
      if (encConfig.bitrate !== undefined) targetBitrate.value = encConfig.bitrate;
      if (encConfig.fps !== undefined) targetFPS.value = encConfig.fps;
    }
  );
});

onUnmounted(() => {
  if (statsInterval) clearInterval(statsInterval);
  if (removeListeners) removeListeners();
});
</script>

<template>
  <main class="container">
    <header class="header">
      <h1>Phase 4: Manual Studio Streamer</h1>
      <div class="badge-group">
      <span class="badge" :class="{ active: isStreaming }">
        {{ isStreaming ? 'ENCODER RUNNING' : 'STOPPED' }}
      </span>
        <span class="badge ws-badge" :class="{ active: wsConnected }">
          {{ wsConnected ? 'NET STREAMING' : 'OFFLINE' }}
        </span>
      </div>
    </header>

    <!-- 1. Desktop Network Target -->
    <section class="card">
      <h2>1. Desktop Network Target</h2>
      <div class="field-group">
        <div class="field">
          <label>Server IP Address:</label>
          <input v-model="desktopIp" type="text" placeholder="192.168.1.100" :disabled="wsConnected"/>
        </div>
        <div class="field port-field">
          <label>Port:</label>
          <input v-model.number="desktopPort" type="number" placeholder="8080" :disabled="wsConnected"/>
        </div>
      </div>
      <button 
        :class="wsConnected ? 'btn-danger' : 'btn-primary'" 
        :disabled="isLoading" 
        @click="handleToggleWebSocket"
      >
        {{ wsConnected ? 'Disconnect Desktop' : 'Connect to Desktop Server' }}
      </button>
    </section>

    <!-- 2. Session & Encoder Setup -->
    <section class="card">
      <h2>2. Capture Preset & H.264 Bitrate</h2>
      
      <div class="field-group">
      <div class="field">
          <label>Preset:</label>
        <select v-model="selectedPreset" :disabled="isStreaming">
          <option value="hd1280x720">720p (1280x720)</option>
          <option value="hd1920x1080">1080p (1920x1080)</option>
          <option value="hd4K3840x2160">4K (3840x2160)</option>
        </select>
      </div>

      <div class="field">
          <label>Target Bitrate:</label>
          <select v-model.number="targetBitrate">
            <option :value="2000000">2 Mbps</option>
            <option :value="4000000">4 Mbps</option>
            <option :value="8000000">8 Mbps</option>
            <option :value="15000000">15 Mbps</option>
        </select>
      </div>
      </div>

      <div class="button-group">
        <button v-if="!isStreaming" class="btn-primary" :disabled="isLoading" @click="handleStartSession">
          Start Session & Encoder
        </button>
        <button v-else class="btn-danger" :disabled="isLoading" @click="handleStopSession">
          Stop Encoder Session
        </button>
        <button v-if="isStreaming" class="btn-secondary" :disabled="isLoading" @click="handleUpdateEncoder">
          Update Bitrate
      </button>
      </div>
    </section>

    <!-- 3. Hardware Metrics -->
    <section v-if="isStreaming && encoderStats" class="card stats-card">
      <h2>Hardware Encoding Metrics</h2>
      <div class="metrics-grid">
        <div class="metric">
          <span class="metric-label">Encoded Frames</span>
          <span class="metric-value">{{ encoderStats.encodedFrames }}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Keyframes (IDR)</span>
          <span class="metric-value">{{ encoderStats.keyFrames }}</span>
        </div>
        <div class="metric">
          <span class="metric-label">Last NALU Size</span>
          <span class="metric-value">{{ (encoderStats.lastFrameBytes / 1024).toFixed(1) }} KB</span>
        </div>
        <div class="metric">
          <span class="metric-label">Bitrate</span>
          <span class="metric-value">{{ (encoderStats.bitrate / 1000000).toFixed(1) }} Mbps</span>
        </div>
      </div>
    </section>

    <!-- 4. Granular Manual Camera Controls -->
    <section class="card" :class="{ disabled: !isStreaming }">
      <h2>4. Granular Manual Camera Controls</h2>
      
      <div class="field">
        <label>Switch Physical Lens:</label>
        <select v-model="selectedLens" :disabled="!isStreaming" @change="handleApplyCameraSettings">
          <option value="Wide">Wide Angle</option>
          <option value="UltraWide">Ultra Wide</option>
          <option value="Telephoto">Telephoto</option>
        </select>
      </div>

      <!-- Focus Distance & Mode -->
      <div class="control-box">
        <div class="control-header">
          <label>Focus Distance: <strong>{{ focusMode === 'continuous' ? 'AUTO' : focusValue.toFixed(2) }}</strong></label>
          <button class="btn-sm" :disabled="!isStreaming" @click="handleToggleFocusMode">
            {{ focusMode === 'continuous' ? 'Lock Manual Focus' : 'Switch to Auto Focus' }}
          </button>
        </div>
        <input 
          v-model.number="focusValue" 
          type="range" 
          min="0.0" 
          max="1.0" 
          step="0.01" 
          :disabled="!isStreaming || focusMode === 'continuous'" 
          @input="handleApplyCameraSettings"
        />
      </div>

      <!-- White Balance (Kelvin & Tint) -->
      <div class="control-box">
        <div class="control-header">
          <label>White Balance: <strong>{{ wbMode === 'continuous' ? 'AUTO' : wbTemperature + 'K / Tint: ' + wbTint }}</strong></label>
          <button class="btn-sm" :disabled="!isStreaming" @click="handleToggleWBMode">
            {{ wbMode === 'continuous' ? 'Lock Manual WB' : 'Switch to Auto WB' }}
          </button>
        </div>
        <div v-if="wbMode === 'locked'" class="field-group">
          <div class="field">
            <label>Temp ({{ wbTemperature }}K):</label>
            <input v-model.number="wbTemperature" type="range" min="2500" max="9000" step="50" :disabled="!isStreaming" @input="handleApplyCameraSettings"/>
          </div>
      <div class="field">
            <label>Tint ({{ wbTint }}):</label>
            <input v-model.number="wbTint" type="range" min="-100" max="100" step="1" :disabled="!isStreaming" @input="handleApplyCameraSettings"/>
          </div>
        </div>
      </div>

      <!-- ISO Exposure -->
      <div class="field">
        <label>ISO Exposure ({{ isoValue }}):</label>
        <input v-model.number="isoValue" type="range" :min="minISO" :max="maxISO" step="5" :disabled="!isStreaming" @input="handleApplyCameraSettings"/>
      </div>

      <!-- Shutter Speed -->
      <div class="field">
        <label>Shutter Speed ({{ shutterSpeed }}s):</label>
        <input v-model.number="shutterSpeed" type="range" :min="minShutter" :max="maxShutter" step="0.0005" :disabled="!isStreaming" @input="handleApplyCameraSettings"/>
      </div>

      <!-- Digital Zoom -->
      <div class="field">
        <label>Digital Zoom ({{ zoomValue }}x):</label>
        <input v-model.number="zoomValue" type="range" min="1.0" :max="maxZoom" step="0.1" :disabled="!isStreaming" @input="handleApplyCameraSettings"/>
      </div>
    </section>

    <!-- Diagnostics -->
    <section class="card status-box">
        <p><strong>Status:</strong> {{ statusMessage || 'Ready' }}</p>
      <pre v-if="deviceCapabilities">{{ JSON.stringify(deviceCapabilities, null, 2) }}</pre>
    </section>
  </main>
</template>

<style scoped>
.container {
  max-width: 500px;
  margin: 0 auto;
  padding: 1rem;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  color: #ffffff;
  min-height: 100vh;
  box-sizing: border-box;
}

.header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 1rem;
}

h1 { font-size: 1.2rem; margin: 0; }
h2 { font-size: 0.95rem; margin: 0 0 0.75rem 0; border-bottom: 1px solid rgba(255, 255, 255, 0.2); padding-bottom: 0.3rem; }

.badge-group { display: flex; gap: 0.4rem; }
.badge {
  font-size: 0.65rem;
  font-weight: bold;
  padding: 0.25rem 0.4rem;
  border-radius: 4px;
  background: rgba(255, 59, 48, 0.8);
}
.badge.active { background: rgba(52, 199, 89, 0.9); }
.badge.ws-badge { background: rgba(142, 142, 147, 0.8); }
.badge.ws-badge.active { background: rgba(0, 122, 255, 0.9); }

.card {
  background: rgba(0, 0, 0, 0.65);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 12px;
  padding: 1rem;
  margin-bottom: 1rem;
}

.card.disabled { opacity: 0.5; }

.control-box {
  background: rgba(255, 255, 255, 0.06);
  padding: 0.6rem;
  border-radius: 8px;
  margin-bottom: 0.75rem;
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.control-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.4rem;
}

.btn-sm {
  width: auto;
  padding: 0.25rem 0.5rem;
  font-size: 0.7rem;
  background: #3a3a3c;
  color: #fff;
  border-radius: 4px;
}

.field-group { display: flex; gap: 0.75rem; }
.field { display: flex; flex-direction: column; margin-bottom: 0.75rem; flex: 1; }
.port-field { max-width: 100px; }

label { font-size: 0.8rem; margin-bottom: 0.25rem; color: #ccc; }
select, input {
  padding: 0.5rem;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.3);
  background: rgba(255, 255, 255, 0.1); color: #fff; font-size: 0.9rem;
}
select option { background: #222; color: #fff; }

.button-group { display: flex; gap: 0.5rem; }
button { width: 100%; padding: 0.65rem; font-size: 0.9rem; font-weight: 600; border-radius: 6px; border: none; cursor: pointer; }
.btn-primary { background: #007aff; color: white; }
.btn-danger { background: #ff3b30; color: white; }
.btn-secondary { background: #34c759; color: white; }

.metrics-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }
.metric { background: rgba(255, 255, 255, 0.08); padding: 0.5rem; border-radius: 6px; text-align: center; }
.metric-label { display: block; font-size: 0.7rem; color: #aaa; }
.metric-value { display: block; font-size: 1.1rem; font-weight: bold; color: #34c759; margin-top: 0.2rem; }

.status-box { font-size: 0.8rem; }
pre { background: rgba(0, 0, 0, 0.5); padding: 0.5rem; border-radius: 6px; color: #34c759; font-size: 0.72rem; overflow-x: auto; }
</style>