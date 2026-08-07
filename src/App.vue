<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue';
import { useCamera } from './composables/useCamera';

const {
  statusMessage,
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

// HUD Visibility toggles
const activePanel = ref(null);   // 'network' | 'preset' | 'stats'
const activeControl = ref(null); // 'lens' | 'zoom' | 'iso' | 'shutter' | 'focus' | 'wb'

// HACK: just css transform UI, until we modify AVCaptureVideoPreviewLayer orientation properly
const hudLandscape = ref(false);

let statsInterval = null;
let removeListeners = null;

// Dynamic device range compute helpers
const minISO = computed(() => deviceCapabilities.value?.minISO || 50);
const maxISO = computed(() => deviceCapabilities.value?.maxISO || 1200);
const minShutter = computed(() => deviceCapabilities.value?.minShutter || 0.0005);
const maxShutter = computed(() => deviceCapabilities.value?.maxShutter || 0.1);
const maxZoom = computed(() => deviceCapabilities.value?.maxZoom || 8.0);

function togglePanel(panel) {
  activePanel.value = activePanel.value === panel ? null : panel;
  activeControl.value = null;
}

function toggleControl(control) {
  activeControl.value = activeControl.value === control ? null : control;
  activePanel.value = null;
}

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
  activePanel.value = null;
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
  activePanel.value = null;
}

onMounted(() => {
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
  <div class="camera-hud" :class="{ 'hud-landscape': hudLandscape }" @click.self="activePanel = null">
    <!-- Top Status & Quick Flyouts Bar -->
    <header class="top-bar">
      <div class="top-bar-left">
        <!-- Network Connection Flyout Toggle -->
        <button
            class="hud-pill"
            :class="{ active: wsConnected, open: activePanel === 'network' }"
            @click="togglePanel('network')"
        >
          <svg class="icon" viewBox="0 0 24 24">
            <path fill="currentColor" d="M12 3C6.95 3 2.59 5.8 0 10c2.59 4.2 6.95 7 12 7s9.41-2.8 12-7c-2.59-4.2-6.95-7-12-7zm0 11.5c-2.48 0-4.5-2.02-4.5-4.5S9.52 5.5 12 5.5s4.5 2.02 4.5 4.5-2.02 4.5-4.5 4.5z"/>
          </svg>
          <span class="pill-dot" :class="{ connected: wsConnected }"></span>
          <span>{{ wsConnected ? 'NET ONLINE' : 'NET OFFLINE' }}</span>
        </button>

        <!-- Stream Preset & Bitrate Flyout Toggle -->
        <button
            class="hud-pill"
            :class="{ active: isStreaming, open: activePanel === 'preset' }"
            @click="togglePanel('preset')"
        >
          <svg class="icon" viewBox="0 0 24 24">
            <path fill="currentColor" d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z"/>
          </svg>
          <span>{{ selectedPreset.replace('hd', '') }} / {{ (targetBitrate / 1000000).toFixed(0) }}M</span>
        </button>
      </div>

      <div class="top-bar-right">
        <!-- Encoder Stats Flyout Toggle -->
        <button
            v-if="isStreaming"
            class="hud-pill icon-only"
            :class="{ open: activePanel === 'stats' }"
            @click="togglePanel('stats')"
            title="Hardware Stats"
        >
          <svg class="icon" viewBox="0 0 24 24">
            <path fill="currentColor" d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-7 14h-2v-4h2v4zm0-6h-2V7h2v4zm4 6h-2V9h2v8zm0-10h-2V7h2v2z"/>
          </svg>
        </button>
      </div>
    </header>

    <!-- Status Toast Notification -->
    <transition name="fade">
      <div v-if="statusMessage" class="status-toast">
        {{ statusMessage }}
      </div>
    </transition>

    <!-- POPUP PANELS -->
    <!-- 1. Network Setup Flyout -->
    <transition name="slide-down">
      <div v-if="activePanel === 'network'" class="flyout-card">
        <div class="flyout-header">
          <h3>Desktop Network Target</h3>
          <button class="close-btn" @click="activePanel = null">✕</button>
        </div>
        <div class="field-row">
          <input v-model="desktopIp" type="text" placeholder="IP Address" :disabled="wsConnected"/>
          <input v-model.number="desktopPort" type="number" placeholder="Port" class="port-input" :disabled="wsConnected"/>
        </div>
        <button
            :class="wsConnected ? 'btn-danger' : 'btn-primary'"
            :disabled="isLoading"
            @click="handleToggleWebSocket"
        >
          {{ wsConnected ? 'Disconnect Desktop' : 'Connect Desktop Server' }}
        </button>
      </div>
    </transition>

    <!-- 2. Capture Preset & Bitrate Flyout -->
    <transition name="slide-down">
      <div v-if="activePanel === 'preset'" class="flyout-card">
        <div class="flyout-header">
          <h3>Capture & Encoding Quality</h3>
          <button class="close-btn" @click="activePanel = null">✕</button>
        </div>
        <div class="field-group">
          <label>Resolution Preset</label>
          <select v-model="selectedPreset" :disabled="isStreaming">
            <option value="hd1280x720">720p (1280x720)</option>
            <option value="hd1920x1080">1080p (1920x1080)</option>
            <option value="hd4K3840x2160">4K (3840x2160)</option>
          </select>
        </div>
        <div class="field-group">
          <label>Bitrate</label>
          <select v-model.number="targetBitrate">
            <option :value="2000000">2 Mbps</option>
            <option :value="4000000">4 Mbps</option>
            <option :value="8000000">8 Mbps</option>
            <option :value="15000000">15 Mbps</option>
          </select>
        </div>
        <button v-if="isStreaming" class="btn-secondary" :disabled="isLoading" @click="handleUpdateEncoder">
          Update Bitrate
        </button>
      </div>
    </transition>

    <!-- 3. Encoder Stats Flyout -->
    <transition name="slide-down">
      <div v-if="activePanel === 'stats' && encoderStats" class="flyout-card">
        <div class="flyout-header">
          <h3>Encoder Metrics</h3>
          <button class="close-btn" @click="activePanel = null">✕</button>
        </div>
        <div class="metrics-grid">
          <div class="metric">
            <span class="metric-label">Frames</span>
            <span class="metric-value">{{ encoderStats.encodedFrames }}</span>
          </div>
          <div class="metric">
            <span class="metric-label">Keyframes</span>
            <span class="metric-value">{{ encoderStats.keyFrames }}</span>
          </div>
          <div class="metric">
            <span class="metric-label">Last NALU</span>
            <span class="metric-value">{{ (encoderStats.lastFrameBytes / 1024).toFixed(1) }} KB</span>
          </div>
          <div class="metric">
            <span class="metric-label">Current Bitrate</span>
            <span class="metric-value">{{ (encoderStats.bitrate / 1000000).toFixed(1) }} Mbps</span>
          </div>
        </div>
      </div>
    </transition>

    <!-- FLOATING SLIDER/CONTROL TRAY (Opens above bottom controls) -->
    <transition name="slide-up">
      <div v-if="activeControl" class="slider-tray">
        <!-- Lens Switcher -->
        <div v-if="activeControl === 'lens'" class="tray-content">
          <span class="tray-title">Select Physical Lens</span>
          <div class="segmented-control">
            <button
                v-for="lens in ['Wide', 'UltraWide', 'Telephoto']"
                :key="lens"
                :class="{ selected: selectedLens === lens }"
                @click="selectedLens = lens; handleApplyCameraSettings()"
            >
              {{ lens }}
            </button>
          </div>
        </div>

        <!-- Zoom Slider -->
        <div v-if="activeControl === 'zoom'" class="tray-content">
          <div class="tray-header">
            <span>Digital Zoom</span>
            <strong>{{ zoomValue.toFixed(1) }}x</strong>
          </div>
          <input v-model.number="zoomValue" type="range" min="1.0" :max="maxZoom" step="0.1" @input="handleApplyCameraSettings"/>
        </div>

        <!-- ISO Slider -->
        <div v-if="activeControl === 'iso'" class="tray-content">
          <div class="tray-header">
            <span>ISO Sensitivity</span>
            <strong>ISO {{ isoValue }}</strong>
          </div>
          <input v-model.number="isoValue" type="range" :min="minISO" :max="maxISO" step="5" @input="handleApplyCameraSettings"/>
        </div>

        <!-- Shutter Speed Slider -->
        <div v-if="activeControl === 'shutter'" class="tray-content">
          <div class="tray-header">
            <span>Shutter Speed</span>
            <strong>1/{{ Math.round(1 / shutterSpeed) }}s</strong>
          </div>
          <input v-model.number="shutterSpeed" type="range" :min="minShutter" :max="maxShutter" step="0.0005" @input="handleApplyCameraSettings"/>
        </div>

        <!-- Focus Distance & Mode -->
        <div v-if="activeControl === 'focus'" class="tray-content">
          <div class="tray-header">
            <span>Focus Mode</span>
            <button class="toggle-btn" @click="handleToggleFocusMode">
              {{ focusMode === 'continuous' ? 'AUTO' : 'MANUAL' }}
            </button>
          </div>
          <input
              v-if="focusMode === 'locked'"
              v-model.number="focusValue"
              type="range"
              min="0.0"
              max="1.0"
              step="0.01"
              @input="handleApplyCameraSettings"
          />
        </div>

        <!-- White Balance (Kelvin & Tint) -->
        <div v-if="activeControl === 'wb'" class="tray-content">
          <div class="tray-header">
            <span>White Balance</span>
            <button class="toggle-btn" @click="handleToggleWBMode">
              {{ wbMode === 'continuous' ? 'AUTO' : 'MANUAL' }}
            </button>
          </div>
          <template v-if="wbMode === 'locked'">
            <div class="sub-slider">
              <label>Temp: {{ wbTemperature }}K</label>
              <input v-model.number="wbTemperature" type="range" min="2500" max="9000" step="50" @input="handleApplyCameraSettings"/>
            </div>
            <div class="sub-slider">
              <label>Tint: {{ wbTint }}</label>
              <input v-model.number="wbTint" type="range" min="-100" max="100" step="1" @input="handleApplyCameraSettings"/>
            </div>
          </template>
        </div>
      </div>
    </transition>

    <!-- Bottom Camera Control Edge & Shutter Button -->
    <footer class="bottom-bar">
      <!-- Main Shutter / Stream Button -->
      <div class="shutter-wrapper">
        <button
            class="shutter-btn"
            :class="{ streaming: isStreaming }"
            :disabled="isLoading"
            @click="isStreaming ? handleStopSession() : handleStartSession()"
        >
          <div class="shutter-inner"></div>
        </button>
      </div>
      <!-- Camera Settings Pills Row -->
      <div class="controls-scroll" :class="{ disabled: !isStreaming }">
        <button
            class="param-pill"
            :class="{ active: activeControl === 'lens' }"
            :disabled="!isStreaming"
            @click="toggleControl('lens')"
        >
          <span class="param-label">LENS</span>
          <span class="param-val">{{ selectedLens }}</span>
        </button>

        <button
            class="param-pill"
            :class="{ active: activeControl === 'zoom' }"
            :disabled="!isStreaming"
            @click="toggleControl('zoom')"
        >
          <span class="param-label">ZOOM</span>
          <span class="param-val">{{ zoomValue.toFixed(1) }}x</span>
        </button>

        <button
            class="param-pill"
            :class="{ active: activeControl === 'iso' }"
            :disabled="!isStreaming"
            @click="toggleControl('iso')"
        >
          <span class="param-label">ISO</span>
          <span class="param-val">{{ isoValue }}</span>
        </button>

        <button
            class="param-pill"
            :class="{ active: activeControl === 'shutter' }"
            :disabled="!isStreaming"
            @click="toggleControl('shutter')"
        >
          <span class="param-label">SHUTTER</span>
          <span class="param-val">1/{{ Math.round(1 / shutterSpeed) }}s</span>
        </button>

        <button
            class="param-pill"
            :class="{ active: activeControl === 'focus' }"
            :disabled="!isStreaming"
            @click="toggleControl('focus')"
        >
          <span class="param-label">FOCUS</span>
          <span class="param-val">{{ focusMode === 'continuous' ? 'AF' : focusValue.toFixed(2) }}</span>
        </button>

        <button
            class="param-pill"
            :class="{ active: activeControl === 'wb' }"
            :disabled="!isStreaming"
            @click="toggleControl('wb')"
        >
          <span class="param-label">WB</span>
          <span class="param-val">{{ wbMode === 'continuous' ? 'AWB' : wbTemperature + 'K' }}</span>
        </button>
      </div>
      
      <!-- Orientation Button -->
      <div class="orientation-wrapper" @click="hudLandscape = !hudLandscape">
        <svg fill="#ffffff" height="32px" width="32px" viewBox="0 0 214.367 214.367" xml:space="preserve">
          <g stroke-width="0"></g><g stroke-linecap="round" stroke-linejoin="round"></g>
          <g><path d="M202.403,95.22c0,46.312-33.237,85.002-77.109,93.484v25.663l-69.76-40l69.76-40v23.494 c27.176-7.87,47.109-32.964,47.109-62.642c0-35.962-29.258-65.22-65.22-65.22s-65.22,29.258-65.22,65.22 c0,9.686,2.068,19.001,6.148,27.688l-27.154,12.754c-5.968-12.707-8.994-26.313-8.994-40.441C11.964,42.716,54.68,0,107.184,0 S202.403,42.716,202.403,95.22z"></path></g>
        </svg>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.camera-hud {
  position: relative;
  width: 100vw;
  height: 100vh;
  box-sizing: border-box;
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", Roboto, sans-serif;
  color: #ffffff;
  user-select: none;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.camera-hud.hud-landscape {
  transform: rotate(90deg);
  transform-origin: top left;
  width: 100vh;
  height: 100vw;
  position: absolute;
  top: 0;
  left: 100%;
  overflow-x: hidden;
}

/* TOP BAR */
.top-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 40px 12px 16px;
  background: linear-gradient(to bottom, rgba(0,0,0,0.6), transparent);
  z-index: 20;
}
.hud-landscape .top-bar {
  padding: 12px 16px;
}

.top-bar-left, .top-bar-right {
  display: flex;
  gap: 8px;
  align-items: center;
}

.hud-pill {
  display: flex;
  align-items: center;
  gap: 6px;
  background: rgba(0, 0, 0, 0.45);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  color: #fff;
  padding: 6px 12px;
  border-radius: 20px;
  font-size: 0.72rem;
  font-weight: 600;
  letter-spacing: 0.5px;
  cursor: pointer;
}

.hud-pill.icon-only {
  padding: 6px;
  border-radius: 50%;
}

.hud-pill.open {
  border-color: #007aff;
  background: rgba(0, 122, 255, 0.25);
}

.icon {
  width: 14px;
  height: 14px;
}

.pill-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: #ff3b30;
}

.pill-dot.connected {
  background: #34c759;
}

/* STATUS TOAST */
.status-toast {
  position: absolute;
  top: 80px;
  left: 50%;
  transform: translateX(-50%);
  background: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(10px);
  padding: 6px 16px;
  border-radius: 16px;
  font-size: 0.75rem;
  color: #34c759;
  border: 1px solid rgba(255, 255, 255, 0.15);
  z-index: 15;
  pointer-events: none;
}
.hud-landscape .status-toast {
  top: 60px;
}

/* FLYOUT POPUP CARDS */
.flyout-card {
  position: absolute;
  top: 60px;
  left: 16px;
  right: 16px;
  max-width: 360px;
  margin: 0 auto;
  background: rgba(18, 18, 20, 0.85);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 16px;
  padding: 14px;
  z-index: 30;
  box-shadow: 0 8px 32px rgba(0,0,0,0.5);
}

.flyout-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
}

.flyout-header h3 {
  font-size: 0.85rem;
  margin: 0;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #aaa;
}

.close-btn {
  background: transparent;
  border: none;
  color: #aaa;
  font-size: 1rem;
  cursor: pointer;
}

.field-row {
  display: flex;
  gap: 8px;
  margin-bottom: 10px;
}

.field-group {
  display: flex;
  flex-direction: column;
  margin-bottom: 10px;
}

.field-group label {
  font-size: 0.7rem;
  color: #888;
  margin-bottom: 4px;
}

input, select {
  width: 100%;
  padding: 8px 10px;
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.2);
  background: rgba(255, 255, 255, 0.1);
  color: #fff;
  font-size: 0.85rem;
  box-sizing: border-box;
}

.port-input {
  width: 90px;
}

/* TRAY CONTROLLER OVERLAY */
.slider-tray {
  position: absolute;
  bottom: 135px;
  left: 16px;
  right: 16px;
  max-width: 400px;
  margin: 0 auto;
  background: rgba(18, 18, 20, 0.85);
  backdrop-filter: blur(20px);
  -webkit-backdrop-filter: blur(20px);
  border: 1px solid rgba(255, 255, 255, 0.2);
  border-radius: 16px;
  padding: 12px 16px;
  z-index: 25;
}

.tray-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
  font-size: 0.8rem;
  color: #ddd;
}

.toggle-btn {
  background: #007aff;
  color: #fff;
  border: none;
  padding: 3px 8px;
  border-radius: 6px;
  font-size: 0.7rem;
  font-weight: bold;
}

.sub-slider {
  margin-top: 8px;
  font-size: 0.75rem;
}

.segmented-control {
  display: flex;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 8px;
  padding: 2px;
  gap: 2px;
}

.segmented-control button {
  flex: 1;
  background: transparent;
  border: none;
  color: #ccc;
  padding: 6px;
  font-size: 0.75rem;
  border-radius: 6px;
}

.segmented-control button.selected {
  background: rgba(255, 255, 255, 0.25);
  color: #fff;
  font-weight: bold;
}

/* BOTTOM BAR & CONTROLS */
.bottom-bar {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding-bottom: 24px;
  background: linear-gradient(to top, rgba(0,0,0,0.7), transparent);
  z-index: 20;
}

.controls-scroll {
  display: flex;
  gap: 8px;
  overflow-x: auto;
  padding: 10px 16px;
  width: 100%;
  box-sizing: border-box;
  justify-content: center;
}

.controls-scroll.disabled {
  opacity: 0.4;
  pointer-events: none;
}

.param-pill {
  display: flex;
  flex-direction: column;
  align-items: center;
  background: rgba(0, 0, 0, 0.45);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.15);
  border-radius: 10px;
  padding: 6px 10px;
  min-width: 58px;
  cursor: pointer;
}

.param-pill.active {
  border-color: #007aff;
  background: rgba(0, 122, 255, 0.2);
}

.param-label {
  font-size: 0.55rem;
  color: #aaa;
  letter-spacing: 0.5px;
}

.param-val {
  font-size: 0.75rem;
  font-weight: 700;
  color: #fff;
  margin-top: 2px;
}

/* SHUTTER / RECORD BUTTON */
.shutter-wrapper {
  margin-top: 6px;
}

.shutter-btn {
  width: 64px;
  height: 64px;
  border-radius: 50%;
  border: 4px solid #ffffff;
  background: transparent;
  padding: 3px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
}

.shutter-inner {
  width: 100%;
  height: 100%;
  border-radius: 50%;
  background: #ff3b30;
  transition: all 0.2s ease;
}

.shutter-btn.streaming .shutter-inner {
  border-radius: 6px;
  width: 50%;
  height: 50%;
}

.orientation-wrapper {
  position: absolute;
  bottom: 85px;
  right: 10px;
  background: transparent;
}

/* BUTTON STYLES */
.btn-primary { background: #007aff; color: white; border: none; padding: 8px; border-radius: 8px; font-weight: bold; width: 100%; }
.btn-danger { background: #ff3b30; color: white; border: none; padding: 8px; border-radius: 8px; font-weight: bold; width: 100%; }
.btn-secondary { background: #34c759; color: white; border: none; padding: 8px; border-radius: 8px; font-weight: bold; width: 100%; }

.metrics-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; }
.metric { background: rgba(255, 255, 255, 0.08); padding: 8px; border-radius: 8px; text-align: center; }
.metric-label { display: block; font-size: 0.65rem; color: #aaa; }
.metric-value { display: block; font-size: 0.95rem; font-weight: bold; color: #34c759; margin-top: 2px; }

/* TRANSITIONS */
.fade-enter-active, .fade-leave-active { transition: opacity 0.3s; }
.fade-enter-from, .fade-leave-to { opacity: 0; }

.slide-down-enter-active, .slide-down-leave-active,
.slide-up-enter-active, .slide-up-leave-active {
  transition: all 0.25s ease-out;
}
.slide-down-enter-from, .slide-down-leave-to { opacity: 0; transform: translateY(-10px); }
.slide-up-enter-from, .slide-up-leave-to { opacity: 0; transform: translateY(10px); }
</style>