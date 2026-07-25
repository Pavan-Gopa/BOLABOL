/**
 * Procedural Meditative Sound Engine using the Web Audio API
 * Generates endless ambient soundscapes without loading heavy audio assets.
 */

export class AmbientSoundscape {
  private ctx: AudioContext | null = null;
  private masterGain: GainNode | null = null;
  private isPlaying: boolean = false;
  private volume: number = 0.5; // 0 to 1
  private isMuted: boolean = false;
  private currentMood: 'cosmic' | 'forest' | 'meditation' | 'wind' = 'cosmic';

  // Active audio nodes for cleanup
  private activeNodes: AudioNode[] = [];
  private chimeTimer: any = null;
  private noiseTimer: any = null;

  constructor() {
    // AudioContext will be initialized on first user interaction
  }

  private initContext() {
    if (!this.ctx) {
      // @ts-ignore
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      this.ctx = new AudioCtx();
      
      this.masterGain = this.ctx.createGain();
      this.masterGain.gain.setValueAtTime(this.volume, this.ctx.currentTime);
      this.masterGain.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') {
      this.ctx.resume();
    }
  }

  public setVolume(vol: number) {
    this.volume = Math.max(0, Math.min(1, vol));
    if (this.masterGain && !this.isMuted) {
      this.masterGain.gain.setTargetAtTime(this.volume, this.ctx?.currentTime || 0, 0.1);
    }
  }

  public getVolume(): number {
    return this.volume;
  }

  public toggleMute(): boolean {
    this.isMuted = !this.isMuted;
    if (this.masterGain) {
      const targetVol = this.isMuted ? 0 : this.volume;
      this.masterGain.gain.setTargetAtTime(targetVol, this.ctx?.currentTime || 0, 0.1);
    }
    return this.isMuted;
  }

  public getMutedState(): boolean {
    return this.isMuted;
  }

  public getIsPlaying(): boolean {
    return this.isPlaying;
  }

  public getCurrentMood(): string {
    return this.currentMood;
  }

  public play(mood: 'cosmic' | 'forest' | 'meditation' | 'wind') {
    this.initContext();
    if (!this.ctx || !this.masterGain) return;

    this.stop();
    this.currentMood = mood;
    this.isPlaying = true;

    if (mood === 'cosmic') {
      this.startCosmicSwell();
    } else if (mood === 'forest') {
      this.startForestZen();
    } else if (mood === 'meditation') {
      this.startDeepMeditation();
    } else if (mood === 'wind') {
      this.startAetherWind();
    }
  }

  public stop() {
    // Clear chime scheduler
    if (this.chimeTimer) {
      clearInterval(this.chimeTimer);
      this.chimeTimer = null;
    }
    if (this.noiseTimer) {
      clearInterval(this.noiseTimer);
      this.noiseTimer = null;
    }

    // Stop and disconnect all active nodes
    this.activeNodes.forEach(node => {
      try {
        // If node is an source, stop it
        if ('stop' in node) {
          (node as any).stop();
        }
        node.disconnect();
      } catch (e) {
        // already stopped or not startable
      }
    });
    this.activeNodes = [];
    this.isPlaying = false;
  }

  /**
   * Helper to create a delay effect (Space / Reverb)
   */
  private createDelayEffect(delayTime = 1.2, feedbackVal = 0.5): { input: AudioNode, output: AudioNode } {
    if (!this.ctx || !this.masterGain) throw new Error("Audio Context not initialized");

    const delay = this.ctx.createDelay();
    delay.delayTime.setValueAtTime(delayTime, this.ctx.currentTime);

    const feedback = this.ctx.createGain();
    feedback.gain.setValueAtTime(feedbackVal, this.ctx.currentTime);

    // Create loop
    delay.connect(feedback);
    feedback.connect(delay);

    // Wet/Dry mix
    const mix = this.ctx.createGain();
    mix.gain.setValueAtTime(0.4, this.ctx.currentTime);
    delay.connect(mix);

    this.activeNodes.push(delay, feedback, mix);
    return { input: delay, output: mix };
  }

  /**
   * Play a bell sound with high sine oscillators
   */
  private playBell(frequency: number, duration: number, gainTarget: number, delayInput: AudioNode) {
    if (!this.ctx || !this.masterGain) return;

    const now = this.ctx.currentTime;

    // Bell chime harmonic stack
    const osc1 = this.ctx.createOscillator();
    const osc2 = this.ctx.createOscillator();
    const oscGain = this.ctx.createGain();

    osc1.type = 'sine';
    osc1.frequency.setValueAtTime(frequency, now);

    // High inharmonic tone for metallic bell clang
    osc2.type = 'sine';
    osc2.frequency.setValueAtTime(frequency * 2.76, now);

    // Gain Envelope
    oscGain.gain.setValueAtTime(0, now);
    oscGain.gain.linearRampToValueAtTime(gainTarget, now + 0.05);
    oscGain.gain.exponentialRampToValueAtTime(0.0001, now + duration);

    osc1.connect(oscGain);
    osc2.connect(oscGain);

    // Send to delay and master
    oscGain.connect(this.masterGain);
    oscGain.connect(delayInput);

    osc1.start(now);
    osc2.start(now);
    osc1.stop(now + duration);
    osc2.stop(now + duration);
  }

  /**
   * Cosmic Swell Mood
   * Low pad chords + pentatonic space chimes
   */
  private startCosmicSwell() {
    if (!this.ctx || !this.masterGain) return;
    const now = this.ctx.currentTime;

    // Space Delay for chimes
    const { input: delayInput, output: delayOutput } = this.createDelayEffect(1.5, 0.4);
    delayOutput.connect(this.masterGain);

    // Pad chord frequencies (F Major 7: F2, C3, E3, A3, C4)
    const freqs = [87.31, 130.81, 164.81, 220.00, 261.63];
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.Q.setValueAtTime(1, now);
    filter.connect(this.masterGain);
    this.activeNodes.push(filter);

    // Slow LFO to modulate filter cutoff (breathing effect)
    const lfo = this.ctx.createOscillator();
    const lfoGain = this.ctx.createGain();
    lfo.frequency.setValueAtTime(0.08, now); // very slow
    lfoGain.gain.setValueAtTime(150, now); // cutoff range
    lfo.connect(lfoGain);
    lfoGain.connect(filter.frequency);
    filter.frequency.setValueAtTime(350, now);
    lfo.start(now);
    this.activeNodes.push(lfo, lfoGain);

    // Create drone oscillators
    freqs.forEach((freq, idx) => {
      if (!this.ctx || !this.masterGain) return;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      
      osc.type = idx % 2 === 0 ? 'triangle' : 'sine';
      osc.frequency.setValueAtTime(freq + (Math.random() - 0.5) * 0.5, now); // slight detune
      
      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(0.08 / freqs.length, now + 4); // fade in drone
      
      osc.connect(gain);
      gain.connect(filter);
      
      osc.start(now);
      this.activeNodes.push(osc, gain);
    });

    // Space chimes sequence (Pentatonic scale notes: F5, G5, A5, C6, D6, F6)
    const pentatonic = [698.46, 783.99, 880.00, 1046.50, 1174.66, 1396.91];
    const scheduleNextChime = () => {
      if (!this.isPlaying || this.currentMood !== 'cosmic') return;
      const freq = pentatonic[Math.floor(Math.random() * pentatonic.length)];
      const duration = 4.0 + Math.random() * 3.0;
      const gainTarget = 0.04 + Math.random() * 0.04;
      this.playBell(freq, duration, gainTarget, delayInput);
    };

    // Trigger chimes periodically
    scheduleNextChime();
    this.chimeTimer = setInterval(scheduleNextChime, 3000);
  }

  /**
   * Forest Zen Mood
   * D minor pad, rustling forest wind, bird tines
   */
  private startForestZen() {
    if (!this.ctx || !this.masterGain) return;
    const now = this.ctx.currentTime;

    // Delay for chimes
    const { input: delayInput, output: delayOutput } = this.createDelayEffect(1.0, 0.35);
    delayOutput.connect(this.masterGain);

    // D minor pad frequencies: D2, A2, D3, F3, C4
    const freqs = [73.42, 110.00, 146.83, 174.61, 261.63];
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(250, now);
    filter.connect(this.masterGain);
    this.activeNodes.push(filter);

    freqs.forEach((freq, idx) => {
      if (!this.ctx || !this.masterGain) return;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq + (Math.random() - 0.5) * 0.3, now);
      
      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(0.06 / freqs.length, now + 3);
      
      osc.connect(gain);
      gain.connect(filter);
      osc.start(now);
      this.activeNodes.push(osc, gain);
    });

    // Procedural Wind noise node
    // Generates buffer of white noise
    const bufferSize = 2 * this.ctx.sampleRate;
    const noiseBuffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      output[i] = Math.random() * 2 - 1;
    }

    const noiseSource = this.ctx.createBufferSource();
    noiseSource.buffer = noiseBuffer;
    noiseSource.loop = true;

    const noiseFilter = this.ctx.createBiquadFilter();
    noiseFilter.type = 'bandpass';
    noiseFilter.Q.setValueAtTime(2.0, now);
    
    const noiseGain = this.ctx.createGain();
    noiseGain.gain.setValueAtTime(0, now);
    noiseGain.gain.linearRampToValueAtTime(0.015, now + 4); // soft fade in

    noiseSource.connect(noiseFilter);
    noiseFilter.connect(noiseGain);
    noiseGain.connect(this.masterGain);

    noiseSource.start(now);
    this.activeNodes.push(noiseSource, noiseFilter, noiseGain);

    // Modulate bandpass frequency to simulate gust of wind
    const modulateWind = () => {
      if (!this.isPlaying || this.currentMood !== 'forest') return;
      const windTargetFreq = 200 + Math.random() * 400;
      const windTransitionTime = 3 + Math.random() * 4;
      noiseFilter.frequency.setTargetAtTime(windTargetFreq, this.ctx?.currentTime || 0, windTransitionTime / 3);
    };
    modulateWind();
    this.noiseTimer = setInterval(modulateWind, 5000);

    // Bird chirping bells (D minor pentatonic: D5, F5, G5, A5, C6, D6)
    const pentatonic = [587.33, 698.46, 783.99, 880.00, 1046.50, 1174.66];
    const scheduleNextForestChime = () => {
      if (!this.isPlaying || this.currentMood !== 'forest') return;
      const freq = pentatonic[Math.floor(Math.random() * pentatonic.length)];
      const duration = 2.5 + Math.random() * 2.0;
      const gainTarget = 0.02 + Math.random() * 0.02;
      this.playBell(freq, duration, gainTarget, delayInput);
    };

    scheduleNextForestChime();
    this.chimeTimer = setInterval(scheduleNextForestChime, 4500);
  }

  /**
   * Deep Meditation Mood
   * Binaural Beats (100Hz vs 104Hz for 4Hz Theta waves) + Low Singing Bowl Drone
   */
  private startDeepMeditation() {
    if (!this.ctx || !this.masterGain) return;
    const now = this.ctx.currentTime;

    // 1. Binaural Beat oscillators
    const leftOsc = this.ctx.createOscillator();
    const rightOsc = this.ctx.createOscillator();
    
    const leftGain = this.ctx.createGain();
    const rightGain = this.ctx.createGain();
    
    const merger = this.ctx.createChannelMerger(2);

    leftOsc.type = 'sine';
    leftOsc.frequency.setValueAtTime(100.0, now); // Left channel 100Hz

    rightOsc.type = 'sine';
    rightOsc.frequency.setValueAtTime(104.0, now); // Right channel 104Hz (Theta 4Hz beat)

    leftGain.gain.setValueAtTime(0, now);
    leftGain.gain.linearRampToValueAtTime(0.04, now + 5);

    rightGain.gain.setValueAtTime(0, now);
    rightGain.gain.linearRampToValueAtTime(0.04, now + 5);

    leftOsc.connect(leftGain);
    rightOsc.connect(rightGain);

    // Merge into stereo
    leftGain.connect(merger, 0, 0);
    rightGain.connect(merger, 0, 1);

    merger.connect(this.masterGain);

    leftOsc.start(now);
    rightOsc.start(now);

    this.activeNodes.push(leftOsc, rightOsc, leftGain, rightGain, merger);

    // 2. Singing Bowl Synth (Sub bass + detuned square oscillators with resonating filter)
    const bowlFreq = 110.0; // A2
    const bowlOsc1 = this.ctx.createOscillator();
    const bowlOsc2 = this.ctx.createOscillator();
    const bowlGain = this.ctx.createGain();

    bowlOsc1.type = 'triangle';
    bowlOsc1.frequency.setValueAtTime(bowlFreq, now);

    bowlOsc2.type = 'sine';
    bowlOsc2.frequency.setValueAtTime(bowlFreq * 1.5 + 0.2, now); // Perfect fifth + slight detune

    bowlGain.gain.setValueAtTime(0, now);
    bowlGain.gain.linearRampToValueAtTime(0.08, now + 6);

    const bowlFilter = this.ctx.createBiquadFilter();
    bowlFilter.type = 'lowpass';
    bowlFilter.Q.setValueAtTime(3, now); // resonance peak
    bowlFilter.frequency.setValueAtTime(180, now);

    bowlOsc1.connect(bowlFilter);
    bowlOsc2.connect(bowlFilter);
    bowlFilter.connect(bowlGain);
    bowlGain.connect(this.masterGain);

    bowlOsc1.start(now);
    bowlOsc2.start(now);

    this.activeNodes.push(bowlOsc1, bowlOsc2, bowlFilter, bowlGain);

    // Bowl filter frequency modulation (creating hum/singing bowl resonance sweep)
    const modulateBowlFilter = () => {
      if (!this.isPlaying || this.currentMood !== 'meditation') return;
      const targetFreq = 140 + Math.random() * 120;
      const transitionTime = 4 + Math.random() * 4;
      bowlFilter.frequency.setTargetAtTime(targetFreq, this.ctx?.currentTime || 0, transitionTime / 2);
    };
    modulateBowlFilter();
    this.noiseTimer = setInterval(modulateBowlFilter, 4000);
  }

  /**
   * Aether Wind Mood
   * E minor sweeping pad, howling filter noise sweeps
   */
  private startAetherWind() {
    if (!this.ctx || !this.masterGain) return;
    const now = this.ctx.currentTime;

    // E minor chord drone: E2, B2, E3, G3, B3, D4
    const freqs = [82.41, 123.47, 164.81, 196.00, 246.94, 293.66];
    const filter = this.ctx.createBiquadFilter();
    filter.type = 'lowpass';
    filter.frequency.setValueAtTime(400, now);
    filter.connect(this.masterGain);
    this.activeNodes.push(filter);

    freqs.forEach((freq, idx) => {
      if (!this.ctx || !this.masterGain) return;
      const osc = this.ctx.createOscillator();
      const gain = this.ctx.createGain();
      osc.type = idx % 2 === 0 ? 'sine' : 'triangle';
      // Pitch modulation for etherial drift
      osc.frequency.setValueAtTime(freq, now);
      
      gain.gain.setValueAtTime(0, now);
      gain.gain.linearRampToValueAtTime(0.05 / freqs.length, now + 4);

      osc.connect(gain);
      gain.connect(filter);
      osc.start(now);
      this.activeNodes.push(osc, gain);
    });

    // Pitch sweep LFO
    const pitchLfo = this.ctx.createOscillator();
    const pitchLfoGain = this.ctx.createGain();
    pitchLfo.type = 'sine';
    pitchLfo.frequency.setValueAtTime(0.04, now); // extremely slow
    pitchLfoGain.gain.setValueAtTime(0.8, now); // scale pitch change in Hz
    
    // Connect to pad filter frequency instead of pitch for a subtle phase sweep
    pitchLfo.connect(pitchLfoGain);
    pitchLfoGain.connect(filter.frequency);
    pitchLfo.start(now);

    this.activeNodes.push(pitchLfo, pitchLfoGain);

    // Sweeping wind white noise
    const bufferSize = 2 * this.ctx.sampleRate;
    const noiseBuffer = this.ctx.createBuffer(1, bufferSize, this.ctx.sampleRate);
    const output = noiseBuffer.getChannelData(0);
    for (let i = 0; i < bufferSize; i++) {
      output[i] = Math.random() * 2 - 1;
    }

    const noiseSource = this.ctx.createBufferSource();
    noiseSource.buffer = noiseBuffer;
    noiseSource.loop = true;

    const windFilter = this.ctx.createBiquadFilter();
    windFilter.type = 'bandpass';
    windFilter.Q.setValueAtTime(3.5, now);
    windFilter.frequency.setValueAtTime(280, now);
    
    const windGain = this.ctx.createGain();
    windGain.gain.setValueAtTime(0, now);
    windGain.gain.linearRampToValueAtTime(0.012, now + 5);

    noiseSource.connect(windFilter);
    windFilter.connect(windGain);
    windGain.connect(this.masterGain);

    noiseSource.start(now);
    this.activeNodes.push(noiseSource, windFilter, windGain);

    const sweepWind = () => {
      if (!this.isPlaying || this.currentMood !== 'wind') return;
      const targetCutoff = 150 + Math.random() * 700;
      const time = 4 + Math.random() * 5;
      windFilter.frequency.setTargetAtTime(targetCutoff, this.ctx?.currentTime || 0, time / 2.5);
    };

    sweepWind();
    this.noiseTimer = setInterval(sweepWind, 6000);
  }
}
