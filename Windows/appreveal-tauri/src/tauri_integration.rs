use crate::error::AppRevealError;
use crate::providers::{current_executable_name, default_device_name, windows_launch_context};
use crate::{
    registry_with_builtins, start_server, ProviderRegistry, Result, ServerConfig, ServerHandle,
    WindowInfo,
};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::{Mutex, MutexGuard};
use tauri::{Manager, Runtime};

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
    let providers = providers_from_tauri(app);
    let registry = registry_with_builtins(providers);
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

fn tauri_launch_context<R>(app: &tauri::AppHandle<R>) -> Value
where
    R: Runtime,
{
    let package = app.package_info();
    let bundle_id = app.config().identifier.clone();
    let app_name = package.name.clone();

    windows_launch_context(
        bundle_id,
        app_name.clone(),
        app_name,
        package.version.to_string(),
        "0".to_string(),
        "tauri",
    )
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
                .unwrap_or_else(current_executable_name)
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
