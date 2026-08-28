import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CameraPosition,
  RealtimeConfiguration,
  RealtimeConnectionState,
  RealtimeContext,
  RealtimeMediaStream,
  RealtimeModels,
  RealtimeState,
  RealtimeVideoFormat,
  RealtimeVideoTrack,
  XmaxClient,
  XmaxConfiguration,
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
        new XmaxConfiguration(XLabConfiguration.currentApiKey()),
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
          this.state.errorMessage = error.message;
        }
      });
      manager.setStateListener((state: RealtimeState): void => {
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

      const localStream: RealtimeMediaStream = await this.createLocalStream(
        manager,
        localVideoPath,
        localImagePath
      );
      this.state.localVideoTrack = localStream.videoTrack ?? null;
      if (localVideoPath.length > 0 || localImagePath.length > 0) {
        this.state.isLocalPreviewLoading = false;
      }

      if (this.realtimeManager !== manager) {
        await this.stopLocalInput(
          manager,
          localVideoPath,
          localImagePath
        );
        this.state.localVideoTrack = null;
        return;
      }

      const remoteStream = await manager.connect(localStream);
      this.state.remoteVideoTrack = remoteStream.videoTrack ?? null;

      if (this.realtimeManager === manager) {
        this.scheduleGenerationUpdate();
      }
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
      this.connecting = false;
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
    if (manager === null || this.connecting || this.switchingCamera) {
      return;
    }

    const currentTrack: RealtimeVideoTrack | null = this.state.localVideoTrack;
    const videoFormat: RealtimeVideoFormat | undefined = currentTrack?.videoFormat;
    const position: CameraPosition | undefined = currentTrack?.position;
    if (videoFormat === undefined || position === undefined) {
      return;
    }

    const nextPosition: CameraPosition = position === CameraPosition.FRONT ?
      CameraPosition.BACK : CameraPosition.FRONT;
    const shouldRestartGeneration: boolean = this.state.isGenerationStarting ||
      manager.currentState.connectionState === RealtimeConnectionState.GENERATING;
    this.switchingCamera = true;
    const switchRevision: number = ++this.generationRevision;
    this.state.errorMessage = '';

    let switched: boolean = false;
    try {
      if (shouldRestartGeneration) {
        this.state.isGenerationStarting = true;
      }

      const stream: RealtimeMediaStream = await manager.replaceLocalCameraStream(
        videoFormat,
        nextPosition
      );
      if (this.realtimeManager === manager) {
        this.state.localVideoTrack = stream.videoTrack ?? null;
        switched = true;
      }
    } catch (error) {
      if (this.realtimeManager === manager) {
        this.state.isGenerationStarting = false;
        this.presentError(error);
      }
    } finally {
      this.switchingCamera = false;
    }

    const generationChanged: boolean = this.generationRevision !== switchRevision;
    if (switched && (shouldRestartGeneration || generationChanged)) {
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
    this.state.connectionState = RealtimeConnectionState.DISCONNECTED;
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
    const connectionAvailable: boolean = manager !== null &&
      (manager.currentState.connectionState === RealtimeConnectionState.CONNECTED ||
        manager.currentState.connectionState === RealtimeConnectionState.GENERATING);
    if (!connectionAvailable) {
      const message: string = this.state.errorMessage.trim().length > 0 ?
        this.state.errorMessage : '实时连接尚未建立';
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
    if (this.selectedReferenceItem !== null) {
      this.selectedReferenceItem.isSelected = false;
      this.selectedReferenceItem = null;
      this.state.selectedReferenceId = '';
    }
    this.submittedPrompt = '';
    this.generationInputMode = GenerationInputMode.REFERENCE;
    this.state.isGenerationStarting = false;
    this.state.isMoxGenerationActive = false;
    this.scheduleGenerationUpdate();
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
    if (this.switchingCamera || this.changingLocalMedia) {
      return;
    }

    if (this.generationUpdating) {
      const manager: XmaxRealtimeManaging | null = this.realtimeManager;
      if (manager !== null &&
        (manager.currentState.connectionState === RealtimeConnectionState.CONNECTED ||
          manager.currentState.connectionState === RealtimeConnectionState.GENERATING)) {
        manager.stopGeneration();
      }
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
        if (manager === null || this.switchingCamera || this.changingLocalMedia ||
          (manager.currentState.connectionState !== RealtimeConnectionState.CONNECTED &&
            manager.currentState.connectionState !== RealtimeConnectionState.GENERATING)) {
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
          if (revision !== this.generationRevision) {
            continue;
          }
          const shouldGenerate: boolean = usesPrompt || usesMox ?
            prompt.length > 0 : referencePath !== undefined;
          if (shouldGenerate) {
            this.state.isMoxGenerationActive = usesMox;
            if (manager.currentState.connectionState === RealtimeConnectionState.CONNECTED) {
              this.state.isGenerationStarting = true;
            }
            await manager.startGeneration(new RealtimeContext(prompt, referencePath));
          } else {
            this.state.isGenerationStarting = false;
            this.state.isMoxGenerationActive = false;
            await manager.stopGeneration();
          }
          this.state.errorMessage = '';
        } catch (error) {
          if (revision === this.generationRevision) {
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
    const shouldReconnect: boolean =
      connectionState === RealtimeConnectionState.CONNECTED ||
        connectionState === RealtimeConnectionState.GENERATING;
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

      if (shouldReconnect) {
        await manager.disconnect();
      }
      await this.stopLocalInput(
        manager,
        previousVideoPath,
        previousImagePath
      );
      stream = await creation(manager, resolvedPath);
      if (this.realtimeManager !== manager) {
        await this.stopLocalInput(
          manager,
          isImage ? '' : resolvedPath,
          isImage ? resolvedPath : ''
        );
        return;
      }

      this.state.localVideoTrack = stream.videoTrack ?? null;
      this.state.isLocalPreviewLoading = false;
      if (shouldReconnect) {
        const remoteStream: RealtimeMediaStream = await manager.connect(stream);
        this.state.remoteVideoTrack = remoteStream.videoTrack ?? null;
      }
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
      this.changingLocalMedia = false;
    }

    const generationChanged: boolean =
      this.generationRevision !== changeRevision;
    if (changed && (shouldRestartGeneration || generationChanged)) {
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
      this.videoFormat(),
      CameraPosition.FRONT
    );
  }

  private videoFormat(): RealtimeVideoFormat {
    return new RealtimeVideoFormat(832, 1472, 24);
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
