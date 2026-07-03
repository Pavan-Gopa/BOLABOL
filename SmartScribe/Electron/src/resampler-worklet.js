class ResamplerProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    this.targetSampleRate = options.processorOptions.targetSampleRate;
    this.ratio = sampleRate / this.targetSampleRate;
    this.lastIndex = 0;
    this.buffer = new Float32Array(2048);
    this.bufferIndex = 0;
  }

  process(inputs, outputs) {
    const input = inputs[0];
    const output = outputs[0];
    
    if (!input || !input.length) return true;
    
    const channel = input[0];
    
    // Linear interpolation resampling
    for (let i = 0; i < output[0].length; i++) {
      const targetIndex = i * this.ratio;
      const index = Math.floor(targetIndex);
      const fraction = targetIndex - index;
      
      const current = channel[index] || 0;
      const next = channel[index + 1] || 0;
      
      // Linear interpolation
      output[0][i] = current + (next - current) * fraction;
    }
    
    return true;
  }
}

registerProcessor('resampler-worklet', ResamplerProcessor);
