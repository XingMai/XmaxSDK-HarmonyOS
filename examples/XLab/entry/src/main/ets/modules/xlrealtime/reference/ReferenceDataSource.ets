import { XLabLocalization } from '../../../localization/XLabLocalization';
import { Reference } from './Reference';
import {
  ReferenceCameraPosition,
  ReferenceCategory,
  ReferenceCategoryInput
} from './ReferenceCategory';
import {
  REALTIME_REFERENCE_CONFIG,
  RealtimeReferenceConfigItem
} from './RealtimeReferenceConfig';

export class ReferenceDataSource {
  static categories(): ReferenceCategory[] {
    return [
      ReferenceDataSource.makeCategory(
        'charx',
        'category_charx',
        ReferenceCameraPosition.FRONT
      ),
      ReferenceDataSource.makeCategory(
        'clothx',
        'category_clothx',
        ReferenceCameraPosition.FRONT
      ),
      ReferenceDataSource.makeCategory(
        'vibex',
        'category_vibex',
        ReferenceCameraPosition.FRONT
      ),
      new ReferenceCategory(
        'mox',
        'category_mox',
        ReferenceCameraPosition.FRONT,
        [ReferenceCameraPosition.FRONT, ReferenceCameraPosition.BACK],
        ReferenceCategoryInput.INSTRUCTION,
        [],
        'touch_instruction'
      ),
      ReferenceDataSource.makeCategory(
        'dimx',
        'category_dimx',
        ReferenceCameraPosition.BACK
      ),
      new ReferenceCategory(
        'free',
        'category_free',
        ReferenceCameraPosition.FRONT,
        [ReferenceCameraPosition.FRONT, ReferenceCameraPosition.BACK],
        ReferenceCategoryInput.PROMPT
      )
    ];
  }

  private static makeCategory(
    id: string,
    name: string,
    defaultCameraPosition: ReferenceCameraPosition
  ): ReferenceCategory {
    const references: Reference[] = [ReferenceDataSource.makeAddAction(id)];
    REALTIME_REFERENCE_CONFIG
      .filter((item: RealtimeReferenceConfigItem): boolean => item.category_id === id)
      .forEach((item: RealtimeReferenceConfigItem): void => {
        references.push(new Reference(
          item.id,
          id,
          item.title,
          item.icon,
          item.default_reference
        ));
      });
    return new ReferenceCategory(
      id,
      name,
      defaultCameraPosition,
      [ReferenceCameraPosition.FRONT, ReferenceCameraPosition.BACK],
      ReferenceCategoryInput.REFERENCES,
      references
    );
  }

  private static makeAddAction(categoryId: string): Reference {
    return new Reference(
      `${categoryId}-add`,
      categoryId,
      XLabLocalization.text('add_reference'),
      undefined,
      undefined,
      true
    );
  }
}
