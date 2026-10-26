//
//  RealtimeModel.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

import { XmaxError, XmaxErrorCode } from '../../foundation/errors/XmaxError';
import { RealtimeVideoFormat } from './RealtimeVideoFormat';
import { ImageSize } from '../media/ImageSize';

/** A realtime generation model supported by XmaxSDK. */
export enum RealtimeModel {

  /** The X2.0 model. */
  X2_0 = 'x2.0',

  /** The X2.1 model. */
  X2_1 = 'x2.0-sla'
}

/** A realtime model's name, session API URL, input constraints, and default media format. */
export class ModelDefinition {

  /** The model name sent to the server. */
  readonly name: RealtimeModel;

  /**
   * The model's session API URL; undefined inherits the client environment without changing storage
   * services.
   */
  get baseURL(): string | undefined {
    return undefined;
  }

  /**
   * The fixed generation canvas dimensions, or an empty array for pixel-area constraints. Camera
   * requests must match a bucket exactly; images and videos retain their aspect ratio.
   */
  get resolutionBuckets(): ImageSize[] {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return [];
      case RealtimeModel.X2_1:
        return [
          new ImageSize(
            1920,
            1080
          ),
          new ImageSize(
            1080,
            1920
          ),
          new ImageSize(
            1408,
            1408
          ),
          new ImageSize(
            1152,
            1536
          ),
          new ImageSize(
            1536,
            1152
          )
        ];
    }
  }

  /** The minimum variable generation canvas area, in pixels. Small local media is not upscaled. */
  get minimumInputPixels(): number {
    return 600000;
  }

  /** The maximum local media area, in pixels, also limiting variable generation canvases. */
  get maximumInputPixels(): number {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return 1280000;
      case RealtimeModel.X2_1:
        return 2100000;
    }
  }

  /**
   * The variable generation canvas dimension alignment, in pixels. Local media dimensions are
   * aligned to 4.
   */
  get inputSizeAlignment(): number {
    return 32;
  }

  /** The frame rate used when no video format is specified, in fps. */
  get defaultFrameRate(): number {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return 30;
      case RealtimeModel.X2_1:
        return 30;
    }
  }

  /** The default camera capture dimensions and frame rate. */
  get defaultCameraVideoFormat(): RealtimeVideoFormat {
    switch (this.name) {
      case RealtimeModel.X2_0:
        return new RealtimeVideoFormat(
          832,
          1472,
          this.defaultFrameRate
        );
      case RealtimeModel.X2_1:
        return new RealtimeVideoFormat(
          1080,
          1920,
          this.defaultFrameRate
        );
    }
  }

  /**
   * Creates a model definition.
   *
   * @param name The model name recognized by the server.
   */
  constructor(
    name: RealtimeModel
  ) {
    if (name !== RealtimeModel.X2_0 && name !== RealtimeModel.X2_1) {
      throw new XmaxError(
        XmaxErrorCode.INVALID_CONFIGURATION,
        `Unsupported realtime model: ${name}`
      );
    }
    this.name = name;
  }
}

/** A factory for realtime model definitions. */
export class RealtimeModels {

  /**
   * Creates a definition for an SDK model.
   *
   * @param model The supported realtime model.
   *
   * @returns The model definition for RealtimeConfiguration.
   */
  static realtime(
    model: RealtimeModel
  ): ModelDefinition {
    return new ModelDefinition(model);
  }
}
