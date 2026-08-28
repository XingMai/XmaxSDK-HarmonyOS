import { RealtimeConnectionState, RealtimeVideoTrack } from '@xmax/sdk';
import { Reference } from '../../reference/Reference';
import { ReferenceCategory } from '../../reference/ReferenceCategory';

@Observed
export class RealtimeReferenceItemState {
  readonly reference: Reference;
  isSelected: boolean = false;

  constructor(reference: Reference) {
    this.reference = reference;
  }
}

@Observed
export class RealtimeReferenceListState {
  items: RealtimeReferenceItemState[];

  constructor(references: Reference[]) {
    this.items = references.map(
      (reference: Reference): RealtimeReferenceItemState =>
        new RealtimeReferenceItemState(reference)
    );
  }

  insertAfterAddAction(item: RealtimeReferenceItemState): void {
    const nextItems: RealtimeReferenceItemState[] = this.items.slice();
    const addIndex: number = nextItems.findIndex(
      (candidate: RealtimeReferenceItemState): boolean => candidate.reference.isAddAction
    );
    nextItems.splice(addIndex < 0 ? 0 : addIndex + 1, 0, item);
    this.items = nextItems;
  }
}

@Observed
export class RealtimeCategoryState {
  readonly category: ReferenceCategory;
  readonly referenceList: RealtimeReferenceListState;

  constructor(category: ReferenceCategory) {
    this.category = category;
    this.referenceList = new RealtimeReferenceListState(category.references);
  }
}

@Observed
export class RealtimeViewState {
  selectedCategoryId: string;
  selectedReferenceId: string = '';
  promptText: string = '';
  promptReferenceImageUrl: string = '';
  isPromptReferenceUploading: boolean = false;
  connectionState: RealtimeConnectionState = RealtimeConnectionState.IDLE;
  localVideoTrack: RealtimeVideoTrack | null = null;
  remoteVideoTrack: RealtimeVideoTrack | null = null;
  isLocalPreviewLoading: boolean = true;
  isGenerationStarting: boolean = false;
  isMoxGenerationActive: boolean = false;
  errorMessage: string = '';
  readonly categories: ReferenceCategory[];
  readonly categoryStates: RealtimeCategoryState[];
  private readonly emptyReferenceList: RealtimeReferenceListState = new RealtimeReferenceListState([]);

  constructor(categories: ReferenceCategory[]) {
    this.categories = categories;
    this.categoryStates = categories.map(
      (category: ReferenceCategory): RealtimeCategoryState => new RealtimeCategoryState(category)
    );
    this.selectedCategoryId = categories.length > 0 ? categories[0].id : '';
  }

  get hasSelectedReference(): boolean {
    return this.selectedReferenceId.length > 0;
  }

  get canCancelGeneration(): boolean {
    return this.isGenerationStarting ||
      this.connectionState === RealtimeConnectionState.GENERATING;
  }

  get isRemoteVideoVisible(): boolean {
    return this.connectionState === RealtimeConnectionState.GENERATING;
  }

  referenceList(categoryId: string): RealtimeReferenceListState {
    const categoryState: RealtimeCategoryState | undefined = this.categoryStates.find(
      (candidate: RealtimeCategoryState): boolean => candidate.category.id === categoryId
    );
    return categoryState?.referenceList ?? this.emptyReferenceList;
  }
}
