function createCameraKitFixture(calls = []) {
  const listeners = [];
  const front = { id: 'front', cameraPosition: 'front' };
  const back = { id: 'back', cameraPosition: 'back' };
  const profile = { format: 'yuv420sp', size: { width: 1440, height: 1080 } };

  const cameraManager = {
    getSupportedCameras() { return [front, back]; },
    getSupportedOutputCapability(device, mode) {
      calls.push(['camera-capability', device.id, mode]);
      return { previewProfiles: [profile] };
    },
    createCameraInput(device) {
      calls.push(['camera-input', device.id]);
      return {
        async open() { calls.push(['camera-open', device.id]); },
        async close() { calls.push(['camera-close', device.id]); }
      };
    },
    createSession(mode) {
      calls.push(['camera-session', mode]);
      return {
        beginConfig() { calls.push(['camera-begin-config']); },
        canAddInput() { return true; },
        addInput() { calls.push(['camera-add-input']); },
        canAddOutput() { return true; },
        addOutput() { calls.push(['camera-add-output']); },
        async commitConfig() { calls.push(['camera-commit']); },
        async start() { calls.push(['camera-start']); },
        async stop() { calls.push(['camera-stop']); },
        async release() { calls.push(['camera-session-release']); }
      };
    }
  };

  class CameraFrameOutput {
    static create(_manager, selectedProfile, listener) {
      calls.push(['camera-frame-output', selectedProfile.size.width, selectedProfile.size.height]);
      listeners.push(listener);
      return {
        output: {
          getSupportedFrameRates() { return [{ min: 1, max: 30 }]; },
          setFrameRate(min, max) { calls.push(['camera-frame-rate', min, max]); }
        },
        configure(format, fps) {
          calls.push(['camera', format.width, format.height, fps]);
        },
        async release() { calls.push(['camera-output-release']); }
      };
    }
  }

  return {
    kit: { camera: {
      CameraPosition: { CAMERA_POSITION_FRONT: 'front', CAMERA_POSITION_BACK: 'back' },
      CameraFormat: { CAMERA_FORMAT_YUV_420_SP: 'yuv420sp' },
      SceneMode: { NORMAL_VIDEO: 'normal-video' },
      getCameraManager() { return cameraManager; }
    } },
    frameOutput: { CameraFrameOutput },
    emit(frame, outputIndex = listeners.length - 1) { listeners[outputIndex](frame); },
    listeners
  };
}

module.exports = { createCameraKitFixture };
