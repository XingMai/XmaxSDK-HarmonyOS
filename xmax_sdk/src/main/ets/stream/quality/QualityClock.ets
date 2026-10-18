import systemDateTime from '@ohos.systemDateTime';

/** 调档采样和冷却使用单调时钟，单位秒。 */
export class QualityClock {
  static now(): number {
    return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, true) / 1000000000;
  }
}
