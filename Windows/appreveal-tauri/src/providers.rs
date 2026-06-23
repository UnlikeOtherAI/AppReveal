use serde::Serialize;
use serde_json::{json, Value};
use std::sync::{Arc, RwLock};

type ValueProvider = Arc<dyn Fn() -> Value + Send + Sync + 'static>;
type WindowsProvider = Arc<dyn Fn() -> Vec<WindowInfo> + Send + Sync + 'static>;
type LogsProvider = Arc<dyn Fn(LogQuery) -> Value + Send + Sync + 'static>;
type NetworkProvider = Arc<dyn Fn(NetworkQuery) -> Value + Send + Sync + 'static>;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LogQuery {
    pub subsystem: Option<String>,
    pub limit: usize,
}

impl Default for LogQuery {
    fn default() -> Self {
        Self {
            subsystem: None,
            limit: 50,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct NetworkQuery {
    pub limit: usize,
}

impl Default for NetworkQuery {
    fn default() -> Self {
        Self { limit: 50 }
    }
}

#[derive(Clone, Debug, Serialize, PartialEq, Eq)]
pub struct WindowInfo {
    pub id: String,
    pub title: String,
    #[serde(rename = "isKey")]
    pub is_key: bool,
    pub frame: String,
}

impl WindowInfo {
    pub fn new(
        id: impl Into<String>,
        title: impl Into<String>,
        is_key: bool,
        frame: impl Into<String>,
    ) -> Self {
        Self {
            id: id.into(),
            title: title.into(),
            is_key,
            frame: frame.into(),
        }
    }
}

#[derive(Clone, Default)]
pub struct ProviderRegistry {
    hooks: Arc<RwLock<ProviderHooks>>,
}

#[derive(Default)]
struct ProviderHooks {
    launch_context: Option<ValueProvider>,
    device_info: Option<ValueProvider>,
    windows: Option<WindowsProvider>,
    logs: Option<LogsProvider>,
    state: Option<ValueProvider>,
    navigation: Option<ValueProvider>,
    feature_flags: Option<ValueProvider>,
    network: Option<NetworkProvider>,
}

impl ProviderRegistry {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn set_launch_context_provider<F>(&self, provider: F)
    where
        F: Fn() -> Value + Send + Sync + 'static,
    {
        self.write_hooks().launch_context = Some(Arc::new(provider));
    }

    pub fn set_device_info_provider<F>(&self, provider: F)
    where
        F: Fn() -> Value + Send + Sync + 'static,
    {
        self.write_hooks().device_info = Some(Arc::new(provider));
    }

    pub fn set_window_provider<F>(&self, provider: F)
    where
        F: Fn() -> Vec<WindowInfo> + Send + Sync + 'static,
    {
        self.write_hooks().windows = Some(Arc::new(provider));
    }

    pub fn set_log_provider<F>(&self, provider: F)
    where
        F: Fn(LogQuery) -> Value + Send + Sync + 'static,
    {
        self.write_hooks().logs = Some(Arc::new(provider));
    }

    pub fn set_state_provider<F>(&self, provider: F)
    where
        F: Fn() -> Value + Send + Sync + 'static,
    {
        self.write_hooks().state = Some(Arc::new(provider));
    }

    pub fn set_navigation_provider<F>(&self, provider: F)
    where
        F: Fn() -> Value + Send + Sync + 'static,
    {
        self.write_hooks().navigation = Some(Arc::new(provider));
    }

    pub fn set_feature_flag_provider<F>(&self, provider: F)
    where
        F: Fn() -> Value + Send + Sync + 'static,
    {
        self.write_hooks().feature_flags = Some(Arc::new(provider));
    }

    pub fn set_network_provider<F>(&self, provider: F)
    where
        F: Fn(NetworkQuery) -> Value + Send + Sync + 'static,
    {
        self.write_hooks().network = Some(Arc::new(provider));
    }

    pub fn has_window_provider(&self) -> bool {
        self.has_hook(|hooks| hooks.windows.is_some())
    }

    pub fn has_log_provider(&self) -> bool {
        self.has_hook(|hooks| hooks.logs.is_some())
    }

    pub fn has_state_provider(&self) -> bool {
        self.has_hook(|hooks| hooks.state.is_some())
    }

    pub fn has_navigation_provider(&self) -> bool {
        self.has_hook(|hooks| hooks.navigation.is_some())
    }

    pub fn has_feature_flag_provider(&self) -> bool {
        self.has_hook(|hooks| hooks.feature_flags.is_some())
    }

    pub fn has_network_provider(&self) -> bool {
        self.has_hook(|hooks| hooks.network.is_some())
    }

    pub fn launch_context(&self) -> Value {
        self.value_from(|hooks| hooks.launch_context.clone())
            .unwrap_or_else(default_launch_context)
    }

    pub fn device_info(&self) -> Value {
        self.value_from(|hooks| hooks.device_info.clone())
            .unwrap_or_else(default_device_info)
    }

    pub fn list_windows(&self) -> Vec<WindowInfo> {
        self.windows_provider()
            .map(|provider| provider())
            .unwrap_or_default()
    }

    pub fn logs(&self, query: LogQuery) -> Value {
        self.logs_provider()
            .map(|provider| provider(query))
            .unwrap_or_else(|| json!({ "logs": [], "count": 0 }))
    }

    pub fn state(&self) -> Value {
        self.value_from(|hooks| hooks.state.clone())
            .unwrap_or_else(|| json!({}))
    }

    pub fn navigation_stack(&self) -> Value {
        self.value_from(|hooks| hooks.navigation.clone())
            .unwrap_or_else(|| json!({}))
    }

    pub fn feature_flags(&self) -> Value {
        self.value_from(|hooks| hooks.feature_flags.clone())
            .unwrap_or_else(|| json!({}))
    }

    pub fn network_calls(&self, query: NetworkQuery) -> Value {
        let limit = query.limit;
        self.network_provider()
            .map(|provider| provider(query))
            .unwrap_or_else(|| {
                json!({
                    "calls": [],
                    "count": 0,
                    "limit": limit
                })
            })
    }

    fn value_from<F>(&self, pick: F) -> Option<Value>
    where
        F: FnOnce(&ProviderHooks) -> Option<ValueProvider>,
    {
        let provider = self.hooks.read().ok().and_then(|hooks| pick(&hooks));
        provider.map(|provider| provider())
    }

    fn windows_provider(&self) -> Option<WindowsProvider> {
        self.hooks
            .read()
            .ok()
            .and_then(|hooks| hooks.windows.clone())
    }

    fn logs_provider(&self) -> Option<LogsProvider> {
        self.hooks.read().ok().and_then(|hooks| hooks.logs.clone())
    }

    fn network_provider(&self) -> Option<NetworkProvider> {
        self.hooks
            .read()
            .ok()
            .and_then(|hooks| hooks.network.clone())
    }

    fn has_hook<F>(&self, pick: F) -> bool
    where
        F: FnOnce(&ProviderHooks) -> bool,
    {
        match self.hooks.read() {
            Ok(hooks) => pick(&hooks),
            Err(_) => false,
        }
    }

    fn write_hooks(&self) -> std::sync::RwLockWriteGuard<'_, ProviderHooks> {
        self.hooks
            .write()
            .expect("AppReveal provider registry poisoned")
    }
}

pub(crate) fn default_launch_context() -> Value {
    let app_name = current_executable_name();
    windows_launch_context(
        app_name.clone(),
        app_name.clone(),
        app_name,
        "unknown".to_string(),
        "0".to_string(),
        "tauri",
    )
}

pub(crate) fn default_device_info() -> Value {
    let launch_context = default_launch_context();
    let process_name = current_executable_name();
    let process_id = std::process::id();
    let device_name = default_device_name();

    json!({
        "platform": "Windows",
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
        "deviceModel": "Windows PC",
        "systemName": "Windows",
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
                .unwrap_or_else(|| "unknown".to_string())
        },
        "os": {
            "platform": "Windows",
            "family": std::env::consts::FAMILY,
            "name": std::env::consts::OS,
            "arch": std::env::consts::ARCH
        },
        "device": {
            "name": device_name,
            "model": "Windows PC"
        }
    })
}

pub(crate) fn default_device_name() -> String {
    std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "unknown".to_string())
}

pub(crate) fn current_executable_name() -> String {
    if let Ok(path) = std::env::current_exe() {
        if let Some(name) = path
            .as_path()
            .file_stem()
            .and_then(|name| name.to_str())
            .filter(|name| !name.trim().is_empty())
        {
            return name.to_string();
        }
    }

    env!("CARGO_PKG_NAME").to_string()
}

pub(crate) fn windows_launch_context(
    bundle_id: String,
    app_name: String,
    display_name: String,
    version: String,
    build: String,
    framework_type: &'static str,
) -> Value {
    let process_name = current_executable_name();

    json!({
        "bundleId": bundle_id,
        "applicationId": bundle_id,
        "appName": app_name,
        "displayName": display_name,
        "version": version,
        "versionName": version,
        "build": build,
        "versionCode": 0,
        "platform": "Windows",
        "frameworkType": framework_type,
        "systemName": "Windows",
        "systemVersion": std::env::consts::OS,
        "deviceModel": "Windows PC",
        "deviceName": default_device_name(),
        "processName": process_name,
        "processId": std::process::id()
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn launch_context_exposes_normalized_windows_keys() {
        let context = default_launch_context();

        assert_eq!(context["platform"], "Windows");
        assert_eq!(context["frameworkType"], "tauri");
        assert!(context["bundleId"].is_string());
        assert_eq!(context["applicationId"], context["bundleId"]);
        assert_eq!(context["versionName"], context["version"]);
        assert!(context["processId"].is_number());
    }

    #[test]
    fn device_info_repeats_discovery_summary_at_top_level() {
        let info = default_device_info();

        assert_eq!(info["platform"], "Windows");
        assert_eq!(info["frameworkType"], "tauri");
        assert_eq!(info["bundleId"], info["app"]["bundleId"]);
        assert_eq!(info["appName"], info["app"]["appName"]);
        assert_eq!(info["deviceName"], info["device"]["name"]);
        assert_eq!(info["processId"], info["process"]["pid"]);
    }
}
