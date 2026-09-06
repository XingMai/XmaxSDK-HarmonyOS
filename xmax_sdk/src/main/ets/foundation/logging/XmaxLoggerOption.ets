/** 控制 SDK 输出的日志类型，可使用按位或组合。 */
export enum XmaxLoggerOption {
  /** 默认关闭所有 SDK 日志。 */
  NONE = 0,
  /** API、Room、Realtime、Storage 等业务运行日志。 */
  BUSINESS = 1 << 0,
  /** 生成启动耗时、RTC 性能指标、网络质量及性能告警日志。 */
  PERFORMANCE = 1 << 1,
  /** 开启所有 SDK 日志。 */
  ALL = BUSINESS | PERFORMANCE
}
