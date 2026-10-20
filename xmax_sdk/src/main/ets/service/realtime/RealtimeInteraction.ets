//
//  RealtimeInteraction.ets
//  XmaxSDK
//  Repo: https://github.com/XingMai/XmaxSDK-HarmonyOS
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/WengYuehTing
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** 有效画面内交互的生命周期；多指交互在首指按下及末指抬起时通知。 */
export type RealtimeInteractionPhase = 'began' | 'ended' | 'cancelled';

/**
 * 通知有效轨迹交互开始、结束或取消；留白触摸不会触发。
 *
 * @param phase 交互阶段；禁用、布局变化及轨道释放会发送 cancelled。
 * @returns 无返回值。
 */
export type RealtimeInteractionListener = (phase: RealtimeInteractionPhase) => void;
