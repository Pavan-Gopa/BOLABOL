declare global {
  interface Window {
    parakeet: {
      transcribeLocal(modelId: string, audioBuffer: ArrayBuffer | Buffer): Promise<{ text: string }>;
      precacheModel(id: string): void;
      removeModel(id: string): void;
      onDownloadComplete(cb: (msg: any) => void): void;
      onDownloadFailed(cb: (msg: any) => void): void;
    };
  }
}
export {};
