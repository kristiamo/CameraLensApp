<script setup>
import { ref } from 'vue';
import { useCamera } from './composables/useCamera';

const { 
  statusMessage, 
  lastResponse, 
  isLoading, 
  isStreaming,
  startCameraSession, 
  stopCameraSession, 
  setManualLensSettings, 
  testNativeCode 
} = useCamera();

// Control State
const selectedPreset = ref('hd1920x1080');
const selectedLens = ref('Wide');
const isoValue = ref(100);
const shutterSpeed = ref(0.02);
const zoomValue = ref(1.0);

// Handlers
async function handleStartSession() {
  await startCameraSession(selectedPreset.value, selectedLens.value);
}

async function handleStopSession() {
  await stopCameraSession();
}

async function handleApplySettings() {
  await setManualLensSettings({
    iso: isoValue.value,
    shutter: shutterSpeed.value,
    zoom: zoomValue.value,
    lensType: selectedLens.value
  });
}

async function handleTestBridge() {
  await testNativeCode('Native bridge operational check');
}
</script>

<template>
  <main class="container">
    <header class="header">
      <h1>Phase 1: Camera Session Test</h1>
      <span class="badge" :class="{ active: isStreaming }">
        {{ isStreaming ? 'STREAMING ACTIVE' : 'STOPPED' }}
      </span>
    </header>

    <!-- 1. Session Lifecycle Control -->
    <section class="card">
      <h2>1. Session Lifecycle & Quality</h2>
      
      <div class="field">
        <label>Resolution Preset:</label>
        <select v-model="selectedPreset" :disabled="isStreaming">
          <option value="hd1280x720">720p (1280x720)</option>
          <option value="hd1920x1080">1080p (1920x1080)</option>
          <option value="hd4K3840x2160">4K (3840x2160)</option>
        </select>
      </div>

      <div class="field">
        <label>Initial Hardware Lens:</label>
        <select v-model="selectedLens" :disabled="isStreaming">
          <option value="Wide">Wide Angle</option>
          <option value="UltraWide">Ultra Wide</option>
          <option value="Telephoto">Telephoto</option>
        </select>
      </div>

      <div class="button-group">
        <button v-if="!isStreaming" class="btn-primary" :disabled="isLoading" @click="handleStartSession">
          Start Native Camera Session
        </button>
        <button v-else class="btn-danger" :disabled="isLoading" @click="handleStopSession">
          Stop Session
      </button>
      </div>
    </section>

    <!-- 2. Dynamic Hardware Controls -->
    <section class="card" :class="{ disabled: !isStreaming }">
      <h2>2. Live Hardware Controls</h2>
      
      <div class="field">
        <label>Switch Lens Hardware:</label>
        <select v-model="selectedLens" :disabled="!isStreaming">
          <option value="Wide">Wide Angle</option>
          <option value="UltraWide">Ultra Wide</option>
          <option value="Telephoto">Telephoto</option>
        </select>
      </div>

      <div class="field">
        <label>Digital Zoom ({{ zoomValue }}x):</label>
        <input 
          v-model.number="zoomValue" 
          type="range" 
          min="1.0" 
          max="8.0" 
          step="0.1" 
          :disabled="!isStreaming"
        />
      </div>

      <div class="field">
        <label>ISO Speed ({{ isoValue }}):</label>
        <input 
          v-model.number="isoValue" 
          type="range" 
          min="50" 
          max="1200" 
          step="10" 
          :disabled="!isStreaming"
        />
      </div>

      <div class="field">
        <label>Shutter Duration ({{ shutterSpeed }}s):</label>
        <input 
          v-model.number="shutterSpeed" 
          type="range" 
          min="0.0005" 
          max="0.1" 
          step="0.0005" 
          :disabled="!isStreaming"
        />
      </div>

      <button class="btn-secondary" :disabled="isLoading || !isStreaming" @click="handleApplySettings">
        Apply Live Controls
      </button>
    </section>

    <!-- 3. Bridge Test & Debugging Output -->
    <section class="card">
      <h2>3. Diagnostics</h2>
      <button class="btn-outline" :disabled="isLoading" @click="handleTestBridge">
        Test Native Bridge Callback
      </button>

      <div class="status-box">
        <p><strong>Status:</strong> {{ statusMessage || 'Ready' }}</p>
        <pre v-if="lastResponse"><strong>Payload:</strong> {{ JSON.stringify(lastResponse, null, 2) }}</pre>
      </div>
    </section>
  </main>
</template>

<style scoped>
/* Glassmorphism styling to allow the native camera preview layer to show through */
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

h1 {
  font-size: 1.25rem;
  margin: 0;
  text-shadow: 0 1px 3px rgba(0, 0, 0, 0.8);
}

h2 {
  font-size: 1rem;
  margin-top: 0;
  margin-bottom: 0.75rem;
  border-bottom: 1px solid rgba(255, 255, 255, 0.2);
  padding-bottom: 0.4rem;
}

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
  transition: opacity 0.3s ease;
}

.card.disabled {
  opacity: 0.5;
}

.field {
  display: flex;
  flex-direction: column;
  margin-bottom: 0.75rem;
}

label {
  font-size: 0.85rem;
  margin-bottom: 0.25rem;
  color: #dddddd;
}

select, input {
  padding: 0.5rem;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.3);
  background: rgba(255, 255, 255, 0.1);
  color: #fff;
  font-size: 0.95rem;
}

select option {
  background: #222;
  color: #fff;
}

button {
  width: 100%;
  padding: 0.65rem 1rem;
  font-size: 0.95rem;
  font-weight: 600;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  transition: background 0.2s;
}

.button-group {
  display: flex;
  gap: 0.5rem;
}

.btn-primary {
  background: #007aff;
  color: white;
}

.btn-danger {
  background: #ff3b30;
  color: white;
}

.btn-secondary {
  background: #34c759;
  color: white;
}

.btn-outline {
  background: transparent;
  border: 1px solid rgba(255, 255, 255, 0.4);
  color: white;
}

button:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

.status-box {
  margin-top: 0.75rem;
  font-size: 0.85rem;
}

pre {
  background: rgba(0, 0, 0, 0.5);
  padding: 0.5rem;
  border-radius: 6px;
  overflow-x: auto;
  font-size: 0.75rem;
  color: #34c759;
}
</style>