/** 定义 Xmax API 的基础请求能力。 */
export interface ApiServicing {

  /**
   * 发送 GET 请求。
   *
   * @param path 请求路径。
   * @returns 响应数据。
   */
  get<T>(path: string): Promise<T>;

  /**
   * 发送 POST 请求。
   *
   * @param path 请求路径。
   * @param body 请求体。
   * @returns 响应数据。
   */
  post<T>(
    path: string,
    body?: Object
  ): Promise<T>;

  /**
   * 发送 PUT 请求。
   *
   * @param path 请求路径。
   * @param body 请求体。
   * @returns 响应数据。
   */
  put<T>(
    path: string,
    body?: Object
  ): Promise<T>;

  /**
   * 发送 DELETE 请求。
   *
   * @param path 请求路径。
   * @returns 响应数据。
   */
  delete<T>(path: string): Promise<T>;
}
