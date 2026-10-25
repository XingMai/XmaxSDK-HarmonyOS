//
//  RealtimeInteraction.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** Valid media interaction phases, notified on the first finger down and last finger up. */
export type RealtimeInteractionPhase = 'began' | 'ended' | 'cancelled';

/**
 * Reports valid interaction start, end, or cancellation; padding touches do not trigger it.
 *
 * @param phase The phase; disabling, layout changes, and track release report cancelled.
 */
export type RealtimeInteractionListener = (
  phase: RealtimeInteractionPhase
) => void;
