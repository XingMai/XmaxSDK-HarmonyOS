//
//  RealtimeMediaStream.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeVideoTrack } from './RealtimeVideoTrack';

/** A stream identity and video track for connection, generation, and display. */
export class RealtimeMediaStream {

  /** The media stream identifier. */
  readonly id: string;

  /** The stream's SDK video track handle. */
  readonly videoTrack?: RealtimeVideoTrack;

  /** Creates a realtime media stream. */
  constructor(
    id: string,
    videoTrack?: RealtimeVideoTrack
  ) {
    this.id = id;
    this.videoTrack = videoTrack;
  }
}
