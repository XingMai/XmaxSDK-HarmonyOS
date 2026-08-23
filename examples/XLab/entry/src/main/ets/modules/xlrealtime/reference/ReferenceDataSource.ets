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
        '换形象',
        ReferenceCameraPosition.FRONT
      ),
      ReferenceDataSource.makeCategory(
        'clothx',
        '换装',
        ReferenceCameraPosition.FRONT
      ),
      ReferenceDataSource.makeCategory(
        'vibex',
        '换风格',
        ReferenceCameraPosition.FRONT
      ),
      new ReferenceCategory(
        'mox',
        '触控动图',
        ReferenceCameraPosition.FRONT,
        [ReferenceCameraPosition.FRONT, ReferenceCameraPosition.BACK],
        ReferenceCategoryInput.INSTRUCTION,
        [],
        '在画面上拖拽，用轨迹控制角色'
      ),
      ReferenceDataSource.makeCategory(
        'dimx',
        '虚拟召唤',
        ReferenceCameraPosition.BACK
      ),
      new ReferenceCategory(
        'free',
        '自由',
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
      '添加参考图',
      undefined,
      undefined,
      true
    );
  }
}
