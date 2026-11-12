use appreveal_tauri::{start_tauri_server_managed, AppRevealTauriServer, ServerConfig};
use tauri::Manager;

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            start_tauri_server_managed(app.handle().clone(), ServerConfig::localhost(0))?;
            // The caller creates an owner-only directory; never print the session URL.
            let path = std::env::var("APPREVEAL_VERIFICATION_SESSION")?;
            let url = app.state::<AppRevealTauriServer>().session_url()?.unwrap();
            std::fs::write(path, url)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("verification app failed");
}
