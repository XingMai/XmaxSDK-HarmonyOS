//
//  ApiServicing.ets
//  XmaxSDK
//
//  Author: 翁跃庭 (Yueting Weng)
//  GitHub: https://github.com/Xmax-AI/XmaxSDK-HarmonyOS
//
//  Copyright (c) 2026 XMAX.AI PTE. LTD.
//

/** An interface for Xmax API requests. */
export interface ApiServicing {

  /**
   * Sends a GET request.
   *
   * @param path The request path.
   *
   * @returns The response data.
   */
  get<T>(
    path: string
  ): Promise<T>;

  /**
   * Sends a POST request.
   *
   * @param path The request path.
   * @param body The request body.
   *
   * @returns The response data.
   */
  post<T>(
    path: string,
    body?: Object
  ): Promise<T>;

  /**
   * Sends a PUT request.
   *
   * @param path The request path.
   * @param body The request body.
   *
   * @returns The response data.
   */
  put<T>(
    path: string,
    body?: Object
  ): Promise<T>;

  /**
   * Sends a DELETE request.
   *
   * @param path The request path.
   *
   * @returns The response data.
   */
  delete<T>(
    path: string
  ): Promise<T>;
}
