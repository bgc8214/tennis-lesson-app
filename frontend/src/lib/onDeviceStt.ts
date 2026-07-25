import { registerPlugin } from "@capacitor/core";

export interface OnDeviceSttSegment {
  startSec: number;
  endSec: number;
  text: string;
}

export interface OnDeviceSttResult {
  locale: string;
  segments: OnDeviceSttSegment[];
  fullText: string;
}

export interface OnDeviceSttPlugin {
  isAvailable(): Promise<{ available: boolean; reason?: string }>;
  transcribe(options: { path: string; language?: string }): Promise<OnDeviceSttResult>;
}

export const OnDeviceSTT = registerPlugin<OnDeviceSttPlugin>("OnDeviceSTT");
