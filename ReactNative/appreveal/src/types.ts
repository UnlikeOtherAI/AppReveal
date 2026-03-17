export interface CapturedRequest {
  id: string;
  method: string;
  url: string;
  statusCode?: number;
  requestTimestamp: number;
  responseTimestamp?: number;
  requestHeaders?: Record<string, string>;
  responseHeaders?: Record<string, string>;
  requestBodySize?: number;
  responseBodySize?: number;
  error?: string;
}
