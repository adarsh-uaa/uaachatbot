import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(__dirname, '../public/sounds');
fs.mkdirSync(outDir, { recursive: true });

const SAMPLE_RATE = 44100;

function createWavBuffer(samples) {
  const byteRate = SAMPLE_RATE * 2;
  const blockAlign = 2;
  const dataSize = samples.length * 2;
  const buffer = Buffer.alloc(44 + dataSize);

  // RIFF header
  buffer.write('RIFF', 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write('WAVE', 8);

  // fmt chunk
  buffer.write('fmt ', 12);
  buffer.writeUInt32LE(16, 16); // subchunk1 size (16 for PCM)
  buffer.writeUInt16LE(1, 20);  // audio format (1 = PCM)
  buffer.writeUInt16LE(1, 22);  // num channels (1 = mono)
  buffer.writeUInt32LE(SAMPLE_RATE, 24);
  buffer.writeUInt32LE(byteRate, 28);
  buffer.writeUInt16LE(blockAlign, 32);
  buffer.writeUInt16LE(16, 34); // bits per sample

  // data chunk
  buffer.write('data', 36);
  buffer.writeUInt32LE(dataSize, 40);

  // Write 16-bit PCM samples
  let offset = 44;
  for (let i = 0; i < samples.length; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    const intVal = s < 0 ? s * 0x8000 : s * 0x7FFF;
    buffer.writeInt16LE(Math.floor(intVal), offset);
    offset += 2;
  }

  return buffer;
}

// 1. Tawk.to Style Telephone Ring (~0.95s total)
function generateTawk() {
  const totalDuration = 0.95;
  const numSamples = Math.floor(SAMPLE_RATE * totalDuration);
  const samples = new Float32Array(numSamples);

  const bursts = [
    { start: 0, duration: 0.32 },
    { start: 0.40, duration: 0.42 }
  ];

  bursts.forEach(({ start, duration }) => {
    const startSample = Math.floor(start * SAMPLE_RATE);
    const endSample = Math.floor((start + duration) * SAMPLE_RATE);
    let phase = 0;

    for (let i = startSample; i < endSample; i++) {
      const t = (i - startSample) / SAMPLE_RATE;
      // 24Hz square wave frequency modulation between ~940Hz and ~1160Hz
      const lfo = Math.sin(2 * Math.PI * 24 * t) >= 0 ? 1 : -1;
      const freq = 1050 + lfo * 110;
      phase += (2 * Math.PI * freq) / SAMPLE_RATE;

      // Sawtooth-like richness + crisp punch
      let wave = 0.7 * Math.sin(phase) + 0.3 * Math.sin(phase * 2);

      // Amplitude envelope
      let env = 1;
      if (t < 0.02) env = t / 0.02;
      else if (t > duration - 0.04) env = Math.max(0, (duration - t) / 0.04);

      samples[i] = wave * env * 0.9;
    }
  });

  return createWavBuffer(samples);
}

// 2. High-Energy Siren (~0.7s total)
function generateSiren() {
  const totalDuration = 0.70;
  const numSamples = Math.floor(SAMPLE_RATE * totalDuration);
  const samples = new Float32Array(numSamples);

  const tones = [
    { freq: 960, start: 0, dur: 0.16 },
    { freq: 720, start: 0.16, dur: 0.16 },
    { freq: 960, start: 0.32, dur: 0.16 },
    { freq: 720, start: 0.48, dur: 0.18 }
  ];

  tones.forEach(({ freq, start, dur }) => {
    const startSample = Math.floor(start * SAMPLE_RATE);
    const endSample = Math.min(numSamples, Math.floor((start + dur) * SAMPLE_RATE));
    let phase = 0;

    for (let i = startSample; i < endSample; i++) {
      const t = (i - startSample) / SAMPLE_RATE;
      phase += (2 * Math.PI * freq) / SAMPLE_RATE;
      let wave = 0.75 * Math.sin(phase) + 0.25 * Math.sin(3 * phase);
      let env = 1;
      if (t < 0.01) env = t / 0.01;
      else if (t > dur - 0.02) env = Math.max(0, (dur - t) / 0.02);

      samples[i] = wave * env * 0.85;
    }
  });

  return createWavBuffer(samples);
}

// 3. Ascending Radar Sweep (~0.45s)
function generateRadar() {
  const totalDuration = 0.45;
  const numSamples = Math.floor(SAMPLE_RATE * totalDuration);
  const samples = new Float32Array(numSamples);
  let phase = 0;

  for (let i = 0; i < numSamples; i++) {
    const t = i / SAMPLE_RATE;
    if (t > 0.38) break;
    // Exponential frequency sweep: 650Hz to 1850Hz
    const freq = 650 * Math.pow(1850 / 650, t / 0.35);
    phase += (2 * Math.PI * freq) / SAMPLE_RATE;
    let wave = Math.sin(phase);
    let env = 1;
    if (t < 0.01) env = t / 0.01;
    else if (t > 0.30) env = Math.max(0, (0.38 - t) / 0.08);

    samples[i] = wave * env * 0.9;
  }

  return createWavBuffer(samples);
}

// 4. Airport Boarding Chime (~0.7s)
function generateChime() {
  const totalDuration = 0.70;
  const numSamples = Math.floor(SAMPLE_RATE * totalDuration);
  const samples = new Float32Array(numSamples);

  const notes = [
    { freq: 523.25, start: 0, dur: 0.45 },
    { freq: 659.25, start: 0.13, dur: 0.45 },
    { freq: 783.99, start: 0.26, dur: 0.44 }
  ];

  notes.forEach(({ freq, start, dur }) => {
    const startSample = Math.floor(start * SAMPLE_RATE);
    const endSample = Math.min(numSamples, Math.floor((start + dur) * SAMPLE_RATE));
    let phase = 0;

    for (let i = startSample; i < endSample; i++) {
      const t = (i - startSample) / SAMPLE_RATE;
      phase += (2 * Math.PI * freq) / SAMPLE_RATE;
      let wave = Math.sin(phase) + 0.2 * Math.sin(2 * phase);
      // Exponential decay envelope
      let env = Math.exp(-t * 5);
      if (t < 0.01) env *= (t / 0.01);

      samples[i] += wave * env * 0.55;
    }
  });

  return createWavBuffer(samples);
}

// 5. Crisp Double Beep (~0.35s)
function generateBeep() {
  const totalDuration = 0.35;
  const numSamples = Math.floor(SAMPLE_RATE * totalDuration);
  const samples = new Float32Array(numSamples);

  const beeps = [
    { start: 0, dur: 0.09 },
    { start: 0.12, dur: 0.09 }
  ];

  beeps.forEach(({ start, dur }) => {
    const startSample = Math.floor(start * SAMPLE_RATE);
    const endSample = Math.min(numSamples, Math.floor((start + dur) * SAMPLE_RATE));
    let phase = 0;

    for (let i = startSample; i < endSample; i++) {
      const t = (i - startSample) / SAMPLE_RATE;
      phase += (2 * Math.PI * 920) / SAMPLE_RATE;
      let wave = Math.sin(phase) + 0.3 * Math.sin(3 * phase);
      let env = 1;
      if (t < 0.005) env = t / 0.005;
      else if (t > dur - 0.01) env = Math.max(0, (dur - t) / 0.01);

      samples[i] = wave * env * 0.85;
    }
  });

  return createWavBuffer(samples);
}

// 6. Silent Keep-Alive Stream (0.5s of absolute zero samples)
function generateSilent() {
  const totalDuration = 0.5;
  const numSamples = Math.floor(SAMPLE_RATE * totalDuration);
  const samples = new Float32Array(numSamples);
  return createWavBuffer(samples);
}

fs.writeFileSync(path.join(outDir, 'tawk.wav'), generateTawk());
fs.writeFileSync(path.join(outDir, 'siren.wav'), generateSiren());
fs.writeFileSync(path.join(outDir, 'radar.wav'), generateRadar());
fs.writeFileSync(path.join(outDir, 'chime.wav'), generateChime());
fs.writeFileSync(path.join(outDir, 'beep.wav'), generateBeep());
fs.writeFileSync(path.join(outDir, 'silent.wav'), generateSilent());

console.log('Successfully generated alarm WAV sounds in', outDir);

