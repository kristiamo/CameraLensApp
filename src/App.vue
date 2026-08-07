<script setup>
import { ref, onUnmounted } from 'vue';
import { useCamera } from './composables/useCamera';

const { 
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
} = useCamera();

// Control State
const selectedPreset = ref('hd1920x1080');
const selectedLens = ref('Wide');
const targetBitrate = ref(4000000); // 4 Mbps
const targetFPS = ref(30);

const isoValue = ref(100);
const shutterSpeed = ref(0.02);
const zoomValue = ref(1.0);

let statsInterval = null;

async function handleStartSession() {
  await startCameraSession(selectedPreset.value, selectedLens.value, targetBitrate.value, targetFPS.value);
  // Start polling encoder metrics every 500ms
  statsInterval = setInterval(fetchEncoderStats, 500);
}

async function handleStopSession() {
  if (statsInterval) clearInterval(statsInterval);
  await stopCameraSession();
}

async function handleUpdateEncoder() {
  await updateEncoderSettings(targetBitrate.value, targetFPS.value);
}

async function handleApplySettings() {
  await setManualLensSettings({
    iso: isoValue.value,
    shutter: shutterSpeed.value,
    zoom: zoomValue.value,
    lensType: selectedLens.value
  });
}

onUnmounted(() => {
  if (statsInterval) clearInterval(statsInterval);
});
</script>

<template>
  <main class="container">
    <header class="header">
      <h1>Phase 2: H.264 Encoder Pipeline</h1>
      <span class="badge" :class="{ active: isStreaming }">
        {{ isStreaming ? 'ENCODER RUNNING' : 'STOPPED' }}
      </span>
    </header>

    <!-- 1. Session & Encoder Setup -->
    <section class="card">
      <h2>1. Session & H.264 Encoder Config</h2>
      
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

    <!-- 2. Real-Time Hardware Encoder Metrics -->
    <section v-if="isStreaming && encoderStats" class="card stats-card">
      <h2>Hardware H.264 Encoding Metrics</h2>
      <div class="metrics-grid">
        <div class="metric">
          <span class="metric-label">Total Frames</span>
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
          <span class="metric-label">Target Bitrate</span>
          <span class="metric-value">{{ (encoderStats.bitrate / 1000000).toFixed(1) }} Mbps</span>
        </div>
      </div>
    </section>

    <!-- 3. Manual Camera Controls -->
    <section class="card" :class="{ disabled: !isStreaming }">
      <h2>3. Camera Hardware Controls</h2>
      
      <div class="field">
        <label>Switch Lens:</label>
        <select v-model="selectedLens" :disabled="!isStreaming" @change="handleApplySettings">
          <option value="Wide">Wide Angle</option>
          <option value="UltraWide">Ultra Wide</option>
          <option value="Telephoto">Telephoto</option>
        </select>
      </div>

      <div class="field">
        <label>Digital Zoom ({{ zoomValue }}x):</label>
        <input v-model.number="zoomValue" type="range" min="1.0" max="8.0" step="0.1" :disabled="!isStreaming" @input="handleApplySettings"/>
      </div>

      <div class="field">
        <label>ISO ({{ isoValue }}):</label>
        <input v-model.number="isoValue" type="range" min="50" max="1200" step="10" :disabled="!isStreaming" @input="handleApplySettings"/>
      </div>

      <div class="field">
        <label>Shutter Speed ({{ shutterSpeed }}s):</label>
        <input v-model.number="shutterSpeed" type="range" min="0.0005" max="0.1" step="0.0005" :disabled="!isStreaming" @input="handleApplySettings"/>
      </div>
    </section>

    <!-- Diagnostics -->
    <section class="card status-box">
        <p><strong>Status:</strong> {{ statusMessage || 'Ready' }}</p>
      <pre v-if="lastResponse">{{ JSON.stringify(lastResponse, null, 2) }}</pre>
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

h1 { font-size: 1.25rem; margin: 0; }
h2 { font-size: 0.95rem; margin: 0 0 0.75rem 0; border-bottom: 1px solid rgba(255, 255, 255, 0.2); padding-bottom: 0.3rem; }

.badge {
  font-size: 0.7rem;
  font-weight: bold;
  padding: 0.25rem 0.5rem;
  border-radius: 4px;
  background: rgba(255, 59, 48, 0.8);
}

.badge.active {
  background: rgba(52, 199, 89, 0.9);
}

.card {
  background: rgba(0, 0, 0, 0.65);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.18);
  border-radius: 12px;
  padding: 1rem;
  margin-bottom: 1rem;
}

.card.disabled {
  opacity: 0.5;
}

.field-group { display: flex; gap: 0.75rem; }
.field { display: flex; flex-direction: column; margin-bottom: 0.75rem; flex: 1; }

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
pre { background: rgba(0, 0, 0, 0.5); padding: 0.5rem; border-radius: 6px; color: #34c759; font-size: 0.75rem; }
</style>