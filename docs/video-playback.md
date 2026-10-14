# XmaxSDK 视频单次播放与点击暂停

适用于 HarmonyOS SDK **1.0.10 及以上**，仅支持 `createLocalVideoStream()` 创建的视频文件流，不适用于摄像头或图片流。

以下片段基于已有的实时页面：`this.realtime` 为已创建的 realtime manager，视频轨道沿用原有绑定方式。

## 1. 不循环播放

`createLocalVideoStream()` 的第三个参数为 `loop`，默认 `true`。传入 `false` 即播放一次。

```ts
import { LocalVideoPlaybackState } from '@xmax/sdk';

// 创建视频流前注册监听。
this.realtime.setLocalVideoPlaybackStateListener((state): void => {
  if (state === LocalVideoPlaybackState.ENDED) {
    console.info('本地视频播放结束');
  }
});

// 第二个参数不指定输出格式，第三个参数关闭循环。
const localStream = await this.realtime.createLocalVideoStream(videoPath, undefined, false);
```

视频流创建后即开始本地播放，不会等点击生成才开始计时。后续连接、生成和视图绑定保持原有写法。

自然播放结束时：

- 回调一次 `ENDED`，表示本地视频及其音轨播放结束，**不是云端生成完成**。
- 停止提交本地音视频帧，远端已经在途的结果仍可继续显示。
- 不自动停止生成或退房；正在运行的生成任务仍保持 `GENERATING`。
- `ENDED` 后不能通过恢复播放重新开始。如需重播，先断开连接（若已连接），停止本地视频流，再重新创建。

默认循环播放时，每一轮结束不会触发 `ENDED`；主动停止或销毁也不属于自然播放结束。

## 2. 点击暂停 / 恢复

点击行为由 App 绑定，SDK 提供切换方法。以下字段和方法放在已有页面组件内：

```ts
private changingPlayback: boolean = false;

private async toggleVideoPlayback(): Promise<void> {
  const state = this.realtime.localVideoPlaybackState;
  if (this.changingPlayback || state === undefined || state === LocalVideoPlaybackState.ENDED) {
    return;
  }

  this.changingPlayback = true;
  try {
    await this.realtime.toggleLocalVideoStreamPlayback();
  } catch (error) {
    console.error(`切换播放状态失败：${error}`);
  } finally {
    this.changingPlayback = false;
  }
}
```

在已有视频视图上绑定点击：

```ts
XmaxRealtimeVideoView({
  localTrack: this.localVideoTrack,
  remoteTrack: this.remoteVideoTrack,
  contentMode: VideoContentMode.FIT,
  // 此示例将触摸用于暂停，关闭生成轨迹交互。
  isInteractionEnabled: false
})
  .width('100%')
  .height('100%')
  .onClick((): void => {
    void this.toggleVideoPlayback();
  })
```

视图组件和 `VideoContentMode` 从 `@xmax/sdk` 导入。若还需要触控生成，请用独立按钮控制暂停，保留视图的轨迹交互。

- 暂停后状态为 `PAUSE`，恢复后为 `PLAYING`，均通过同一个播放状态监听器通知。
- 暂停保留文件进度，持续发送最后一帧和静音音频，并尝试以截图定格远端画面；恢复后从原位置继续。
- **暂停不等于停止生成任务。**
- 页面初始化、连接或启动生成期间，应禁用点击；上面的 `changingPlayback` 仅防止重复点击。
- 也可以分别调用 `pauseLocalVideoStream()` 和 `resumeLocalVideoStream()`。结束后忽略点击，不再调用这些方法。

页面退出时按原有流程清理 manager；不再需要监听时调用 `setLocalVideoPlaybackStateListener(null)`。
