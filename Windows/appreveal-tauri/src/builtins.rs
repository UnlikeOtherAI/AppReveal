use crate::error::{AppRevealError, Result};
use crate::providers::{LogQuery, NetworkQuery, ProviderRegistry};
use crate::registry::{Tool, ToolRegistry};
use serde_json::{json, Map, Value};
use std::time::Duration;

const MAX_BATCH_DELAY_MS: u64 = 60_000;

pub fn registry_with_builtins(providers: ProviderRegistry) -> ToolRegistry {
    let registry = ToolRegistry::new();
    register_builtin_tools(&registry, providers)
        .expect("built-in AppReveal tools should register with valid names");
    registry
}

pub fn register_builtin_tools(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    register_list_windows(registry, providers.clone())?;
    register_launch_context(registry, providers.clone())?;
    register_device_info(registry, providers.clone())?;
    register_get_screen(registry, providers.clone())?;
    register_get_logs(registry, providers.clone())?;
    register_get_state(registry, providers.clone())?;
    register_get_navigation_stack(registry, providers.clone())?;
    register_get_feature_flags(registry, providers.clone())?;
    register_network_tools(registry, providers)?;
    register_batch(registry)?;
    Ok(())
}

fn register_list_windows(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    let available = providers.clone();
    registry.register(
        Tool::new(
            "list_windows",
            "List all visible app windows with IDs, titles, frames, and key status. Use window IDs with other tools to target specific windows.",
            object_schema(Map::new()),
            move |_| {
                let windows = providers.list_windows();
                let count = windows.len();
                Ok(json!({
                    "windows": windows,
                    "count": count
                }))
            },
        )
        .available_when(move || available.has_window_provider()),
    )
}

fn register_launch_context(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    registry.register(Tool::new(
        "launch_context",
        "Get app launch environment info",
        object_schema(Map::new()),
        move |_| Ok(providers.launch_context()),
    ))
}

fn register_device_info(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    registry.register(Tool::new(
        "device_info",
        "Return comprehensive device and app information: manifest metadata, hardware, OS build details, screen metrics, locale, timezone, battery, memory, and storage.",
        object_schema(Map::new()),
        move |_| Ok(providers.device_info()),
    ))
}

fn register_get_screen(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    let available = providers.clone();
    registry.register(
        Tool::new(
            "get_screen",
            "Get the currently active screen identity and metadata.",
            object_schema(Map::new()),
            move |_| {
                let navigation = providers.navigation_stack();
                let current_route = navigation
                    .get("currentRoute")
                    .or_else(|| navigation.get("current"))
                    .and_then(Value::as_str)
                    .unwrap_or("windows.unknown");
                let navigation_stack = navigation
                    .get("navigationStack")
                    .or_else(|| navigation.get("navigation_stack"))
                    .cloned()
                    .unwrap_or_else(|| json!([]));
                let presented_modals = navigation
                    .get("presentedModals")
                    .or_else(|| navigation.get("presented_modals"))
                    .cloned()
                    .unwrap_or_else(|| json!([]));

                Ok(json!({
                    "screenKey": current_route,
                    "screenTitle": current_route,
                    "frameworkType": "tauri",
                    "controllerChain": [],
                    "activeTab": null,
                    "navigationDepth": navigation_stack.as_array().map(Vec::len).unwrap_or(0),
                    "presentedModals": presented_modals,
                    "confidence": if current_route == "windows.unknown" { 0.25 } else { 1.0 },
                    "source": if current_route == "windows.unknown" { "derived" } else { "explicit" },
                    "appBarTitle": current_route
                }))
            },
        )
        .available_when(move || available.has_navigation_provider()),
    )
}

fn register_get_logs(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    let mut properties = Map::new();
    properties.insert(
        "subsystem".to_string(),
        json!({ "type": "string", "description": "Filter by subsystem" }),
    );
    properties.insert(
        "limit".to_string(),
        json!({ "type": "integer", "description": "Max results (default 50)" }),
    );

    let available = providers.clone();
    registry.register(
        Tool::new(
            "get_logs",
            "Get recent app logs",
            object_schema(properties),
            move |arguments| {
                let query = parse_log_query(arguments)?;
                Ok(providers.logs(query))
            },
        )
        .available_when(move || available.has_log_provider()),
    )
}

fn register_get_state(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    let available = providers.clone();
    registry.register(
        Tool::new(
            "get_state",
            "Get the current app state snapshot",
            object_schema(Map::new()),
            move |_| Ok(providers.state()),
        )
        .available_when(move || available.has_state_provider()),
    )
}

fn register_get_navigation_stack(
    registry: &ToolRegistry,
    providers: ProviderRegistry,
) -> Result<()> {
    let available = providers.clone();
    registry.register(
        Tool::new(
            "get_navigation_stack",
            "Get the current navigation state",
            object_schema(Map::new()),
            move |_| Ok(providers.navigation_stack()),
        )
        .available_when(move || available.has_navigation_provider()),
    )
}

fn register_get_feature_flags(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    let available = providers.clone();
    registry.register(
        Tool::new(
            "get_feature_flags",
            "Get all active feature flags",
            object_schema(Map::new()),
            move |_| Ok(providers.feature_flags()),
        )
        .available_when(move || available.has_feature_flag_provider()),
    )
}

fn register_network_tools(registry: &ToolRegistry, providers: ProviderRegistry) -> Result<()> {
    let mut call_properties = Map::new();
    call_properties.insert("limit".to_string(), json!({ "type": "integer" }));
    let available = providers.clone();
    registry.register(
        Tool::new(
            "get_network_calls",
            "Recent HTTP traffic captured by the app.",
            object_schema(call_properties),
            move |arguments| {
                let query = parse_network_query(arguments)?;
                Ok(providers.network_calls(query))
            },
        )
        .available_when(move || available.has_network_provider()),
    )
}

fn register_batch(registry: &ToolRegistry) -> Result<()> {
    let batch_registry = registry.clone();
    let mut properties = Map::new();
    properties.insert(
        "actions".to_string(),
        json!({
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "tool": { "type": "string" },
                    "arguments": { "type": "object" },
                    "delay_ms": {
                        "type": "integer",
                        "minimum": 0,
                        "maximum": MAX_BATCH_DELAY_MS
                    }
                },
                "required": ["tool"]
            }
        }),
    );
    properties.insert("stop_on_error".to_string(), json!({ "type": "boolean" }));
    registry.register(Tool::new(
        "batch",
        "Execute multiple tool calls in one request.",
        object_schema(properties),
        move |arguments| {
            let arguments = arguments.and_then(Value::as_object).ok_or_else(|| {
                AppRevealError::InvalidParams("arguments must be an object".to_string())
            })?;
            let actions = arguments
                .get("actions")
                .and_then(Value::as_array)
                .ok_or_else(|| {
                    AppRevealError::InvalidParams("actions array required".to_string())
                })?;

            let stop_on_error = match arguments.get("stop_on_error") {
                Some(value) => value.as_bool().ok_or_else(|| {
                    AppRevealError::InvalidParams("stop_on_error must be a boolean".to_string())
                })?,
                None => false,
            };

            let mut results = Vec::with_capacity(actions.len());

            for (index, action) in actions.iter().enumerate() {
                let Some(action) = action.as_object() else {
                    push_batch_error(&mut results, index, None, "action must be an object");
                    if stop_on_error {
                        break;
                    }
                    continue;
                };

                let tool_name = match action.get("tool").and_then(Value::as_str) {
                    Some(tool_name) if !tool_name.trim().is_empty() => tool_name,
                    _ => {
                        push_batch_error(&mut results, index, None, "tool is required");
                        if stop_on_error {
                            break;
                        }
                        continue;
                    }
                };

                let delay_ms = match parse_batch_delay_ms(action.get("delay_ms")) {
                    Ok(delay_ms) => delay_ms,
                    Err(error) => {
                        push_batch_error(&mut results, index, Some(tool_name), error);
                        if stop_on_error {
                            break;
                        }
                        continue;
                    }
                };

                let action_arguments = match action.get("arguments") {
                    Some(value) if !value.is_object() && !value.is_null() => {
                        push_batch_error(
                            &mut results,
                            index,
                            Some(tool_name),
                            "arguments must be an object",
                        );
                        if stop_on_error {
                            break;
                        }
                        continue;
                    }
                    Some(value) if value.is_null() => None,
                    value => value,
                };

                if delay_ms > 0 {
                    std::thread::sleep(Duration::from_millis(delay_ms));
                }

                let result = match batch_registry.tool(tool_name)? {
                    Some(tool) => tool.call(action_arguments),
                    None => Err(AppRevealError::ToolNotFound(tool_name.to_string())),
                };

                match result {
                    Ok(value) => results.push(json!({
                        "index": index,
                        "tool": tool_name,
                        "success": true,
                        "result": value
                    })),
                    Err(error) => {
                        results.push(json!({
                            "index": index,
                            "tool": tool_name,
                            "success": false,
                            "error": error.to_string()
                        }));
                        if stop_on_error {
                            break;
                        }
                    }
                }
            }

            Ok(json!({ "results": results }))
        },
    ))
}

fn parse_batch_delay_ms(value: Option<&Value>) -> std::result::Result<u64, &'static str> {
    let Some(value) = value else {
        return Ok(0);
    };

    let Some(delay_ms) = value.as_u64() else {
        return Err("delay_ms must be a non-negative integer");
    };

    if delay_ms > MAX_BATCH_DELAY_MS {
        return Err("delay_ms exceeds maximum of 60000");
    }

    Ok(delay_ms)
}

fn push_batch_error(
    results: &mut Vec<Value>,
    index: usize,
    tool_name: Option<&str>,
    error: impl Into<String>,
) {
    let mut result = Map::new();
    result.insert("index".to_string(), json!(index));
    if let Some(tool_name) = tool_name {
        result.insert("tool".to_string(), json!(tool_name));
    }
    result.insert("success".to_string(), json!(false));
    result.insert("error".to_string(), json!(error.into()));
    results.push(Value::Object(result));
}

fn object_schema(properties: Map<String, Value>) -> Value {
    json!({
        "type": "object",
        "properties": properties
    })
}

fn parse_log_query(arguments: Option<&Value>) -> Result<LogQuery> {
    let Some(arguments) = arguments else {
        return Ok(LogQuery::default());
    };

    let Some(arguments) = arguments.as_object() else {
        return Err(AppRevealError::InvalidParams(
            "arguments must be an object".to_string(),
        ));
    };

    let subsystem = arguments
        .get("subsystem")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty())
        .map(ToOwned::to_owned);

    let limit = arguments
        .get("limit")
        .and_then(Value::as_u64)
        .map(|limit| limit as usize)
        .unwrap_or(50);

    Ok(LogQuery { subsystem, limit })
}

fn parse_network_query(arguments: Option<&Value>) -> Result<NetworkQuery> {
    let Some(arguments) = arguments else {
        return Ok(NetworkQuery::default());
    };

    let Some(arguments) = arguments.as_object() else {
        return Err(AppRevealError::InvalidParams(
            "arguments must be an object".to_string(),
        ));
    };

    let limit = arguments
        .get("limit")
        .and_then(Value::as_u64)
        .map(|limit| limit as usize)
        .unwrap_or(50);

    Ok(NetworkQuery { limit })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn listed_tool_names(registry: &ToolRegistry) -> Vec<String> {
        registry
            .list()
            .unwrap()
            .into_iter()
            .map(|tool| tool.name)
            .collect()
    }

    #[test]
    fn default_registry_advertises_only_always_functional_tools() {
        let registry = registry_with_builtins(ProviderRegistry::new());

        assert_eq!(
            listed_tool_names(&registry),
            vec!["batch", "device_info", "launch_context"]
        );
        assert!(registry.tool("list_windows").unwrap().is_none());
        assert!(registry.tool("get_state").unwrap().is_none());
        assert!(registry.tool("get_recent_errors").unwrap().is_none());
    }

    #[test]
    fn provider_backed_tool_is_advertised_after_late_provider_registration() {
        let providers = ProviderRegistry::new();
        let registry = registry_with_builtins(providers.clone());

        assert!(!listed_tool_names(&registry).contains(&"get_state".to_string()));
        assert!(registry.tool("get_state").unwrap().is_none());

        providers.set_state_provider(|| json!({ "screen": "cart" }));

        assert!(listed_tool_names(&registry).contains(&"get_state".to_string()));
        let state = registry.tool("get_state").unwrap().unwrap();
        assert_eq!(state.call(None).unwrap(), json!({ "screen": "cart" }));
    }

    #[test]
    fn batch_rejects_non_object_action_arguments() {
        let registry = registry_with_builtins(ProviderRegistry::new());
        let batch = registry.tool("batch").unwrap().unwrap();

        let result = batch
            .call(Some(&json!({
                "actions": [
                    { "tool": "get_state", "arguments": [] }
                ]
            })))
            .unwrap();

        assert_eq!(result["results"][0]["success"], false);
        assert_eq!(
            result["results"][0]["error"],
            json!("arguments must be an object")
        );
    }

    #[test]
    fn batch_rejects_negative_delay() {
        let registry = registry_with_builtins(ProviderRegistry::new());
        let batch = registry.tool("batch").unwrap().unwrap();

        let result = batch
            .call(Some(&json!({
                "actions": [
                    { "tool": "get_state", "delay_ms": -1 }
                ]
            })))
            .unwrap();

        assert_eq!(result["results"][0]["success"], false);
        assert_eq!(
            result["results"][0]["error"],
            json!("delay_ms must be a non-negative integer")
        );
    }

    #[test]
    fn network_calls_without_provider_is_not_advertised_or_callable() {
        let registry = registry_with_builtins(ProviderRegistry::new());

        assert!(!listed_tool_names(&registry).contains(&"get_network_calls".to_string()));
        assert!(registry.tool("get_network_calls").unwrap().is_none());
    }

    #[test]
    fn network_calls_use_registered_provider() {
        let providers = ProviderRegistry::new();
        providers.set_network_provider(|query| {
            json!({
                "calls": [{ "url": "https://example.test" }],
                "limit": query.limit
            })
        });
        let registry = registry_with_builtins(providers);
        let network = registry.tool("get_network_calls").unwrap().unwrap();

        let result = network.call(Some(&json!({ "limit": 7 }))).unwrap();

        assert_eq!(result["calls"][0]["url"], json!("https://example.test"));
        assert_eq!(result["limit"], json!(7));
    }
}
