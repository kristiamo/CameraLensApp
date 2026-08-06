<script setup>
import { ref } from 'vue';
import { useCamera } from './composables/useCamera';

const { statusMessage, lastResponse, isLoading, testNativeCode, setManualLensSettings } = useCamera();

const selectedLens = ref('Wide');
const isoValue = ref(100);
const shutterSpeed = ref(0.02);

async function handleTestBridge() {
  await testNativeCode('Test message from App.vue');
}

async function handleConfigureLens() {
  await setManualLensSettings(isoValue.value, shutterSpeed.value, selectedLens.value);
}
</script>

<template>
  <main class="container">
    <h1>Camera Lens Bridge Test</h1>

    <section class="card">
      <h2>1. Test Native Bridge</h2>
      <button :disabled="isLoading" @click="handleTestBridge">
        Run deviceAction()
      </button>
    </section>

    <section class="card">
      <h2>2. Configure Lens Settings</h2>
      <div class="field">
        <label>Lens Type:</label>
        <select v-model="selectedLens">
          <option value="Wide">Wide Angle</option>
          <option value="UltraWide">Ultra Wide</option>
          <option value="Telephoto">Telephoto</option>
        </select>
      </div>

      <div class="field">
        <label>ISO ({{ isoValue }}):</label>
        <input v-model.number="isoValue" type="range" min="50" max="800" step="10" />
      </div>

      <div class="field">
        <label>Shutter Speed ({{ shutterSpeed }}s):</label>
        <input v-model.number="shutterSpeed" type="range" min="0.001" max="0.1" step="0.001" />
      </div>

      <button :disabled="isLoading" @click="handleConfigureLens">
        Apply Lens Configuration
      </button>
    </section>

    <section class="card status">
      <h2>Status</h2>
      <p><strong>Message:</strong> {{ statusMessage || 'Ready' }}</p>
      <pre v-if="lastResponse"><strong>Raw Result:</strong> {{ JSON.stringify(lastResponse, null, 2) }}</pre>
    </section>
  </main>
</template>

<style scoped>
.container {
  max-width: 500px;
  margin: 0 auto;
  padding: 1rem;
  font-family: sans-serif;
}

.card {
  border: 1px solid #ccc;
  border-radius: 8px;
  padding: 1rem;
  margin-bottom: 1rem;
}

.field {
  display: flex;
  flex-direction: column;
  margin-bottom: 0.75rem;
}

button {
  padding: 0.5rem 1rem;
  font-size: 1rem;
  cursor: pointer;
}

pre {
  background: #f4f4f4;
  padding: 0.5rem;
  border-radius: 4px;
  overflow-x: auto;
}
</style>