use crate::error::AppRevealError;
use crate::providers::{current_executable_name, default_device_name};
use crate::{
    registry_with_builtins, start_server, ProviderRegistry, Result, ServerConfig, ServerHandle,
    Tool, ToolRegistry, WindowInfo,
};
use serde_json::{json, Map, Value};
use std::net::SocketAddr;
use std::sync::mpsc;
use std::sync::{Mutex, MutexGuard};
use std::time::Duration;
use tauri::menu::MenuItemKind;
use tauri::plugin::{Builder, TauriPlugin};
use tauri::{Manager, Runtime, WebviewWindow};

const APPREVEAL_PLUGIN_NAME: &str = "appreveal";
const DEFAULT_EVAL_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Clone, Debug)]
pub struct TauriPluginConfig {
    pub server_config: ServerConfig,
    pub debug_only: bool,
    pub print_session_url: bool,
}

impl Default for TauriPluginConfig {
    fn default() -> Self {
        Self {
            server_config: ServerConfig::any_interface(0)
                .with_bonjour_service_name("AppReveal-Tauri"),
            debug_only: true,
            print_session_url: true,
        }
    }
}

pub fn init<R>() -> TauriPlugin<R>
where
    R: Runtime,
{
    init_with_config(TauriPluginConfig::default())
}

pub fn init_with_config<R>(config: TauriPluginConfig) -> TauriPlugin<R>
where
    R: Runtime,
{
    Builder::new(APPREVEAL_PLUGIN_NAME)
        .setup(move |app, _api| {
            if config.debug_only && !cfg!(debug_assertions) {
                return Ok(());
            }

            let mut server_config = config.server_config.clone();
            enrich_bonjour_config(app, &mut server_config);
            start_tauri_server_managed(app.clone(), server_config).map_err(
                |error| -> Box<dyn std::error::Error> {
                    Box::new(std::io::Error::other(error.to_string()))
                },
            )?;

            if config.print_session_url {
                if let Ok(Some(url)) = app.state::<AppRevealTauriServer>().session_url() {
                    println!("[AppReveal] Tauri MCP listening at {url}");
                }
            }

            Ok(())
        })
        .build()
}

pub fn providers_from_tauri<R>(app: tauri::AppHandle<R>) -> ProviderRegistry
where
    R: Runtime,
{
    let providers = ProviderRegistry::new();
    configure_tauri_providers(&providers, app);
    providers
}

pub fn configure_tauri_providers<R>(providers: &ProviderRegistry, app: tauri::AppHandle<R>)
where
    R: Runtime,
{
    let launch_app = app.clone();
    providers.set_launch_context_provider(move || tauri_launch_context(&launch_app));

    let device_app = app.clone();
    providers.set_device_info_provider(move || tauri_device_info(&device_app));

    providers.set_window_provider(move || tauri_windows(&app));
}

pub fn start_tauri_server<R>(app: tauri::AppHandle<R>, config: ServerConfig) -> Result<ServerHandle>
where
    R: Runtime,
{
    let providers = providers_from_tauri(app.clone());
    let registry = registry_with_builtins(providers);
    register_tauri_tools(&registry, app)?;
    start_server(config, registry)
}

pub fn start_tauri_server_managed<R>(
    app: tauri::AppHandle<R>,
    config: ServerConfig,
) -> Result<SocketAddr>
where
    R: Runtime,
{
    if app.try_state::<AppRevealTauriServer>().is_none() {
        let _ = app.manage(AppRevealTauriServer::default());
    }

    let server_app = app.clone();
    let server = app.state::<AppRevealTauriServer>();
    server.start(server_app, config)
}

#[derive(Default)]
pub struct AppRevealTauriServer {
    handle: Mutex<Option<ServerHandle>>,
}

impl AppRevealTauriServer {
    pub fn start<R>(&self, app: tauri::AppHandle<R>, config: ServerConfig) -> Result<SocketAddr>
    where
        R: Runtime,
    {
        let mut handle = self.lock_handle()?;
        if handle.is_some() {
            return Err(AppRevealError::AlreadyStarted);
        }

        let server = start_tauri_server(app, config)?;
        let local_addr = server.local_addr();
        *handle = Some(server);
        Ok(local_addr)
    }

    pub fn stop(&self) -> Result<()> {
        let Some(mut handle) = self.lock_handle()?.take() else {
            return Ok(());
        };

        handle.stop()
    }

    pub fn local_addr(&self) -> Result<Option<SocketAddr>> {
        Ok(self.lock_handle()?.as_ref().map(ServerHandle::local_addr))
    }

    pub fn session_token(&self) -> Result<Option<String>> {
        Ok(self
            .lock_handle()?
            .as_ref()
            .and_then(|handle| handle.session_token().map(ToOwned::to_owned)))
    }

    pub fn session_url(&self) -> Result<Option<String>> {
        Ok(self.lock_handle()?.as_ref().map(ServerHandle::session_url))
    }

    pub fn is_running(&self) -> Result<bool> {
        Ok(self.lock_handle()?.is_some())
    }

    fn lock_handle(&self) -> Result<MutexGuard<'_, Option<ServerHandle>>> {
        self.handle
            .lock()
            .map_err(|_| AppRevealError::Protocol("Tauri server handle poisoned".to_string()))
    }
}

fn register_tauri_tools<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    register_get_elements(registry, app.clone())?;
    register_get_dom_interactive(registry, app.clone())?;
    register_tap_element(registry, app.clone())?;
    register_tap_text(registry, app.clone())?;
    register_tap_point(registry, app.clone())?;
    register_type_text(registry, app.clone())?;
    register_clear_text(registry, app.clone())?;
    register_focus_window(registry, app.clone())?;
    register_get_menu_bar(registry, app)?;
    Ok(())
}

fn register_get_elements<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "get_elements",
        "List visible interactive DOM elements from Tauri WebViews, including AppReveal IDs, selectors, labels, roles, actions, and screen frames.",
        object_schema(properties),
        move |arguments| {
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            collect_dom_elements(&app, window_id.as_deref())
        },
    ))
}

fn register_get_dom_interactive<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "get_dom_interactive",
        "Return the live interactive DOM inventory for each Tauri WebView window.",
        object_schema(properties),
        move |arguments| {
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            collect_dom_elements(&app, window_id.as_deref())
        },
    ))
}

fn register_tap_element<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("id".to_string(), json!({ "type": "string" }));
    properties.insert("elementId".to_string(), json!({ "type": "string" }));
    properties.insert("selector".to_string(), json!({ "type": "string" }));
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "tap_element",
        "Tap a Tauri WebView DOM element by AppReveal ID, DOM id, data-testid, or CSS selector.",
        object_schema(properties),
        move |arguments| {
            let target = required_string_arg(arguments, &["id", "elementId", "selector"])?;
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            interact_with_dom(&app, "tap_element", &target, None, window_id.as_deref())
        },
    ))
}

fn register_tap_text<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("text".to_string(), json!({ "type": "string" }));
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "tap_text",
        "Tap a Tauri WebView DOM element by visible text or accessible label.",
        object_schema(properties),
        move |arguments| {
            let text = required_string_arg(arguments, &["text"])?;
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            interact_with_dom(&app, "tap_text", &text, None, window_id.as_deref())
        },
    ))
}

fn register_tap_point<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("x".to_string(), json!({ "type": "number" }));
    properties.insert("y".to_string(), json!({ "type": "number" }));
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "tap_point",
        "Tap a point inside a Tauri WebView. Screen coordinates are converted to WebView-local DOM coordinates when possible.",
        object_schema(properties),
        move |arguments| {
            let x = required_number_arg(arguments, "x")?;
            let y = required_number_arg(arguments, "y")?;
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            tap_dom_point(&app, x, y, window_id.as_deref())
        },
    ))
}

fn register_type_text<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("id".to_string(), json!({ "type": "string" }));
    properties.insert("elementId".to_string(), json!({ "type": "string" }));
    properties.insert("selector".to_string(), json!({ "type": "string" }));
    properties.insert("text".to_string(), json!({ "type": "string" }));
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "type_text",
        "Type text into a Tauri WebView DOM input, textarea, select, or contenteditable element.",
        object_schema(properties),
        move |arguments| {
            let target = required_string_arg(arguments, &["id", "elementId", "selector"])?;
            let text = required_string_arg(arguments, &["text"])?;
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            interact_with_dom(
                &app,
                "type_text",
                &target,
                Some(&text),
                window_id.as_deref(),
            )
        },
    ))
}

fn register_clear_text<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("id".to_string(), json!({ "type": "string" }));
    properties.insert("elementId".to_string(), json!({ "type": "string" }));
    properties.insert("selector".to_string(), json!({ "type": "string" }));
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "clear_text",
        "Clear text in a Tauri WebView DOM input, textarea, select, or contenteditable element.",
        object_schema(properties),
        move |arguments| {
            let target = required_string_arg(arguments, &["id", "elementId", "selector"])?;
            let window_id = optional_string_arg(arguments, &["window_id", "windowId"]);
            interact_with_dom(&app, "clear_text", &target, None, window_id.as_deref())
        },
    ))
}

fn register_focus_window<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    let mut properties = Map::new();
    properties.insert("window_id".to_string(), json!({ "type": "string" }));
    properties.insert("windowId".to_string(), json!({ "type": "string" }));
    registry.register(Tool::new(
        "focus_window",
        "Focus a Tauri WebView window by label.",
        object_schema(properties),
        move |arguments| {
            let window_id = required_string_arg(arguments, &["window_id", "windowId"])?;
            let Some(window) = app.get_webview_window(&window_id) else {
                return Ok(json!({
                    "success": false,
                    "error": "window_not_found",
                    "windowId": window_id
                }));
            };

            match window.set_focus() {
                Ok(()) => Ok(json!({ "success": true, "windowId": window_id })),
                Err(error) => Ok(json!({
                    "success": false,
                    "error": error.to_string(),
                    "windowId": window_id
                })),
            }
        },
    ))
}

fn register_get_menu_bar<R>(registry: &ToolRegistry, app: tauri::AppHandle<R>) -> Result<()>
where
    R: Runtime,
{
    registry.register(Tool::new(
        "get_menu_bar",
        "Inspect the current Tauri application menu tree when the runtime exposes one.",
        object_schema(Map::new()),
        move |_| tauri_menu_bar(&app),
    ))
}

fn collect_dom_elements<R>(app: &tauri::AppHandle<R>, window_id: Option<&str>) -> Result<Value>
where
    R: Runtime,
{
    let mut flattened = Vec::new();
    let mut webviews = Vec::new();

    for (label, window) in filtered_webview_windows(app, window_id) {
        let snapshot = eval_json(&window, DOM_SNAPSHOT_JS.to_string())?;
        let origin = window_css_origin(&window);
        let mut elements = Vec::new();

        for element in snapshot
            .get("elements")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default()
        {
            let index = element.get("index").and_then(Value::as_u64).unwrap_or(0);
            let rect = element.get("rect").cloned().unwrap_or_else(|| json!({}));
            let local_x = rect.get("x").and_then(Value::as_f64).unwrap_or(0.0);
            let local_y = rect.get("y").and_then(Value::as_f64).unwrap_or(0.0);
            let width = rect.get("width").and_then(Value::as_f64).unwrap_or(0.0);
            let height = rect.get("height").and_then(Value::as_f64).unwrap_or(0.0);
            let screen_x = origin.0 + local_x;
            let screen_y = origin.1 + local_y;
            let id = format!("web.{label}.{index}");

            let mapped = json!({
                "id": id,
                "windowId": label,
                "source": "tauri_webview_dom",
                "idSource": "dom",
                "domId": element.get("id").cloned().unwrap_or(Value::Null),
                "selector": element.get("selector").cloned().unwrap_or(Value::Null),
                "label": element.get("label").cloned().unwrap_or(Value::Null),
                "text": element.get("text").cloned().unwrap_or(Value::Null),
                "role": element.get("role").cloned().unwrap_or(Value::Null),
                "tag": element.get("tag").cloned().unwrap_or(Value::Null),
                "type": element.get("type").cloned().unwrap_or(Value::Null),
                "value": element.get("value").cloned().unwrap_or(Value::Null),
                "actions": element.get("actions").cloned().unwrap_or_else(|| json!([])),
                "enabled": element.get("enabled").cloned().unwrap_or_else(|| json!(true)),
                "visible": element.get("visible").cloned().unwrap_or_else(|| json!(true)),
                "frame": format!("{screen_x:.0},{screen_y:.0},{width:.0},{height:.0}"),
                "rect": {
                    "x": screen_x,
                    "y": screen_y,
                    "width": width,
                    "height": height
                },
                "localRect": rect
            });
            flattened.push(mapped.clone());
            elements.push(mapped);
        }

        webviews.push(json!({
            "windowId": label,
            "url": snapshot.get("url").cloned().unwrap_or(Value::Null),
            "title": snapshot.get("title").cloned().unwrap_or(Value::Null),
            "viewport": snapshot.get("viewport").cloned().unwrap_or(Value::Null),
            "elements": elements
        }));
    }

    let count = flattened.len();
    Ok(json!({
        "elements": flattened,
        "webviews": webviews,
        "count": count
    }))
}

fn interact_with_dom<R>(
    app: &tauri::AppHandle<R>,
    action: &str,
    target: &str,
    text: Option<&str>,
    window_id: Option<&str>,
) -> Result<Value>
where
    R: Runtime,
{
    let (resolved_window_id, resolved_target) = resolve_appreveal_dom_target(target, window_id);
    for (label, window) in filtered_webview_windows(app, resolved_window_id.as_deref()) {
        let script = dom_action_script(action, Some(&resolved_target), text, None, None);
        let mut result = eval_json(&window, script)?;
        result["windowId"] = json!(label);
        result["target"] = json!("webview_dom");
        if result
            .get("success")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            return Ok(result);
        }
    }

    Ok(json!({
        "success": false,
        "target": "webview_dom",
        "action": action,
        "error": "target_not_found"
    }))
}

fn tap_dom_point<R>(
    app: &tauri::AppHandle<R>,
    x: f64,
    y: f64,
    window_id: Option<&str>,
) -> Result<Value>
where
    R: Runtime,
{
    let windows = filtered_webview_windows(app, window_id);
    if windows.is_empty() {
        return Ok(json!({
            "success": false,
            "target": "webview_dom",
            "action": "tap_point",
            "error": "window_not_found"
        }));
    }

    let selected = windows
        .iter()
        .find_map(|(label, window)| {
            local_point_if_inside(window, x, y).map(|point| (label, window, point))
        })
        .or_else(|| {
            windows
                .first()
                .map(|(label, window)| (label, window, (x, y)))
        });

    let Some((label, window, point)) = selected else {
        return Ok(json!({
            "success": false,
            "target": "webview_dom",
            "action": "tap_point",
            "error": "window_not_found"
        }));
    };

    let script = dom_action_script("tap_point", None, None, Some(point.0), Some(point.1));
    let mut result = eval_json(window, script)?;
    result["windowId"] = json!(label);
    result["target"] = json!("webview_dom");
    Ok(result)
}

fn tauri_menu_bar<R>(app: &tauri::AppHandle<R>) -> Result<Value>
where
    R: Runtime,
{
    let Some(menu) = app.menu() else {
        return Ok(json!({
            "menus": [],
            "count": 0
        }));
    };

    let items = menu
        .items()
        .map_err(|error| AppRevealError::Tool(error.to_string()))?
        .iter()
        .map(menu_item_to_json)
        .collect::<Result<Vec<_>>>()?;
    let count = items.len();

    Ok(json!({
        "menus": items,
        "count": count
    }))
}

fn menu_item_to_json<R>(item: &MenuItemKind<R>) -> Result<Value>
where
    R: Runtime,
{
    match item {
        MenuItemKind::MenuItem(item) => Ok(json!({
            "id": item.id().as_ref(),
            "title": item.text().unwrap_or_default(),
            "kind": "item",
            "enabled": item.is_enabled().unwrap_or(false)
        })),
        MenuItemKind::Submenu(item) => {
            let children = item
                .items()
                .map_err(|error| AppRevealError::Tool(error.to_string()))?
                .iter()
                .map(menu_item_to_json)
                .collect::<Result<Vec<_>>>()?;
            Ok(json!({
                "id": item.id().as_ref(),
                "title": item.text().unwrap_or_default(),
                "kind": "submenu",
                "enabled": item.is_enabled().unwrap_or(false),
                "items": children
            }))
        }
        MenuItemKind::Predefined(item) => Ok(json!({
            "id": item.id().as_ref(),
            "title": item.text().unwrap_or_default(),
            "kind": "predefined"
        })),
        MenuItemKind::Check(item) => Ok(json!({
            "id": item.id().as_ref(),
            "title": item.text().unwrap_or_default(),
            "kind": "check",
            "enabled": item.is_enabled().unwrap_or(false),
            "checked": item.is_checked().unwrap_or(false)
        })),
        MenuItemKind::Icon(item) => Ok(json!({
            "id": item.id().as_ref(),
            "title": item.text().unwrap_or_default(),
            "kind": "icon",
            "enabled": item.is_enabled().unwrap_or(false)
        })),
    }
}

fn eval_json<R>(window: &WebviewWindow<R>, script: String) -> Result<Value>
where
    R: Runtime,
{
    let (sender, receiver) = mpsc::channel();
    window
        .eval_with_callback(script, move |payload| {
            let _ = sender.send(payload);
        })
        .map_err(|error| AppRevealError::Tool(error.to_string()))?;

    let payload = receiver.recv_timeout(DEFAULT_EVAL_TIMEOUT).map_err(|_| {
        AppRevealError::Tool("Timed out waiting for Tauri WebView JavaScript result".to_string())
    })?;
    let value: Value = serde_json::from_str(&payload)?;
    if let Some(inner) = value.as_str() {
        serde_json::from_str(inner).map_err(AppRevealError::from)
    } else {
        Ok(value)
    }
}

fn filtered_webview_windows<R>(
    app: &tauri::AppHandle<R>,
    window_id: Option<&str>,
) -> Vec<(String, WebviewWindow<R>)>
where
    R: Runtime,
{
    app.webview_windows()
        .into_iter()
        .filter(|(label, _)| {
            window_id
                .map(|window_id| window_id == label)
                .unwrap_or(true)
        })
        .collect()
}

fn resolve_appreveal_dom_target(
    target: &str,
    explicit_window_id: Option<&str>,
) -> (Option<String>, String) {
    if let Some((window_id, index)) = target
        .strip_prefix("web.")
        .and_then(|rest| rest.split_once('.'))
    {
        return (
            explicit_window_id
                .map(ToOwned::to_owned)
                .or_else(|| Some(window_id.to_string())),
            format!("index:{index}"),
        );
    }

    (
        explicit_window_id.map(ToOwned::to_owned),
        target.to_string(),
    )
}

fn window_css_origin<R>(window: &WebviewWindow<R>) -> (f64, f64)
where
    R: Runtime,
{
    let scale = window.scale_factor().unwrap_or(1.0).max(1.0);
    window
        .inner_position()
        .map(|position| (position.x as f64 / scale, position.y as f64 / scale))
        .unwrap_or((0.0, 0.0))
}

fn local_point_if_inside<R>(window: &WebviewWindow<R>, x: f64, y: f64) -> Option<(f64, f64)>
where
    R: Runtime,
{
    let scale = window.scale_factor().unwrap_or(1.0).max(1.0);
    let origin = window_css_origin(window);
    let size = window.inner_size().ok()?;
    let width = size.width as f64 / scale;
    let height = size.height as f64 / scale;

    if x >= origin.0 && y >= origin.1 && x <= origin.0 + width && y <= origin.1 + height {
        Some((x - origin.0, y - origin.1))
    } else {
        None
    }
}

fn object_schema(properties: Map<String, Value>) -> Value {
    json!({
        "type": "object",
        "properties": properties
    })
}

fn optional_string_arg(arguments: Option<&Value>, names: &[&str]) -> Option<String> {
    arguments.and_then(Value::as_object).and_then(|arguments| {
        names.iter().find_map(|name| {
            arguments
                .get(*name)
                .and_then(Value::as_str)
                .filter(|value| !value.trim().is_empty())
                .map(ToOwned::to_owned)
        })
    })
}

fn required_string_arg(arguments: Option<&Value>, names: &[&str]) -> Result<String> {
    optional_string_arg(arguments, names).ok_or_else(|| {
        AppRevealError::InvalidParams(format!("Missing required string argument: {}", names[0]))
    })
}

fn required_number_arg(arguments: Option<&Value>, name: &str) -> Result<f64> {
    arguments
        .and_then(Value::as_object)
        .and_then(|arguments| arguments.get(name))
        .and_then(Value::as_f64)
        .ok_or_else(|| AppRevealError::InvalidParams(format!("Missing required number: {name}")))
}

fn enrich_bonjour_config<R>(app: &tauri::AppHandle<R>, config: &mut ServerConfig)
where
    R: Runtime,
{
    let Some(bonjour) = config.bonjour.as_mut() else {
        return;
    };

    let bundle_id = app.config().identifier.clone();
    let version = app.package_info().version.to_string();
    if bonjour.service_name == "AppReveal-Tauri" {
        bonjour.service_name = format!("AppReveal-{bundle_id}");
    }
    bonjour
        .txt_records
        .entry("bundleId".to_string())
        .or_insert(bundle_id);
    bonjour
        .txt_records
        .entry("version".to_string())
        .or_insert(version);
}

fn tauri_launch_context<R>(app: &tauri::AppHandle<R>) -> Value
where
    R: Runtime,
{
    let package = app.package_info();
    let bundle_id = app.config().identifier.clone();
    let app_name = package.name.clone();
    let process_name = current_executable_name();

    json!({
        "bundleId": bundle_id,
        "applicationId": bundle_id,
        "appName": app_name,
        "displayName": app_name,
        "version": package.version.to_string(),
        "versionName": package.version.to_string(),
        "build": "0",
        "versionCode": 0,
        "platform": platform_name(),
        "frameworkType": "tauri",
        "systemName": platform_name(),
        "systemVersion": std::env::consts::OS,
        "deviceModel": desktop_model_name(),
        "deviceName": default_device_name(),
        "processName": process_name,
        "processId": std::process::id()
    })
}

fn tauri_device_info<R>(app: &tauri::AppHandle<R>) -> Value
where
    R: Runtime,
{
    let launch_context = tauri_launch_context(app);
    let process_name = current_executable_name();
    let process_id = std::process::id();
    let device_name = default_device_name();

    json!({
        "platform": platform_name(),
        "frameworkType": "tauri",
        "bundleId": launch_context["bundleId"].clone(),
        "applicationId": launch_context["applicationId"].clone(),
        "appName": launch_context["appName"].clone(),
        "displayName": launch_context["displayName"].clone(),
        "version": launch_context["version"].clone(),
        "versionName": launch_context["versionName"].clone(),
        "build": launch_context["build"].clone(),
        "versionCode": launch_context["versionCode"].clone(),
        "deviceName": device_name,
        "deviceModel": desktop_model_name(),
        "systemName": platform_name(),
        "systemVersion": std::env::consts::OS,
        "processName": process_name,
        "processId": process_id,
        "app": launch_context,
        "process": {
            "pid": process_id,
            "name": process_name,
            "executable": std::env::current_exe()
                .ok()
                .and_then(|path| path.to_str().map(ToOwned::to_owned))
                .unwrap_or_else(current_executable_name)
        },
        "os": {
            "platform": platform_name(),
            "family": std::env::consts::FAMILY,
            "name": std::env::consts::OS,
            "arch": std::env::consts::ARCH
        },
        "device": {
            "name": device_name,
            "model": desktop_model_name()
        },
        "windows": {
            "count": app.webview_windows().len()
        }
    })
}

fn tauri_windows<R>(app: &tauri::AppHandle<R>) -> Vec<WindowInfo>
where
    R: Runtime,
{
    app.webview_windows()
        .into_iter()
        .map(|(label, window)| {
            let title = window.title().unwrap_or_else(|_| label.clone());
            let is_key = window.is_focused().unwrap_or(false);
            let frame = match (window.outer_position(), window.outer_size()) {
                (Ok(position), Ok(size)) => {
                    format!(
                        "{},{},{},{}",
                        position.x, position.y, size.width, size.height
                    )
                }
                _ => "0,0,0,0".to_string(),
            };
            WindowInfo::new(label, title, is_key, frame)
        })
        .collect()
}

fn platform_name() -> &'static str {
    match std::env::consts::OS {
        "macos" => "macOS",
        "windows" => "Windows",
        "linux" => "Linux",
        value => value,
    }
}

fn desktop_model_name() -> &'static str {
    match std::env::consts::OS {
        "macos" => "Mac",
        "windows" => "Windows PC",
        "linux" => "Linux PC",
        _ => "Desktop",
    }
}

fn dom_action_script(
    action: &str,
    target: Option<&str>,
    text: Option<&str>,
    x: Option<f64>,
    y: Option<f64>,
) -> String {
    let action = serde_json::to_string(action).expect("action serializes");
    let target = serde_json::to_string(&target).expect("target serializes");
    let text = serde_json::to_string(&text).expect("text serializes");
    let x = x
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string());
    let y = y
        .map(|value| value.to_string())
        .unwrap_or_else(|| "null".to_string());

    format!(
        r#"
(() => {{
  const action = {action};
  const target = {target};
  const inputText = {text};
  const pointX = {x};
  const pointY = {y};
  const interactiveSelector = [
    'a[href]',
    'button',
    'input',
    'textarea',
    'select',
    'summary',
    '[role="button"]',
    '[role="link"]',
    '[role="checkbox"]',
    '[role="radio"]',
    '[role="switch"]',
    '[tabindex]:not([tabindex="-1"])',
    '[contenteditable="true"]',
    '[contenteditable=""]',
    '[data-testid]',
    '[data-test]',
    '[aria-label]'
  ].join(',');
  const cssEscape = value => {{
    if (window.CSS && CSS.escape) return CSS.escape(String(value));
    return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  }};
  const visible = element => {{
    if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';
  }};
  const label = element => (
    element.getAttribute('aria-label') ||
    element.getAttribute('title') ||
    element.getAttribute('placeholder') ||
    element.innerText ||
    element.value ||
    element.textContent ||
    ''
  ).trim().replace(/\s+/g, ' ');
  const selectorFor = element => {{
    if (element.id) return '#' + cssEscape(element.id);
    for (const attr of ['data-testid', 'data-test', 'name', 'aria-label']) {{
      const value = element.getAttribute(attr);
      if (value) return `[${{attr}}="${{cssEscape(value)}}"]`;
    }}
    const parts = [];
    let current = element;
    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.body) {{
      let part = current.tagName.toLowerCase();
      const parent = current.parentElement;
      if (parent) {{
        const siblings = Array.from(parent.children).filter(child => child.tagName === current.tagName);
        if (siblings.length > 1) part += `:nth-of-type(${{siblings.indexOf(current) + 1}})`;
      }}
      parts.unshift(part);
      current = parent;
    }}
    return parts.length ? parts.join(' > ') : element.tagName.toLowerCase();
  }};
  const roleFor = element => {{
    const explicit = element.getAttribute('role');
    if (explicit) return explicit;
    const tag = element.tagName.toLowerCase();
    if (tag === 'button') return 'button';
    if (tag === 'a') return 'link';
    if (tag === 'select') return 'combobox';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'input') {{
      const type = (element.getAttribute('type') || 'text').toLowerCase();
      if (type === 'checkbox') return 'checkbox';
      if (type === 'radio') return 'radio';
      if (type === 'submit' || type === 'button') return 'button';
      return 'textbox';
    }}
    return tag;
  }};
  const actionsFor = element => {{
    const actions = ['tap'];
    const tag = element.tagName.toLowerCase();
    const type = (element.getAttribute('type') || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || element.isContentEditable) actions.push('type_text', 'clear_text');
    if (tag === 'select') actions.push('select');
    if (type === 'checkbox' || type === 'radio' || element.getAttribute('role') === 'switch') actions.push('toggle');
    return actions;
  }};
  const descriptor = (element, index = null) => {{
    const rect = element.getBoundingClientRect();
    return {{
      index,
      id: element.id || element.getAttribute('data-testid') || element.getAttribute('data-test') || element.getAttribute('name') || (index === null ? null : String(index)),
      selector: selectorFor(element),
      tag: element.tagName.toLowerCase(),
      role: roleFor(element),
      type: element.getAttribute('type') || null,
      label: label(element),
      text: (element.innerText || element.textContent || '').trim().replace(/\s+/g, ' '),
      value: 'value' in element ? element.value : null,
      enabled: !element.disabled && element.getAttribute('aria-disabled') !== 'true',
      visible: visible(element),
      rect: {{ x: rect.left, y: rect.top, width: rect.width, height: rect.height }},
      actions: actionsFor(element)
    }};
  }};
  const elements = () => Array.from(document.querySelectorAll(interactiveSelector)).filter(visible);
  const findTarget = () => {{
    if (action === 'tap_point') return document.elementFromPoint(pointX, pointY);
    if (!target) return null;
    const all = elements();
    if (target.startsWith('index:')) {{
      const index = Number.parseInt(target.slice('index:'.length), 10);
      return Number.isFinite(index) ? all[index] : null;
    }}
    try {{
      const selected = document.querySelector(target);
      if (selected) return selected;
    }} catch (_) {{}}
    const normalized = target.trim().toLowerCase();
    return all.find((element, index) => {{
      const descriptorForElement = descriptor(element, index);
      const candidates = [
        String(index),
        descriptorForElement.id,
        descriptorForElement.selector,
        element.getAttribute('data-testid'),
        element.getAttribute('data-test'),
        element.getAttribute('name'),
        descriptorForElement.label,
        descriptorForElement.text
      ].filter(Boolean).map(value => String(value).trim().toLowerCase());
      return candidates.includes(normalized);
    }});
  }};
  const dispatchInput = element => {{
    element.dispatchEvent(new InputEvent('input', {{ bubbles: true, inputType: 'insertText', data: inputText || '' }}));
    element.dispatchEvent(new Event('change', {{ bubbles: true }}));
  }};
  const dispatchClick = element => {{
    element.scrollIntoView({{ block: 'center', inline: 'center' }});
    const rect = element.getBoundingClientRect();
    const clientX = action === 'tap_point' ? pointX : rect.left + rect.width / 2;
    const clientY = action === 'tap_point' ? pointY : rect.top + rect.height / 2;
    for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {{
      const event = type.startsWith('pointer')
        ? new PointerEvent(type, {{ bubbles: true, cancelable: true, clientX, clientY, pointerId: 1, pointerType: 'mouse', isPrimary: true }})
        : new MouseEvent(type, {{ bubbles: true, cancelable: true, clientX, clientY, button: 0 }});
      element.dispatchEvent(event);
    }}
  }};

  const element = findTarget();
  if (!element) return {{ success: false, action, error: 'target_not_found' }};

  if (action === 'type_text' || action === 'clear_text') {{
    element.focus();
    if (element.isContentEditable) {{
      element.textContent = action === 'clear_text' ? '' : `${{element.textContent || ''}}${{inputText || ''}}`;
    }} else if ('value' in element) {{
      element.value = action === 'clear_text' ? '' : `${{element.value || ''}}${{inputText || ''}}`;
    }} else {{
      return {{ success: false, action, error: 'target_not_editable', element: descriptor(element) }};
    }}
    dispatchInput(element);
  }} else {{
    dispatchClick(element);
  }}

  return {{ success: true, action, element: descriptor(element) }};
}})()
"#
    )
}

const DOM_SNAPSHOT_JS: &str = r#"
(() => {
  const interactiveSelector = [
    'a[href]',
    'button',
    'input',
    'textarea',
    'select',
    'summary',
    '[role="button"]',
    '[role="link"]',
    '[role="checkbox"]',
    '[role="radio"]',
    '[role="switch"]',
    '[tabindex]:not([tabindex="-1"])',
    '[contenteditable="true"]',
    '[contenteditable=""]',
    '[data-testid]',
    '[data-test]',
    '[aria-label]'
  ].join(',');
  const cssEscape = value => {
    if (window.CSS && CSS.escape) return CSS.escape(String(value));
    return String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"');
  };
  const visible = element => {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden';
  };
  const label = element => (
    element.getAttribute('aria-label') ||
    element.getAttribute('title') ||
    element.getAttribute('placeholder') ||
    element.innerText ||
    element.value ||
    element.textContent ||
    ''
  ).trim().replace(/\s+/g, ' ');
  const selectorFor = element => {
    if (element.id) return '#' + cssEscape(element.id);
    for (const attr of ['data-testid', 'data-test', 'name', 'aria-label']) {
      const value = element.getAttribute(attr);
      if (value) return `[${attr}="${cssEscape(value)}"]`;
    }
    const parts = [];
    let current = element;
    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.body) {
      let part = current.tagName.toLowerCase();
      const parent = current.parentElement;
      if (parent) {
        const siblings = Array.from(parent.children).filter(child => child.tagName === current.tagName);
        if (siblings.length > 1) part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
      }
      parts.unshift(part);
      current = parent;
    }
    return parts.length ? parts.join(' > ') : element.tagName.toLowerCase();
  };
  const roleFor = element => {
    const explicit = element.getAttribute('role');
    if (explicit) return explicit;
    const tag = element.tagName.toLowerCase();
    if (tag === 'button') return 'button';
    if (tag === 'a') return 'link';
    if (tag === 'select') return 'combobox';
    if (tag === 'textarea') return 'textbox';
    if (tag === 'input') {
      const type = (element.getAttribute('type') || 'text').toLowerCase();
      if (type === 'checkbox') return 'checkbox';
      if (type === 'radio') return 'radio';
      if (type === 'submit' || type === 'button') return 'button';
      return 'textbox';
    }
    return tag;
  };
  const actionsFor = element => {
    const actions = ['tap'];
    const tag = element.tagName.toLowerCase();
    const type = (element.getAttribute('type') || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || element.isContentEditable) actions.push('type_text', 'clear_text');
    if (tag === 'select') actions.push('select');
    if (type === 'checkbox' || type === 'radio' || element.getAttribute('role') === 'switch') actions.push('toggle');
    return actions;
  };
  const elements = Array.from(document.querySelectorAll(interactiveSelector)).filter(visible);
  return {
    url: location.href,
    title: document.title,
    viewport: { width: innerWidth, height: innerHeight },
    elements: elements.map((element, index) => {
      const rect = element.getBoundingClientRect();
      return {
        index,
        id: element.id || element.getAttribute('data-testid') || element.getAttribute('data-test') || element.getAttribute('name') || String(index),
        selector: selectorFor(element),
        tag: element.tagName.toLowerCase(),
        role: roleFor(element),
        type: element.getAttribute('type') || null,
        label: label(element),
        text: (element.innerText || element.textContent || '').trim().replace(/\s+/g, ' '),
        value: 'value' in element ? element.value : null,
        enabled: !element.disabled && element.getAttribute('aria-disabled') !== 'true',
        visible: true,
        rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height },
        actions: actionsFor(element)
      };
    })
  };
})()
"#;
