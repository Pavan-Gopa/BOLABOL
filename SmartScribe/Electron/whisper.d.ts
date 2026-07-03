export {};

declare global {
  interface Window {
    whisper: {
      installModel(modelId: string): Promise<boolean>;
      transcribeFile(
        fname_inp: string,
        modelId: string,
        opts?: { forceCpu?: boolean; threads?: number }
      ): Promise<{ text: string; segments?: Array<{ t0?: string; t1?: string; text: string }>; engine?: string; engineAssumed?: boolean }>;
      onComplete(cb: (m: any) => void): void;
      onError(cb: (m: any) => void): void;
    };
    dialogs: {
      pickAudioFile(): Promise<string | null>;
    };
  }
}
