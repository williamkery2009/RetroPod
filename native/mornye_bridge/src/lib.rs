//! Small C ABI around the pinned, unmodified Mornye extension manager.
use mornye_extensions::{manager::{ExtensionManager, ProviderDownloadRequest}, package::ExtensionPackage, RuntimeLimits};
use serde_json::{json, Value};
use std::{ffi::{c_char, CStr, CString}, path::Path, sync::OnceLock};
static MANAGER: OnceLock<ExtensionManager> = OnceLock::new();
fn string<'a>(v: &'a Value, key: &str) -> Result<&'a str, String> {
    v[key].as_str().ok_or_else(|| format!("Missing {key}"))
}
fn parsed(s: String) -> Result<Value, String> { serde_json::from_str(&s).map_err(|e| e.to_string()) }
// Raw provider responses may include signed URLs, tokens and cookies.
// Only a fixed diagnostic category crosses the native boundary on failure.
fn error_code(message: &str) -> &'static str {
    let m = message.to_ascii_lowercase();
    if m.contains("signed-session") || m.contains("signed session") || m.contains("verification_required") || m.contains("verify_required") { "EXT_SESSION" }
    else if m.contains("sign in") || m.contains("login") || m.contains("authentication") || m.contains("unauthorized") || m.contains("401") || m.contains("not a bot") { "EXT_AUTH" }
    else if m.contains("403") || m.contains("forbidden") { "EXT_FORBIDDEN" }
    else if m.contains("429") || m.contains("rate limit") { "EXT_RATE_LIMIT" }
    else if m.contains("timeout") || m.contains("timed out") { "EXT_TIMEOUT" }
    else if m.contains("quality_unavailable") || m.contains("unsupported quality") { "EXT_QUALITY" }
    else if m.contains("permission") || m.contains("not allowed") || m.contains("not permitted") { "EXT_PERMISSION" }
    else if m.contains("runtime feature") || m.contains("app version") || m.contains("function not found") { "EXT_COMPATIBILITY" }
    else if m.contains("disabled") || m.contains("extension not found") { "EXT_DISABLED" }
    else if m.contains("502") || m.contains("503") || m.contains("504") { "EXT_SERVER" }
    else if m.contains("no playable") || m.contains("not_found") || m.contains("not found") { "EXT_NO_AUDIO" }
    else { "EXT_FAILED" }
}
fn dispatch(v: Value) -> Result<Value, String> {
    let op = string(&v, "op")?;
    if op == "init" {
        if MANAGER.get().is_none() {
            let root = Path::new(string(&v, "root")?);
            let manager = ExtensionManager::new(&root.join("sources"), &root.join("data"), string(&v, "key")?, "5.4.5", RuntimeLimits::default()).map_err(|e| e.to_string())?;
            let cache = root.join("audio");
            std::fs::create_dir_all(&cache).map_err(|e| e.to_string())?;
            manager.environment().set_allowed_download_directories(&[cache]).map_err(|e| e.to_string())?;
            manager.load_all().map_err(|e| e.to_string())?;
            MANAGER.set(manager).map_err(|_| "Already initialized".to_string())?;
        }
        return Ok(json!(true));
    }
    let m = MANAGER.get().ok_or("Runtime not initialized")?;
    let id = v["id"].as_str().unwrap_or("");
    match op {
        "installed" => parsed(m.installed().map_err(|e| e.to_string())?),
        "inspect" => {
            let p = ExtensionPackage::open(Path::new(string(&v,"path")?)).map_err(|e| e.to_string())?;
            parsed(p.manifest_json)
        },
        "install" => parsed(m.install(Path::new(string(&v,"path")?)).map_err(|e| e.to_string())?),
        "remove" => { m.remove(id).map_err(|e| e.to_string())?; Ok(Value::Null) },
        "enable" => { m.set_enabled(id, v["enabled"] == true).map_err(|e| e.to_string())?; Ok(Value::Null) },
        "settings" => Ok(json!(m.environment().settings(id).map_err(|e| e.to_string())?)),
        "saveSettings" => { m.update_settings(id, v["settings"].as_object().ok_or("Invalid settings")?.clone()).map_err(|e| e.to_string())?; Ok(Value::Null) },
        "search" => parsed(m.search_metadata_provider(id, string(&v,"query")?, 40, 30000).map_err(|e| e.to_string())?),
        "download" => {
            let request = ProviderDownloadRequest {
                track_id: string(&v,"trackId")?.into(), quality: string(&v,"quality")?.into(),
                output_path: string(&v,"path")?.into(), item_id: string(&v,"itemId")?.into(),
                // Resolve fresh provider state; search metadata is not a prepared context.
                prepared_context: None,
            };
            let result = parsed(m.download(id, request, 60000).map_err(|e| e.to_string())?)?;
            if result["success"] != true {
                return Err(format!("{} {}", result["error_type"].as_str().unwrap_or(""), result["error_message"].as_str().unwrap_or("")));
            }
            Ok(result)
        },
        "ffmpegPoll" => parsed(m.environment().ffmpeg_commands().wait_pending_json(1000).map_err(|e|e.to_string())?),
        "ffmpegComplete" => {
            m.environment().ffmpeg_commands().complete(id, mornye_extensions::ffmpeg::CommandResult {
                success: v["success"] == true, output: String::new(), error: if v["success"] == true {String::new()} else {"Audio conversion failed".into()},
            }).map_err(|e| e.to_string())?; Ok(Value::Null)
        },
        _ => Err("Unknown runtime operation".into()),
    }
}
/// Caller owns input; returned UTF-8 JSON must be released with rp_free.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rp_call(input: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(|| {
        if input.is_null() { return Err("Null request".into()); }
        let raw = unsafe { CStr::from_ptr(input) }.to_str().map_err(|_| "Invalid UTF-8".to_string())?;
        dispatch(serde_json::from_str(raw).map_err(|e|e.to_string())?)
    });
    let value = match result { Ok(Ok(v)) => json!({"value":v}), Ok(Err(e)) => json!({"error":error_code(&e)}), Err(_) => json!({"error":"EXT_FAILED"}) };
    CString::new(value.to_string()).unwrap().into_raw()
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn rp_free(value: *mut c_char) {
    if !value.is_null() { drop(unsafe { CString::from_raw(value) }); }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn executes_registered_extension_and_interrupts_runaway_code() {
        let vm = mornye_extensions::ExtensionRuntime::load("registerExtension({searchTracks(q){return {tracks:[{id:'123',name:q}]}},loop(){while(true){}}});", "{}", RuntimeLimits::default()).unwrap();
        let result = vm.call("searchTracks", "[\"Test\"]", None, 1000).unwrap();
        assert_eq!(serde_json::from_str::<Value>(&result).unwrap()["tracks"][0]["name"], "Test");
        assert!(vm.call("loop", "[]", None, 25).is_err());
    }
}

#[cfg(test)]
mod package_tests {
    use super::*;
    use std::io::Write;
    #[test]
    fn installs_searches_prepares_audio_and_persists_enabled_state() {
        let dir = tempfile::tempdir().unwrap();
        let package = dir.path().join("fixture.sflx");
        let manifest = json!({"name":"fixture", "displayName":"Fixture", "version":"1.0.0", "description":"Runtime installation fixture",
            "type":["metadata_provider","download_provider"],
            "permissions":{"file":true,"storage":true}});
        let source = r#"registerExtension({
            searchTracks(q){return {tracks:[{id:'1',name:q,artists:'Artist',album_name:'Album',duration_ms:1000,provider_id:'fixture'}]};},
            download(id,quality,path){const result=file.writeBytes(path,'UklGRg=='); return {success:result.success,file_path:path};}
        });"#;
        let mut zip = zip::ZipWriter::new(std::fs::File::create(&package).unwrap());
        for (name, body) in [("manifest.json",manifest.to_string()),("index.js",source.to_string())] {
            zip.start_file(name,zip::write::SimpleFileOptions::default()).unwrap();
            zip.write_all(body.as_bytes()).unwrap();
        }
        zip.finish().unwrap();
        let create = || ExtensionManager::new(&dir.path().join("sources"), &dir.path().join("data"), "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", "5.4.5", RuntimeLimits::default()).unwrap();
        let m = create();
        m.install(&package).unwrap();
        let found = parsed(m.search_metadata_provider("fixture","Search",10,1000).unwrap()).unwrap();
        assert_eq!(found[0]["name"], "Search");
        let audio = dir.path().join("audio"); std::fs::create_dir(&audio).unwrap();
        m.environment().set_allowed_download_directories(&[audio.clone()]).unwrap();
        let path = audio.join("test.wav");
        let result = parsed(m.download("fixture",ProviderDownloadRequest {
            track_id:"1".into(), quality:"high".into(), output_path:path.to_str().unwrap().into(),
            item_id:"test".into(), prepared_context:None,
        },1000).unwrap()).unwrap();
        assert_eq!(result["success"],true,"{result}");
        assert_eq!(std::fs::read(&path).unwrap(),b"RIFF");
        m.set_enabled("fixture",false).unwrap(); m.shutdown();
        let reopened=create(); reopened.load_all().unwrap();
        assert!(reopened.search_metadata_provider("fixture","Search",10,1000).is_err());
        reopened.remove("fixture").unwrap();
        assert_eq!(parsed(reopened.installed().unwrap()).unwrap(),json!([]));
    }
}

#[cfg(test)]
mod diagnostic_tests {
    use super::*;
    #[test]
    fn errors_are_categorized_without_returning_provider_secrets() {
        for (raw, expected) in [
            ("HTTP 403 https://example.invalid?token=secret", "EXT_FORBIDDEN"),
            ("verification_required signed-session grant missing", "EXT_SESSION"),
            ("LOGIN_REQUIRED cookie=secret", "EXT_AUTH"),
            ("quality_unavailable", "EXT_QUALITY"),
            ("stream resolution timeout", "EXT_TIMEOUT"),
            ("unknown token=secret", "EXT_FAILED"),
        ] { assert_eq!(error_code(raw), expected); }
    }
}
