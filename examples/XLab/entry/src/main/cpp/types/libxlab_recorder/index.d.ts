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

export interface FileFrame {
  video: boolean;
  data: ArrayBuffer;
  width: number;
  height: number;
  sampleRate: number;
  channels: number;
  timestampUs: number;
  error?: string;
}

export interface FileSource {
  readonly width: number;
  readonly height: number;
  readonly hasAudio: boolean;
  start(): void;
  release(): Promise<void>;
}

export const createFileSource: (fd: number, length: number, onFrame: (frame: FileFrame) => void) => Promise<FileSource>;
