// AudioWorklet processor for recording audio data
class AudioRecorderProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.isRecording = false;
    this.audioData = [];
    
    this.port.onmessage = (event) => {
      if (event.data.command === 'start') {
        this.isRecording = true;
        this.audioData = [];
      } else if (event.data.command === 'stop') {
        this.isRecording = false;
        this.port.postMessage({
          command: 'audioData',
          data: new Float32Array(this.audioData)
        });
        this.audioData = [];
      }
    };
  }

  process(inputs, outputs, parameters) {
    const input = inputs[0];
    
    if (this.isRecording && input && input.length > 0) {
      const inputChannel = input[0]; // Use first channel (mono)
      
      // Collect audio data
      for (let i = 0; i < inputChannel.length; i++) {
        this.audioData.push(inputChannel[i]);
      }
    }

    return true; // Keep processor alive
  }
}

registerProcessor('audio-recorder-processor', AudioRecorderProcessor);
