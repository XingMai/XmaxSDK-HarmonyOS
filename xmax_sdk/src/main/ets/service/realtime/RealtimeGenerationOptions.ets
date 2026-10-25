//
//  RealtimeGenerationOptions.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { RealtimeContext } from './RealtimeContext';
import { RealtimeMediaStream } from './RealtimeMediaStream';

/**
 * Static generation parameters. The image must be server-accessible and match local input aspect
 * ratio.
 */
export interface RealtimeGenerationParameters {

  /** Whether to generate from a specified static image; omission uses ordinary realtime input. */
  readonly static_generate?: boolean;

  /** The static image URL, required for static generation. */
  readonly static_image_path?: string;
}

/**
 * Options for starting, updating, or replacing a task while retaining the connection and local
 * media.
 */
export interface RealtimeGenerationOptions {

  /** The local stream created by this manager; optional while connected. */
  readonly localStream?: RealtimeMediaStream;

  /** The requested conditions; omission reuses cached conditions. */
  readonly context?: RealtimeContext;

  /**
   * Whether to create a new task, default false. Static tasks permit interaction after
   * confirmation; ordinary tasks also await a first frame.
   */
  readonly restart?: boolean;

  /** Whether to restore the original face; defaults to false. */
  readonly faceRestoration?: boolean;

  /**
   * The public static-image configuration entry, requiring context and cached independently by the
   * SDK. Omitting context reuses the cache; explicit context without extraParams clears static
   * configuration.
   */
  readonly extraParams?: RealtimeGenerationParameters;
}
