use appreveal_tauri::{AppReveal, Result, ServerConfig};
use serde_json::json;
use std::time::Duration;

fn main() -> Result<()> {
    let mut appreveal = AppReveal::new();
    appreveal.register_state_provider(|| {
        json!({
            "screen": "tauri-example",
            "frameworkType": "tauri"
        })
    });

    let addr = appreveal.start(ServerConfig::localhost(0))?;
    println!(
        "AppReveal Tauri example listening at {}",
        appreveal
            .session_url()
            .unwrap_or_else(|| format!("http://{addr}"))
    );

    loop {
        std::thread::sleep(Duration::from_secs(60));
    }
}
