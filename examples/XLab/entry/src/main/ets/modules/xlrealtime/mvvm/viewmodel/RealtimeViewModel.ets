import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CameraPosition,
  RealtimeConfiguration,
  RealtimeConnectionState,
  RealtimeDisconnectionReason,
  RealtimeContext,
  RealtimeMediaStream,
  RealtimeModels,
  RealtimeState,
  XmaxClient,
  XmaxConfiguration,
  XmaxEnvironment,
  XmaxLoggerOption,
  XmaxError,
  XmaxRealtimeManaging
} from '@xmax/sdk';
import { XLabConfiguration } from '../../config/XLabConfiguration';
import { XLabModelSelection } from '../../config/XLabModelSelection';
import { Reference, ReferenceUploadState } from '../../reference/Reference';
import { ReferenceCategory } from '../../reference/ReferenceCategory';
import { ReferenceDataSource } from '../../reference/ReferenceDataSource';
import { ReferenceUploading } from '../../reference/ReferenceUploader';
import { RealtimeReferenceItemState, RealtimeViewState } from '../model/RealtimeViewState';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'RealtimeViewModel';

enum GenerationInputMode {
  REFERENCE = 'reference',
  PROMPT = 'prompt',
  MOX = 'mox'
}

type LocalMediaCreation = (
  manager: XmaxRealtimeManaging,
  filePath: string
) => Promise<RealtimeMediaStream>;

export class RealtimeViewModel {
  onMessage: ((message: string) => void) | null = null;
  readonly state: RealtimeViewState;

  private static nextCustomReferenceId: number = 1;
  private selectedReferenceItem: RealtimeReferenceItemState | null = null;
  private referenceUploader: ReferenceUploading | null = null;
  private readonly uploadVersions: Map<string, number> = new Map();
  private nextUploadVersion: number = 1;
  private promptReference: Reference | null = null;
  private promptReferenceUploadVersion: number = 0;
  private realtimeManager: XmaxRealtimeManaging | null = null;
  private localStream: RealtimeMediaStream | null = null;
  private remoteStream: RealtimeMediaStream | null = null;
  private connecting: boolean = false;
  private switchingCamera: boolean = false;
  private changingLocalMedia: boolean = false;
  private generationUpdating: boolean = false;
  private generationRevision: number = 0;
  private generationInputMode: GenerationInputMode = GenerationInputMode.REFERENCE;
  private submittedPrompt: string = '';
  private localVideoPath: string = '';
  private localImagePath: string = '';
  private moxReferenceSourcePath: string = '';
  private moxReferenceRemoteUrl: string = '';

  constructor(categories: ReferenceCategory[] = ReferenceDataSource.categories()) {
    this.state = new RealtimeViewState(categories);
  }

  setReferenceUploader(uploader: ReferenceUploading): void {
    this.referenceUploader = uploader;
  }

  async setAudioMuted(muted: boolean): Promise<void> {
    this.state.isAudioMuted = muted;
    await Promise.all([this.applyLocalAudioVolume(), this.applyRemoteAudioVolume()]);
  }

  async setLocalAudioVolume(volume: number): Promise<void> {
    this.state.localAudioVolume = volume;
    const wasMuted: boolean = this.state.isAudioMuted;
    this.state.isAudioMuted = false;
    await Promise.all([
      this.applyLocalAudioVolume(),
      wasMuted ? this.applyRemoteAudioVolume() : Promise.resolve()
    ]);
  }

  async setRemoteAudioVolume(volume: number): Promise<void> {
    this.state.remoteAudioVolume = volume;
    const wasMuted: boolean = this.state.isAudioMuted;
    this.state.isAudioMuted = false;
    await Promise.all([
      this.applyRemoteAudioVolume(),
      wasMuted ? this.applyLocalAudioVolume() : Promise.resolve()
    ]);
  }

  private async applyLocalAudioVolume(): Promise<void> {
    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    const volume: number = this.state.isAudioMuted ? 0 : this.state.localAudioVolume;
    try {
      await manager?.setLocalAudioVolume(volume);
    } catch (error) {
      if (this.realtimeManager === manager &&
        volume === (this.state.isAudioMuted ? 0 : this.state.localAudioVolume)) {
        this.onMessage?.(this.errorMessage(error));
      }
    }
  }

  private async applyRemoteAudioVolume(): Promise<void> {
    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    const volume: number = this.state.isAudioMuted ? 0 : this.state.remoteAudioVolume;
    try {
      await manager?.setRemoteAudioVolume(volume);
    } catch (error) {
      if (this.realtimeManager === manager &&
        volume === (this.state.isAudioMuted ? 0 : this.state.remoteAudioVolume)) {
        this.onMessage?.(this.errorMessage(error));
      }
    }
  }

  async connect(
    context: common.UIAbilityContext,
    localVideoPath: string = '',
    localImagePath: string = ''
  ): Promise<void> {
    if (this.realtimeManager !== null || this.connecting) {
      return;
    }
    this.connecting = true;
    this.localVideoPath = localVideoPath;
    this.localImagePath = localImagePath;
    this.state.isLocalPreviewLoading = true;
    this.state.errorMessage = '';

    let connectingManager: XmaxRealtimeManaging | null = null;
    try {
      const client = new XmaxClient(
        new XmaxConfiguration(
          XLabConfiguration.currentApiKey(),
          XmaxEnvironment.CHINA,
          XmaxLoggerOption.ALL
        ),
        context
      );
      const manager: XmaxRealtimeManaging = client.createRealtimeManager(
        new RealtimeConfiguration(
          RealtimeModels.realtime(XLabModelSelection.current())
        )
      );
      connectingManager = manager;
      this.realtimeManager = manager;
      manager.setCameraPreviewReadyListener((): void => {
        if (this.realtimeManager === manager) {
          this.state.isLocalPreviewLoading = false;
        }
      });
      manager.setErrorListener((error: XmaxError): void => {
        if (this.realtimeManager === manager) {
          // 监听器只接收致命错误；具体调用失败仍在各自 catch 中处理。
          this.state.errorMessage = error.message;
          this.state.isGenerationStarting = false;
          this.state.isMoxGenerationActive = false;
          this.state.remoteVideoTrack = null;
        }
      });
      manager.setStateListener((state: RealtimeState): void => {
        if (this.realtimeManager !== manager) {
          return;
        }
        if (state.disconnectionReason === RealtimeDisconnectionReason.CAMERA_ORIENTATION_CHANGED) {
          if (state.connectionState === RealtimeConnectionState.DISCONNECTING) {
            this.generationRevision++;
            this.clearGenerationSelection();
            this.remoteStream = null;
          } else if (state.connectionState === RealtimeConnectionState.DISCONNECTED &&
            this.state.connectionState !== RealtimeConnectionState.DISCONNECTED) {
            this.state.errorMessage = '';
            this.onMessage?.('屏幕方向已切换，生成已断开，请重新开始');
          }
        }
        if (state.connectionState !== RealtimeConnectionState.GENERATING) {
          this.state.remoteVideoTrack = null;
        }
        this.state.connectionState = state.connectionState;
        if (state.connectionState === RealtimeConnectionState.GENERATING ||
          state.connectionState === RealtimeConnectionState.DISCONNECTING ||
          state.connectionState === RealtimeConnectionState.DISCONNECTED ||
          state.connectionState === RealtimeConnectionState.ERROR) {
          this.state.isGenerationStarting = false;
        }
        if (state.connectionState === RealtimeConnectionState.DISCONNECTING ||
          state.connectionState === RealtimeConnectionState.DISCONNECTED ||
          state.connectionState === RealtimeConnectionState.ERROR) {
          this.state.isMoxGenerationActive = false;
        }
      });

      await Promise.all([this.applyLocalAudioVolume(), this.applyRemoteAudioVolume()]);
      if (this.realtimeManager !== manager) {
        return;
      }
      const localStream: RealtimeMediaStream = await this.createLocalStream(
        manager,
        localVideoPath,
        localImagePath
      );
      if (this.realtimeManager !== manager) {
        return;
      }
      this.localStream = localStream;
      this.state.localVideoTrack = localStream.videoTrack ?? null;
      if (localVideoPath.length > 0 || localImagePath.length > 0) {
        this.state.isLocalPreviewLoading = false;
      }
      // 本地预览不占用服务端会话；首次提交生成条件时再连接。
      this.scheduleGenerationUpdate();
    } catch (error) {
      if (connectingManager === null ||
        this.realtimeManager === connectingManager) {
        const message: string = this.errorMessage(error);
        this.state.errorMessage = message;
        this.state.remoteVideoTrack = null;
        this.state.isLocalPreviewLoading = false;
        this.logPreviewError(message);
      }
    } finally {
      if (this.realtimeManager === connectingManager) {
        this.connecting = false;
      }
    }
  }

  async resume(
    context: common.UIAbilityContext,
    fallbackVideoPath: string = '',
    fallbackImagePath: string = ''
  ): Promise<void> {
    const hasPreservedInput: boolean = this.localVideoPath.length > 0 ||
      this.localImagePath.length > 0;
    await this.connect(
      context,
      hasPreservedInput ? this.localVideoPath : fallbackVideoPath,
      hasPreservedInput ? this.localImagePath : fallbackImagePath
    );
  }

  async switchCamera(): Promise<void> {
    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    if (manager === null || this.connecting || this.switchingCamera ||
      this.changingLocalMedia || this.state.isGenerationStarting ||
      this.state.localVideoTrack?.position === undefined) {
      return;
    }

    this.switchingCamera = true;
    const switchRevision: number = ++this.generationRevision;
    this.state.errorMessage = '';
    try {
      this.state.isGenerationStarting =
        manager.currentState.connectionState === RealtimeConnectionState.GENERATING;
      const stream: RealtimeMediaStream = await manager.switchCamera();
      if (this.realtimeManager === manager) {
        this.localStream = stream;
        this.state.localVideoTrack = stream.videoTrack ?? null;
        if (manager.currentState.connectionState === RealtimeConnectionState.GENERATING) {
          this.state.remoteVideoTrack = this.remoteStream?.videoTrack ?? null;
        }
      }
    } catch (error) {
      if (this.realtimeManager === manager && this.generationRevision === switchRevision) {
        this.presentError(error);
      }
    } finally {
      if (this.realtimeManager === manager) {
        this.switchingCamera = false;
        this.state.isGenerationStarting = false;
      }
    }

    if (this.realtimeManager === manager &&
      this.generationRevision !== switchRevision) {
      this.scheduleGenerationUpdate();
    }
  }

  async changeLocalVideo(filePath: string): Promise<void> {
    await this.changeLocalMedia(
      filePath,
      false,
      (
        manager: XmaxRealtimeManaging,
        resolvedPath: string
      ): Promise<RealtimeMediaStream> =>
        manager.createLocalVideoStream(resolvedPath)
    );
  }

  async changeLocalImage(filePath: string): Promise<void> {
    await this.changeLocalMedia(
      filePath,
      true,
      (
        manager: XmaxRealtimeManaging,
        resolvedPath: string
      ): Promise<RealtimeMediaStream> =>
        manager.createLocalImageStream(resolvedPath)
    );
  }

  async suspend(): Promise<void> {
    await this.closeRealtime(true);
  }

  async disconnect(): Promise<void> {
    await this.closeRealtime(false);
  }

  private async closeRealtime(preservesLocalInput: boolean): Promise<void> {
    this.generationRevision++;
    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    let closePromise: Promise<void> | null = null;
    if (manager !== null) {
      manager.setCameraPreviewReadyListener(null);
      manager.setStateListener(null);
      manager.setErrorListener(null);
      closePromise = manager.close();
    }
    this.realtimeManager = null;
    this.localStream = null;
    this.remoteStream = null;
    if (!preservesLocalInput) {
      this.localVideoPath = '';
      this.localImagePath = '';
    }
    this.moxReferenceSourcePath = '';
    this.moxReferenceRemoteUrl = '';
    if (this.selectedReferenceItem !== null) {
      this.selectedReferenceItem.isSelected = false;
      this.selectedReferenceItem = null;
    }
    this.submittedPrompt = '';
    this.generationInputMode = GenerationInputMode.REFERENCE;
    this.state.selectedReferenceId = '';
    this.state.localVideoTrack = null;
    this.state.remoteVideoTrack = null;
    this.state.isLocalPreviewLoading = true;
    this.connecting = false;
    this.switchingCamera = false;
    this.changingLocalMedia = false;
    this.state.isGenerationStarting = false;
    this.state.isMoxGenerationActive = false;
    this.state.errorMessage = '';
    if (closePromise !== null) {
      await closePromise;
    }
    if (this.realtimeManager === null) {
      this.state.connectionState = RealtimeConnectionState.DISCONNECTED;
    }
  }

  selectCategory(categoryId: string): void {
    const categoryExists: boolean = this.state.categories.some(
      (category: ReferenceCategory): boolean => category.id === categoryId
    );
    if (categoryExists) {
      this.state.selectedCategoryId = categoryId;
    }
  }

  updatePromptText(prompt: string): void {
    this.state.promptText = prompt;
  }

  submitPrompt(value: string): void {
    const prompt: string = value.trim();
    this.state.promptText = prompt;
    if (prompt.length === 0 || this.state.selectedCategoryId !== 'free' ||
      this.state.isPromptReferenceUploading) {
      return;
    }
    this.submittedPrompt = prompt;
    this.generationInputMode = GenerationInputMode.PROMPT;
    this.state.isMoxGenerationActive = false;
    this.scheduleGenerationUpdate();
  }

  startMoxGeneration(): void {
    if (this.state.selectedCategoryId !== 'mox') {
      return;
    }

    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    const connectionAvailable: boolean = manager !== null && this.localStream !== null;
    if (!connectionAvailable) {
      const message: string = this.state.errorMessage.trim().length > 0 ?
        this.state.errorMessage : '本地画面尚未就绪';
      this.onMessage?.(message);
      return;
    }

    if (this.selectedReferenceItem !== null) {
      this.selectedReferenceItem.isSelected = false;
      this.selectedReferenceItem = null;
      this.state.selectedReferenceId = '';
    }
    this.submittedPrompt = '让画面自然动起来';
    this.generationInputMode = GenerationInputMode.MOX;
    this.scheduleGenerationUpdate();
  }

  addPromptReference(filePath: string): void {
    const uploader: ReferenceUploading | null = this.referenceUploader;
    if (uploader === null) {
      this.onMessage?.('参考图上传尚未就绪');
      return;
    }

    const reference = new Reference(
      `prompt-${Date.now()}-${RealtimeViewModel.nextCustomReferenceId++}`,
      'free',
      '自由模式参考图',
      filePath,
      undefined,
      false,
      ReferenceUploadState.UPLOADING
    );
    const version: number = ++this.promptReferenceUploadVersion;
    this.promptReference = reference;
    this.state.promptReferenceImageUrl = '';
    this.state.isPromptReferenceUploading = true;

    uploader.uploadReference(filePath)
      .then((remoteUrl: string): void => {
        if (this.promptReferenceUploadVersion !== version ||
          this.promptReference !== reference) {
          return;
        }
        reference.remoteUrl = remoteUrl;
        reference.uploadState = ReferenceUploadState.READY;
        this.state.promptReferenceImageUrl = filePath;
        this.state.isPromptReferenceUploading = false;
      })
      .catch((_error: Object): void => {
        if (this.promptReferenceUploadVersion !== version ||
          this.promptReference !== reference) {
          return;
        }
        this.promptReference = null;
        this.state.promptReferenceImageUrl = '';
        this.state.isPromptReferenceUploading = false;
        this.onMessage?.('参考图上传失败，请重试');
      });
  }

  removePromptReference(): void {
    this.promptReferenceUploadVersion++;
    this.promptReference = null;
    this.state.promptReferenceImageUrl = '';
    this.state.isPromptReferenceUploading = false;
  }

  selectReference(item: RealtimeReferenceItemState): void {
    if (item.reference.isAddAction) {
      return;
    }
    if (item.reference.uploadState === ReferenceUploadState.FAILED &&
      item.reference.imageUrl !== undefined) {
      this.startReferenceUpload(item);
      return;
    }
    if (this.selectedReferenceItem === item) {
      this.clearReference();
      return;
    }
    if (this.selectedReferenceItem !== null) {
      this.selectedReferenceItem.isSelected = false;
    }
    item.isSelected = true;
    this.selectedReferenceItem = item;
    this.state.selectedReferenceId = item.reference.id;
    this.generationInputMode = GenerationInputMode.REFERENCE;
    this.state.isMoxGenerationActive = false;
    this.scheduleGenerationUpdate();
  }

  addLocalReference(categoryId: string, filePath: string): void {
    const reference = new Reference(
      `custom-${Date.now()}-${RealtimeViewModel.nextCustomReferenceId++}`,
      categoryId,
      '自定义参考图',
      filePath,
      undefined,
      false,
      ReferenceUploadState.UPLOADING
    );
    const item = new RealtimeReferenceItemState(reference);
    this.state.referenceList(categoryId).insertAfterAddAction(item);
    this.selectReference(item);
    this.startReferenceUpload(item);
  }

  clearReference(): void {
    if (this.selectedReferenceItem === null) {
      return;
    }
    this.selectedReferenceItem.isSelected = false;
    this.selectedReferenceItem = null;
    this.state.selectedReferenceId = '';
    this.scheduleGenerationUpdate();
  }

  cancelGeneration(): void {
    this.clearGenerationSelection();
    this.scheduleGenerationUpdate();
  }

  private clearGenerationSelection(): void {
    if (this.selectedReferenceItem !== null) {
      this.selectedReferenceItem.isSelected = false;
      this.selectedReferenceItem = null;
      this.state.selectedReferenceId = '';
    }
    this.submittedPrompt = '';
    this.generationInputMode = GenerationInputMode.REFERENCE;
    this.state.isGenerationStarting = false;
    this.state.isMoxGenerationActive = false;
  }

  private startReferenceUpload(item: RealtimeReferenceItemState): void {
    const uploader: ReferenceUploading | null = this.referenceUploader;
    const filePath: string | undefined = item.reference.imageUrl;
    if (uploader === null || filePath === undefined) {
      item.reference.uploadState = ReferenceUploadState.FAILED;
      this.onMessage?.('参考图上传尚未就绪');
      return;
    }

    item.reference.uploadState = ReferenceUploadState.UPLOADING;
    const version: number = this.nextUploadVersion++;
    this.uploadVersions.set(item.reference.id, version);
    uploader.uploadReference(filePath)
      .then((remoteUrl: string): void => {
        if (this.uploadVersions.get(item.reference.id) !== version) {
          return;
        }
        item.reference.remoteUrl = remoteUrl;
        item.reference.uploadState = ReferenceUploadState.READY;
        this.uploadVersions.delete(item.reference.id);
        if (this.selectedReferenceItem === item) {
          this.scheduleGenerationUpdate();
        }
      })
      .catch((_error: Object): void => {
        if (this.uploadVersions.get(item.reference.id) !== version) {
          return;
        }
        item.reference.uploadState = ReferenceUploadState.FAILED;
        this.uploadVersions.delete(item.reference.id);
        this.onMessage?.('参考图上传失败，点击图片可重试');
      });
  }

  private scheduleGenerationUpdate(): void {
    this.generationRevision++;
    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    if (this.switchingCamera || this.generationUpdating) {
      // 连接中需要断开才能取消旧的一键生成；已连接时只停止生成，保留会话。
      if (manager !== null) {
        const state: RealtimeConnectionState = manager.currentState.connectionState;
        const stopping: Promise<void> = state === RealtimeConnectionState.CONNECTING ||
          state === RealtimeConnectionState.DISCONNECTING ? manager.disconnect() : manager.stopGeneration();
        void stopping.catch((error: Object): void => {
          if (this.realtimeManager === manager) {
            this.presentError(error);
          }
        });
      }
      return;
    }
    if (this.changingLocalMedia) {
      return;
    }
    void this.applyGenerationUpdates();
  }

  private async applyGenerationUpdates(): Promise<void> {
    this.generationUpdating = true;
    try {
      while (true) {
        const revision: number = this.generationRevision;
        const manager: XmaxRealtimeManaging | null = this.realtimeManager;
        const localStream: RealtimeMediaStream | null = this.localStream;
        if (manager === null || localStream === null || this.switchingCamera || this.changingLocalMedia ||
          manager.currentState.connectionState === RealtimeConnectionState.CONNECTING ||
          manager.currentState.connectionState === RealtimeConnectionState.DISCONNECTING) {
          return;
        }
        const selectedReference: Reference | undefined = this.selectedReferenceItem?.reference;
        const usesPrompt: boolean = this.generationInputMode === GenerationInputMode.PROMPT;
        const usesMox: boolean = this.generationInputMode === GenerationInputMode.MOX;
        const prompt: string = usesPrompt || usesMox ? this.submittedPrompt :
          this.generationPrompt(selectedReference?.categoryId ?? '');
        try {
          const referencePath: string | undefined = usesPrompt ?
            this.promptReference?.remoteUrl : usesMox ?
              await this.resolveMoxReferencePath() : selectedReference?.remoteUrl;
          if (revision !== this.generationRevision || this.realtimeManager !== manager) {
            continue;
          }
          const shouldGenerate: boolean = usesPrompt || usesMox ?
            prompt.length > 0 : referencePath !== undefined;
          if (shouldGenerate) {
            this.state.isMoxGenerationActive = usesMox;
            if (manager.currentState.connectionState !== RealtimeConnectionState.GENERATING) {
              this.state.isGenerationStarting = true;
            }
            const remoteStream: RealtimeMediaStream = await manager.startGeneration(
              localStream, new RealtimeContext(prompt, referencePath)
            );
            if (this.realtimeManager === manager && revision === this.generationRevision) {
              this.remoteStream = remoteStream;
              this.state.remoteVideoTrack = remoteStream.videoTrack ?? null;
            }
          } else {
            this.state.isGenerationStarting = false;
            this.state.isMoxGenerationActive = false;
            await manager.stopGeneration();
          }
          if (this.realtimeManager === manager && revision === this.generationRevision) {
            this.state.errorMessage = '';
          }
        } catch (error) {
          if (revision === this.generationRevision && this.realtimeManager === manager) {
            this.state.isGenerationStarting = false;
            this.state.isMoxGenerationActive = false;
            this.presentError(error);
            return;
          }
        }
        if (revision === this.generationRevision) {
          return;
        }
      }
    } finally {
      this.generationUpdating = false;
    }
  }

  private async changeLocalMedia(
    filePath: string,
    isImage: boolean,
    creation: LocalMediaCreation
  ): Promise<void> {
    const resolvedPath: string = filePath.trim();
    const manager: XmaxRealtimeManaging | null = this.realtimeManager;
    if (resolvedPath.length === 0 || manager === null || this.connecting ||
      this.switchingCamera || this.changingLocalMedia) {
      return;
    }

    const connectionState: RealtimeConnectionState =
      manager.currentState.connectionState;
    const shouldRestartGeneration: boolean = this.state.isGenerationStarting ||
      connectionState === RealtimeConnectionState.GENERATING;
    const previousVideoPath: string = this.localVideoPath;
    const previousImagePath: string = this.localImagePath;
    this.changingLocalMedia = true;
    const changeRevision: number = ++this.generationRevision;
    this.state.isLocalPreviewLoading = true;
    this.state.errorMessage = '';

    let changed: boolean = false;
    let stream: RealtimeMediaStream | null = null;
    try {
      if (shouldRestartGeneration) {
        this.state.isGenerationStarting = true;
      }

      this.state.localVideoTrack = null;
      this.state.remoteVideoTrack = null;

      this.localStream = null;
      this.remoteStream = null;
      await manager.disconnect();
      if (this.realtimeManager !== manager) {
        return;
      }
      await this.stopLocalInput(
        manager,
        previousVideoPath,
        previousImagePath
      );
      if (this.realtimeManager !== manager) {
        return;
      }
      stream = await creation(manager, resolvedPath);
      if (this.realtimeManager !== manager) {
        return;
      }

      this.localStream = stream;
      this.state.localVideoTrack = stream.videoTrack ?? null;
      this.state.isLocalPreviewLoading = false;
      if (isImage) {
        this.localImagePath = resolvedPath;
        this.localVideoPath = '';
        this.moxReferenceSourcePath = '';
        this.moxReferenceRemoteUrl = '';
      } else {
        this.localVideoPath = resolvedPath;
        this.localImagePath = '';
      }
      changed = true;
    } catch (error) {
      if (this.realtimeManager === manager) {
        this.state.localVideoTrack = stream?.videoTrack ?? null;
        this.state.remoteVideoTrack = null;
        this.state.isLocalPreviewLoading = false;
        this.state.isGenerationStarting = false;
        this.logPreviewError(this.errorMessage(error));
        this.presentError(error);
      }
    } finally {
      if (this.realtimeManager === manager) {
        this.changingLocalMedia = false;
      }
    }

    const generationChanged: boolean =
      this.generationRevision !== changeRevision;
    if (this.realtimeManager === manager && changed &&
      (shouldRestartGeneration || generationChanged)) {
      this.scheduleGenerationUpdate();
    }
  }

  private generationPrompt(categoryId: string): string {
    switch (categoryId) {
      case 'charx':
        return '视频中角色替换成参考图中角色';
      case 'clothx':
        return '视频中人物衣服替换成参考图中衣服';
      case 'vibex':
        return '视频风格变为参考图指定的风格';
      case 'dimx':
        return '指定角色在场景中互动';
      default:
        return '';
    }
  }

  private async resolveMoxReferencePath(): Promise<string | undefined> {
    const sourcePath: string = this.localImagePath.trim();
    if (sourcePath.length === 0) {
      return undefined;
    }
    if (this.moxReferenceSourcePath === sourcePath &&
      this.moxReferenceRemoteUrl.length > 0) {
      return this.moxReferenceRemoteUrl;
    }

    const uploader: ReferenceUploading | null = this.referenceUploader;
    if (uploader === null) {
      throw new Error('参考图上传尚未就绪');
    }

    this.state.isGenerationStarting = true;
    const remoteUrl: string = await uploader.uploadReference(sourcePath);
    if (this.localImagePath.trim() !== sourcePath) {
      return undefined;
    }
    this.moxReferenceSourcePath = sourcePath;
    this.moxReferenceRemoteUrl = remoteUrl;
    return remoteUrl;
  }

  private async stopLocalInput(
    manager: XmaxRealtimeManaging,
    localVideoPath: string,
    localImagePath: string
  ): Promise<void> {
    if (localImagePath.length > 0) {
      await manager.stopLocalImageStream();
      return;
    }
    if (localVideoPath.length > 0) {
      await manager.stopLocalVideoStream();
      return;
    }

    await manager.stopLocalCameraStream();
  }

  private async createLocalStream(
    manager: XmaxRealtimeManaging,
    localVideoPath: string,
    localImagePath: string
  ): Promise<RealtimeMediaStream> {
    if (localImagePath.length > 0) {
      return manager.createLocalImageStream(localImagePath);
    }
    if (localVideoPath.length > 0) {
      return manager.createLocalVideoStream(localVideoPath);
    }

    return manager.createLocalCameraStream(
      manager.options.model.defaultCameraVideoFormat,
      CameraPosition.FRONT
    );
  }

  private errorMessage(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }

  private presentError(error: Object): void {
    const message: string = this.errorMessage(error);
    this.state.errorMessage = message;
    this.onMessage?.(message);
  }

  private logPreviewError(message: string): void {
    hilog.error(
      LOG_DOMAIN,
      LOG_TAG,
      'Failed to load local preview: %{public}s',
      message
    );
  }
}
