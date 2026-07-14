use crate::error::{AppRevealError, Result};
use crate::registry::ToolRegistry;
use crate::{APPREVEAL_PROTOCOL_VERSION, APPREVEAL_SERVER_NAME, APPREVEAL_VERSION};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};

#[derive(Debug, Clone, Deserialize, PartialEq)]
pub struct JsonRpcRequest {
    #[serde(default)]
    #[allow(dead_code)]
    pub jsonrpc: Option<String>,
    #[serde(default)]
    pub id: Option<Value>,
    #[serde(default)]
    pub method: String,
    #[serde(default)]
    pub params: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct JsonRpcRequestEnvelope {
    pub request: JsonRpcRequest,
    pub expects_response: bool,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct JsonRpcResponse {
    pub jsonrpc: &'static str,
    pub id: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<RpcError>,
}

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct RpcError {
    pub code: i32,
    pub message: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Value>,
}

impl JsonRpcResponse {
    pub fn success(id: Option<Value>, result: Value) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: Some(result),
            error: None,
        }
    }

    pub fn error(id: Option<Value>, error: RpcError) -> Self {
        Self {
            jsonrpc: "2.0",
            id,
            result: None,
            error: Some(error),
        }
    }
}

impl RpcError {
    pub fn parse_error(detail: impl Into<String>) -> Self {
        Self {
            code: -32700,
            message: format!("Parse error: {}", detail.into()),
            data: None,
        }
    }

    pub fn method_not_found(method: impl AsRef<str>) -> Self {
        Self {
            code: -32601,
            message: format!("Method not found: {}", method.as_ref()),
            data: None,
        }
    }

    pub fn invalid_request(detail: impl Into<String>) -> Self {
        Self {
            code: -32600,
            message: format!("Invalid Request: {}", detail.into()),
            data: None,
        }
    }

    pub fn invalid_params(detail: impl Into<String>) -> Self {
        Self {
            code: -32602,
            message: format!("Invalid params: {}", detail.into()),
            data: None,
        }
    }

    pub fn internal_error(detail: impl Into<String>) -> Self {
        Self {
            code: -32603,
            message: detail.into(),
            data: None,
        }
    }
}

pub(crate) fn parse_json_rpc_request(
    body: &[u8],
) -> std::result::Result<JsonRpcRequestEnvelope, Box<JsonRpcResponse>> {
    let value = serde_json::from_slice::<Value>(body).map_err(|error| {
        Box::new(JsonRpcResponse::error(
            None,
            RpcError::parse_error(error.to_string()),
        ))
    })?;

    let Some(object) = value.as_object() else {
        return Err(Box::new(JsonRpcResponse::error(
            None,
            RpcError::invalid_request("request must be an object"),
        )));
    };

    validate_json_rpc_object(object)?;

    let expects_response = object.contains_key("id");
    let request = serde_json::from_value::<JsonRpcRequest>(value).map_err(|error| {
        Box::new(JsonRpcResponse::error(
            None,
            RpcError::invalid_request(error.to_string()),
        ))
    })?;

    Ok(JsonRpcRequestEnvelope {
        request,
        expects_response,
    })
}

fn validate_json_rpc_object(
    object: &Map<String, Value>,
) -> std::result::Result<(), Box<JsonRpcResponse>> {
    let response_id = object.get("id").and_then(valid_response_id);

    match object.get("jsonrpc") {
        Some(Value::String(version)) if version == "2.0" => {}
        Some(_) => {
            return Err(Box::new(JsonRpcResponse::error(
                response_id,
                RpcError::invalid_request("jsonrpc must be \"2.0\""),
            )));
        }
        None => {
            return Err(Box::new(JsonRpcResponse::error(
                response_id,
                RpcError::invalid_request("jsonrpc is required"),
            )));
        }
    }

    match object.get("method") {
        Some(Value::String(method)) if !method.is_empty() => {}
        Some(Value::String(_)) => {
            return Err(Box::new(JsonRpcResponse::error(
                response_id,
                RpcError::invalid_request("method must not be empty"),
            )));
        }
        Some(_) => {
            return Err(Box::new(JsonRpcResponse::error(
                response_id,
                RpcError::invalid_request("method must be a string"),
            )));
        }
        None => {
            return Err(Box::new(JsonRpcResponse::error(
                response_id,
                RpcError::invalid_request("method is required"),
            )));
        }
    }

    if let Some(id) = object.get("id") {
        if valid_response_id(id).is_none() && !id.is_null() {
            return Err(Box::new(JsonRpcResponse::error(
                None,
                RpcError::invalid_request("id must be a string, number, or null"),
            )));
        }
    }

    Ok(())
}

fn valid_response_id(id: &Value) -> Option<Value> {
    match id {
        Value::Null | Value::String(_) | Value::Number(_) => Some(id.clone()),
        _ => None,
    }
}

pub fn handle_request(registry: &ToolRegistry, request: JsonRpcRequest) -> JsonRpcResponse {
    if request.jsonrpc.as_deref() != Some("2.0") {
        return JsonRpcResponse::error(
            request.id,
            RpcError::invalid_request("jsonrpc must be \"2.0\""),
        );
    }

    if request.method.is_empty() {
        return JsonRpcResponse::error(
            request.id,
            RpcError::invalid_request("method must not be empty"),
        );
    }

    match request.method.as_str() {
        "initialize" => JsonRpcResponse::success(request.id, initialize_result()),
        "ping" => JsonRpcResponse::success(request.id, json!({})),
        "tools/list" => match registry.list() {
            Ok(tools) => JsonRpcResponse::success(request.id, json!({ "tools": tools })),
            Err(error) => {
                JsonRpcResponse::error(request.id, RpcError::internal_error(error.to_string()))
            }
        },
        "tools/call" => handle_tool_call(registry, request),
        _ => JsonRpcResponse::error(request.id, RpcError::method_not_found(request.method)),
    }
}

fn initialize_result() -> Value {
    json!({
        "protocolVersion": APPREVEAL_PROTOCOL_VERSION,
        "capabilities": {
            "tools": {}
        },
        "serverInfo": {
            "name": APPREVEAL_SERVER_NAME,
            "version": APPREVEAL_VERSION
        }
    })
}

fn handle_tool_call(registry: &ToolRegistry, request: JsonRpcRequest) -> JsonRpcResponse {
    let id = request.id;
    let params = match request.params.as_ref().and_then(Value::as_object) {
        Some(params) => params,
        None => {
            return JsonRpcResponse::error(id, RpcError::invalid_params("Missing tool name"));
        }
    };

    let Some(tool_name) = params.get("name").and_then(Value::as_str) else {
        return JsonRpcResponse::error(id, RpcError::invalid_params("Missing tool name"));
    };

    let arguments = params.get("arguments").filter(|value| !value.is_null());
    if matches!(arguments, Some(value) if !value.is_object()) {
        return JsonRpcResponse::error(id, RpcError::invalid_params("arguments must be an object"));
    }

    let tool = match registry.tool(tool_name) {
        Ok(Some(tool)) => tool,
        Ok(None) => {
            return JsonRpcResponse::error(id, RpcError::method_not_found(tool_name));
        }
        Err(error) => {
            return JsonRpcResponse::error(id, RpcError::internal_error(error.to_string()));
        }
    };

    match tool
        .call(arguments)
        .and_then(|value| tool_call_result(tool_name, value))
    {
        Ok(result) => JsonRpcResponse::success(id, result),
        Err(error) => JsonRpcResponse::error(id, RpcError::internal_error(error.to_string())),
    }
}

fn tool_call_result(tool_name: &str, value: Value) -> Result<Value> {
    if tool_name != "screenshot" {
        return text_tool_result(value, false);
    }

    let Some(screenshot) = value.as_object() else {
        return text_tool_result(value, true);
    };
    let Some(image_data) = screenshot
        .get("image")
        .and_then(Value::as_str)
        .filter(|data| !data.trim().is_empty())
    else {
        return text_tool_result(value, true);
    };

    let format = screenshot
        .get("format")
        .and_then(Value::as_str)
        .unwrap_or("png")
        .to_ascii_lowercase();
    let mime_type = if format == "jpeg" || format == "jpg" {
        "image/jpeg"
    } else {
        "image/png"
    };
    let mut metadata = screenshot.clone();
    metadata.remove("image");
    let metadata = Value::Object(metadata);
    let metadata_text = serde_json::to_string(&metadata).map_err(AppRevealError::from)?;

    Ok(json!({
        "content": [
            {
                "type": "image",
                "data": image_data,
                "mimeType": mime_type
            },
            {
                "type": "text",
                "text": metadata_text
            }
        ],
        "structuredContent": metadata
    }))
}

fn text_tool_result(value: Value, is_error: bool) -> Result<Value> {
    serde_json::to_string(&value)
        .map_err(AppRevealError::from)
        .map(|text| {
            let mut result = json!({
                "content": [
                    {
                        "type": "text",
                        "text": text
                    }
                ]
            });
            if is_error {
                result["isError"] = json!(true);
            }
            result
        })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{registry_with_builtins, ProviderRegistry, Tool};

    #[test]
    fn initialize_returns_appreveal_server_info() {
        let registry = ToolRegistry::new();
        let response = handle_request(
            &registry,
            JsonRpcRequest {
                jsonrpc: Some("2.0".to_string()),
                id: Some(json!(1)),
                method: "initialize".to_string(),
                params: None,
            },
        );

        assert_eq!(response.error, None);
        assert_eq!(
            response.result.unwrap()["protocolVersion"],
            APPREVEAL_PROTOCOL_VERSION
        );
    }

    #[test]
    fn tools_call_wraps_handler_json_as_text_content() {
        let providers = ProviderRegistry::new();
        providers.set_state_provider(|| json!({ "cartCount": 2 }));
        let registry = registry_with_builtins(providers);

        let response = handle_request(
            &registry,
            JsonRpcRequest {
                jsonrpc: Some("2.0".to_string()),
                id: Some(json!("abc")),
                method: "tools/call".to_string(),
                params: Some(json!({
                    "name": "get_state",
                    "arguments": {}
                })),
            },
        );

        let text = response.result.unwrap()["content"][0]["text"]
            .as_str()
            .unwrap()
            .to_string();
        assert_eq!(
            serde_json::from_str::<Value>(&text).unwrap(),
            json!({ "cartCount": 2 })
        );
    }

    #[test]
    fn screenshot_returns_image_content_and_metadata() {
        for (format, mime_type) in [("png", "image/png"), ("jpeg", "image/jpeg")] {
            let registry = ToolRegistry::new();
            registry
                .register(Tool::new(
                    "screenshot",
                    "Screenshot",
                    json!({ "type": "object" }),
                    move |_| {
                        Ok(json!({
                            "image": format!("base64-{format}"),
                            "width": 100,
                            "height": 200,
                            "scale": 2.0,
                            "format": format
                        }))
                    },
                ))
                .unwrap();

            let response = handle_request(
                &registry,
                JsonRpcRequest {
                    jsonrpc: Some("2.0".to_string()),
                    id: Some(json!(1)),
                    method: "tools/call".to_string(),
                    params: Some(json!({
                        "name": "screenshot",
                        "arguments": {}
                    })),
                },
            );

            let result = response.result.unwrap();
            assert_eq!(result["content"][0]["type"], json!("image"));
            assert_eq!(
                result["content"][0]["data"],
                json!(format!("base64-{format}"))
            );
            assert_eq!(result["content"][0]["mimeType"], json!(mime_type));
            assert!(result["structuredContent"].get("image").is_none());
            assert_eq!(result["structuredContent"]["width"], json!(100));
            let metadata = result["content"][1]["text"].as_str().unwrap();
            assert_eq!(
                serde_json::from_str::<Value>(metadata).unwrap(),
                result["structuredContent"]
            );
        }
    }

    #[test]
    fn failed_screenshot_is_text_content_marked_as_error() {
        let registry = ToolRegistry::new();
        registry
            .register(Tool::new(
                "screenshot",
                "Screenshot",
                json!({ "type": "object" }),
                |_| Ok(json!({ "error": "capture failed" })),
            ))
            .unwrap();

        let response = handle_request(
            &registry,
            JsonRpcRequest {
                jsonrpc: Some("2.0".to_string()),
                id: Some(json!(1)),
                method: "tools/call".to_string(),
                params: Some(json!({
                    "name": "screenshot",
                    "arguments": {}
                })),
            },
        );

        let result = response.result.unwrap();
        assert_eq!(result["content"][0]["type"], json!("text"));
        assert_eq!(result["isError"], json!(true));
        assert!(result.get("structuredContent").is_none());
    }

    #[test]
    fn ping_returns_empty_result() {
        let registry = ToolRegistry::new();
        let response = handle_request(
            &registry,
            JsonRpcRequest {
                jsonrpc: Some("2.0".to_string()),
                id: Some(json!(99)),
                method: "ping".to_string(),
                params: None,
            },
        );

        assert_eq!(response.error, None);
        assert_eq!(response.result, Some(json!({})));
    }

    #[test]
    fn parse_rejects_missing_jsonrpc() {
        let response = parse_json_rpc_request(
            json!({
                "id": 1,
                "method": "ping"
            })
            .to_string()
            .as_bytes(),
        )
        .unwrap_err();

        assert_eq!(response.error.unwrap().code, -32600);
    }

    #[test]
    fn parse_marks_requests_without_id_as_notifications() {
        let envelope = parse_json_rpc_request(
            json!({
                "jsonrpc": "2.0",
                "method": "ping"
            })
            .to_string()
            .as_bytes(),
        )
        .unwrap();

        assert!(!envelope.expects_response);
        assert_eq!(envelope.request.method, "ping");
    }
}
