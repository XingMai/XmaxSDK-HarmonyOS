export interface VideoPlane {
  data: ArrayBuffer;
  byteOffset: number;
  byteLength: number;
  stride: number;
}

export interface VideoFrame {
  width: number;
  height: number;
  rotation: number;
  pixelFormat: string;
  timestampUs: number;
  planes: VideoPlane[];
}

export interface AudioFrame {
  data: Uint8Array;
  sampleRate: number;
  channels: number;
  timestampUs: number;
}

export const create: (path: string, onError: (message: string) => void) => number;
export const appendVideo: (handle: number, frame: VideoFrame) => void;
export const appendAudio: (handle: number, frame: AudioFrame) => void;
export const finish: (handle: number, cancel: boolean) => Promise<string>;
