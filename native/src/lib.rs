//! A local-only JSON C ABI. No sockets, URLs, downloads, accounts or telemetry.
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::Path;

#[cfg(feature = "engine")]
mod engine;

pub const UPSTREAM_REVISION: &str = "5772f9d6238a019b71f0fb235fbeeaf1338694f5";
const MAX_REQUEST_BYTES: usize = 1_048_576;
const DATA_FILES: [&str; 5] = [
    "types.pb2",
    "dogmaAttributes.pb2",
    "dogmaEffects.pb2",
    "typeDogma.pb2",
    "dbuffcollections.pb2",
];
const PATCH_IDS: &str = include_str!("../vendor/eve-fit-os/patch_ids.json");

#[derive(Debug, Serialize)]
pub struct Failure {
    pub code: &'static str,
    pub message: String,
}
impl Failure {
    pub(crate) fn new(code: &'static str, message: impl Into<String>) -> Self {
        Self {
            code,
            message: message.into(),
        }
    }
}
type Result<T> = std::result::Result<T, Failure>;

#[derive(Debug, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
enum Request {
    Health {
        #[serde(default, alias = "data_dir")]
        data_path: Option<String>,
    },
    Calculate {
        #[serde(alias = "data_dir")]
        data_path: String,
        fit: Fit,
    },
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Fit {
    pub ship_type_id: i32,
    #[serde(default)]
    pub modules: Vec<Module>,
    #[serde(default)]
    pub drones: Vec<Drone>,
    #[serde(default)]
    pub implants: Vec<Implant>,
    #[serde(default)]
    pub skills: BTreeMap<String, u8>,
    #[serde(default)]
    pub skill_mode: SkillMode,
}
#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum SkillMode {
    #[default]
    Custom,
    All5,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Module {
    pub type_id: i32,
    #[serde(alias = "slot")]
    pub slot_type: SlotType,
    pub index: i32,
    pub state: State,
    #[serde(default)]
    pub charge_type_id: Option<i32>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum SlotType {
    High,
    Medium,
    Low,
    Rig,
    Subsystem,
}
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum State {
    Offline,
    Online,
    Active,
    Overloaded,
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Drone {
    pub type_id: i32,
    #[serde(default = "one")]
    pub quantity: u16,
    pub state: DroneState,
}
#[derive(Debug, Clone, Copy, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum DroneState {
    Online,
    Active,
}
fn one() -> u16 {
    1
}
#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct Implant {
    pub type_id: i32,
    pub index: i32,
}

impl Fit {
    fn validate(&self) -> Result<()> {
        if self.ship_type_id <= 0 {
            return Err(Failure::new("INVALID_FIT", "ship_type_id must be positive"));
        }
        if self.modules.len() > 64
            || self
                .drones
                .iter()
                .map(|d| u32::from(d.quantity))
                .sum::<u32>()
                > 255
            || self.implants.len() > 10
        {
            return Err(Failure::new(
                "INVALID_FIT",
                "Fit exceeds bridge item limits (64 modules, 255 drones, 10 implants)",
            ));
        }
        let mut occupied = BTreeSet::new();
        for m in &self.modules {
            if m.type_id <= 0
                || m.charge_type_id.is_some_and(|id| id <= 0)
                || !(0..8).contains(&m.index)
            {
                return Err(Failure::new(
                    "INVALID_FIT",
                    "Invalid module type, charge or slot index",
                ));
            }
            if !occupied.insert((m.slot_type, m.index)) {
                return Err(Failure::new(
                    "INVALID_FIT",
                    "Two modules occupy the same slot",
                ));
            }
        }
        if self
            .drones
            .iter()
            .any(|d| d.type_id <= 0 || d.quantity == 0)
        {
            return Err(Failure::new(
                "INVALID_FIT",
                "Drone type and quantity must be positive",
            ));
        }
        let mut implant_slots = BTreeSet::new();
        if self.implants.iter().any(|i| {
            i.type_id <= 0 || !(1..=10).contains(&i.index) || !implant_slots.insert(i.index)
        }) {
            return Err(Failure::new(
                "INVALID_FIT",
                "Implant slot must be unique and within 1..10",
            ));
        }
        if self
            .skills
            .iter()
            .any(|(id, &level)| id.parse::<i32>().map_or(true, |id| id <= 0) || level > 5)
        {
            return Err(Failure::new(
                "INVALID_FIT",
                "Skill IDs must be positive and levels within 0..5",
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
struct DataManifest {
    schema_version: u32,
    server: String,
    upstream_revision: String,
    patch_ids_sha256: String,
    files: BTreeMap<String, String>,
}

fn sha256(bytes: &[u8]) -> String {
    format!("{:x}", Sha256::digest(bytes))
}

pub(crate) fn verify_dataset(root: &Path) -> Result<()> {
    if !root.is_dir() {
        return Err(Failure::new(
            "DATA_MISSING",
            "Local engine data directory does not exist",
        ));
    }
    let bytes = std::fs::read(root.join("engine-manifest.json"))
        .map_err(|e| Failure::new("DATA_MISSING", format!("engine-manifest.json: {e}")))?;
    let manifest: DataManifest = serde_json::from_slice(&bytes)
        .map_err(|e| Failure::new("DATA_INVALID", format!("Invalid engine manifest: {e}")))?;
    if manifest.schema_version != 1
        || manifest.server != "tranquility"
        || manifest.upstream_revision != UPSTREAM_REVISION
        || manifest.patch_ids_sha256 != sha256(PATCH_IDS.as_bytes())
    {
        return Err(Failure::new("DATA_VERSION_MISMATCH", "Engine data must match this exact engine revision, patch ID mapping and Tranquility server"));
    }
    for name in DATA_FILES {
        let bytes = std::fs::read(root.join(name))
            .map_err(|e| Failure::new("DATA_MISSING", format!("{name}: {e}")))?;
        if bytes.is_empty() || manifest.files.get(name) != Some(&sha256(&bytes)) {
            return Err(Failure::new(
                "DATA_INVALID",
                format!("Missing checksum, empty file or checksum mismatch: {name}"),
            ));
        }
    }
    Ok(())
}

fn dispatch(request: Request) -> Result<Value> {
    match request {
        Request::Health { data_path } => {
            let status = data_path.as_ref().map(|p| verify_dataset(Path::new(p)));
            Ok(
                json!({"protocol_version":1,"engine":"eve-fit-os","engine_enabled":cfg!(feature="engine"),"upstream_revision":UPSTREAM_REVISION,"offline":true,"pyfa_verified":false,
                "data_status":match &status { None => "not_checked", Some(Ok(())) => "ready", Some(Err(e)) if e.code == "DATA_MISSING" => "missing", _ => "invalid" },
                "data_error":status.and_then(|s| s.err()) }),
            )
        }
        Request::Calculate { data_path, fit } => {
            fit.validate()?;
            #[cfg(feature = "engine")]
            {
                verify_dataset(Path::new(&data_path))?;
                engine::calculate(&data_path, &fit)
            }
            #[cfg(not(feature = "engine"))]
            {
                let _ = data_path;
                Err(Failure::new(
                    "ENGINE_UNAVAILABLE",
                    "This library was built without the engine feature",
                ))
            }
        }
    }
}

/// Dispatch a protocol request; errors never contain synthetic gameplay statistics.
pub fn call_json(request: &str) -> String {
    let result = catch_unwind(AssertUnwindSafe(|| {
        if request.len() > MAX_REQUEST_BYTES {
            return Err(Failure::new("REQUEST_TOO_LARGE", "Request limit is 1 MiB"));
        }
        let parsed: Request = serde_json::from_str(request)
            .map_err(|e| Failure::new("INVALID_REQUEST", e.to_string()))?;
        dispatch(parsed)
    }))
    .unwrap_or_else(|_| {
        Err(Failure::new(
            "ENGINE_PANIC",
            "Engine rejected the local data or fit; no result was returned",
        ))
    });
    match result {
        Ok(result) => json!({"ok":true,"result":result}),
        Err(error) => json!({"ok":false,"error":error}),
    }
    .to_string()
}

fn owned_response(value: String) -> *mut c_char {
    CString::new(value)
        .expect("JSON cannot contain raw NUL")
        .into_raw()
}

/// # Safety
/// `request` must be null or a readable, NUL-terminated UTF-8 string. The caller
/// retains it until this call returns. Free the returned pointer with `els_free`.
#[no_mangle]
pub unsafe extern "C" fn els_call(request: *const c_char) -> *mut c_char {
    if request.is_null() {
        return owned_response(
            json!({"ok":false,"error":{"code":"INVALID_REQUEST","message":"Null request pointer"}})
                .to_string(),
        );
    }
    let text = unsafe { CStr::from_ptr(request) }.to_str();
    owned_response(match text {
        Ok(s) => call_json(s),
        Err(_) => {
            json!({"ok":false,"error":{"code":"INVALID_UTF8","message":"Request must be UTF-8"}})
                .to_string()
        }
    })
}

/// # Safety
/// Free a pointer returned by `els_call` exactly once. Null is a no-op.
#[no_mangle]
pub unsafe extern "C" fn els_free(response: *mut c_char) {
    if !response.is_null() {
        drop(unsafe { CString::from_raw(response) });
    }
}

/// Allocate a zero-filled input buffer. Limit includes the final NUL byte.
#[no_mangle]
pub extern "C" fn els_alloc(size: usize) -> *mut u8 {
    if size == 0 || size > MAX_REQUEST_BYTES + 1 {
        return std::ptr::null_mut();
    }
    Box::into_raw(vec![0_u8; size].into_boxed_slice()).cast::<u8>()
}

/// # Safety
/// Free an `els_alloc` pointer exactly once with the original size. Null is safe.
#[no_mangle]
pub unsafe extern "C" fn els_dealloc(pointer: *mut u8, size: usize) {
    if !pointer.is_null() {
        drop(unsafe { Box::from_raw(std::ptr::slice_from_raw_parts_mut(pointer, size)) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn response(text: &str) -> Value {
        serde_json::from_str(&call_json(text)).unwrap()
    }
    fn fit_request(fit: Value) -> String {
        json!({"op":"calculate","data_path":"does-not-exist","fit":fit}).to_string()
    }
    #[test]
    fn health_states_verification_honestly() {
        let r = response(r#"{"op":"health"}"#);
        assert_eq!(r["ok"], true);
        assert_eq!(r["result"]["pyfa_verified"], false);
    }
    #[test]
    fn malformed_json_is_error() {
        assert_eq!(response("{")["error"]["code"], "INVALID_REQUEST");
    }
    #[test]
    fn rejects_unknown_operation_and_fields() {
        assert_eq!(response(r#"{"op":"market"}"#)["ok"], false);
        assert_eq!(
            response(r#"{"op":"health","url":"https://example.com"}"#)["ok"],
            false
        );
    }
    #[test]
    fn rejects_state_typo() {
        assert_eq!(
            response(&fit_request(
                json!({"ship_type_id":587,"modules":[{"type_id":1,"slot_type":"high","index":0,"state":"overheating"}]})
            ))["error"]["code"],
            "INVALID_REQUEST"
        );
    }
    #[test]
    fn rejects_duplicate_slots() {
        let m = json!({"type_id":1,"slot_type":"high","index":0,"state":"active"});
        assert_eq!(
            response(&fit_request(
                json!({"ship_type_id":587,"modules":[m.clone(),m]})
            ))["error"]["code"],
            "INVALID_FIT"
        );
    }
    #[test]
    fn rejects_skill_level_six() {
        assert_eq!(
            response(&fit_request(
                json!({"ship_type_id":587,"skills":{"3300":6}})
            ))["error"]["code"],
            "INVALID_FIT"
        );
    }
    #[test]
    fn client_fit_contract_reaches_data_validation() {
        let request = fit_request(
            json!({"ship_type_id":587,"skill_mode":"all5","skills":{"3300":5},"modules":[{"type_id":2006,"slot_type":"high","index":0,"state":"active"}],"drones":[{"type_id":2456,"quantity":5,"state":"online"}]}),
        );
        let r = response(&request);
        assert_eq!(
            r["error"]["code"],
            if cfg!(feature = "engine") {
                "DATA_MISSING"
            } else {
                "ENGINE_UNAVAILABLE"
            }
        );
    }
    #[test]
    fn missing_data_never_produces_stats() {
        let r = response(&fit_request(json!({"ship_type_id":587})));
        assert_eq!(r["ok"], false);
        assert!(r.get("result").is_none());
    }
    #[test]
    fn missing_dataset_is_explicit() {
        assert_eq!(
            verify_dataset(Path::new("impossible-local-engine-data"))
                .unwrap_err()
                .code,
            "DATA_MISSING"
        );
    }
    #[test]
    fn dataset_revision_and_hash_are_enforced() {
        let unique = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root =
            std::env::temp_dir().join(format!("els-manifest-{}-{unique}", std::process::id()));
        std::fs::create_dir(&root).unwrap();
        let files: BTreeMap<_, _> = DATA_FILES
            .into_iter()
            .map(|name| {
                std::fs::write(root.join(name), b"test-only checksum payload").unwrap();
                (name, sha256(b"test-only checksum payload"))
            })
            .collect();
        let mut manifest = json!({"schema_version":1,"server":"tranquility","upstream_revision":UPSTREAM_REVISION,"patch_ids_sha256":sha256(PATCH_IDS.as_bytes()),"files":files});
        let write_manifest = |value: &Value| {
            std::fs::write(root.join("engine-manifest.json"), value.to_string()).unwrap()
        };
        write_manifest(&manifest);
        assert!(verify_dataset(&root).is_ok());
        manifest["server"] = json!("serenity");
        write_manifest(&manifest);
        assert_eq!(
            verify_dataset(&root).unwrap_err().code,
            "DATA_VERSION_MISMATCH"
        );
        manifest["server"] = json!("tranquility");
        write_manifest(&manifest);
        std::fs::write(root.join("types.pb2"), b"changed payload").unwrap();
        assert_eq!(verify_dataset(&root).unwrap_err().code, "DATA_INVALID");
        // This temporary directory was created exclusively by this test.
        std::fs::remove_dir_all(root).unwrap();
    }
    #[test]
    fn ffi_roundtrip_and_invalid_utf8() {
        unsafe {
            let input = CString::new(r#"{"op":"health"}"#).unwrap();
            let output = els_call(input.as_ptr());
            let r: Value = serde_json::from_slice(CStr::from_ptr(output).to_bytes()).unwrap();
            assert_eq!(r["ok"], true);
            els_free(output);
            let bad = [0xff_u8, 0];
            let output = els_call(bad.as_ptr().cast());
            assert!(CStr::from_ptr(output)
                .to_str()
                .unwrap()
                .contains("INVALID_UTF8"));
            els_free(output);
            let output = els_call(std::ptr::null());
            assert!(CStr::from_ptr(output)
                .to_str()
                .unwrap()
                .contains("INVALID_REQUEST"));
            els_free(output);
            els_free(std::ptr::null_mut());
        }
    }
    #[test]
    fn allocation_is_zeroed_and_bounded() {
        assert!(els_alloc(0).is_null());
        assert!(els_alloc(MAX_REQUEST_BYTES + 2).is_null());
        unsafe {
            let p = els_alloc(8);
            assert_eq!(std::slice::from_raw_parts(p, 8), [0; 8]);
            els_dealloc(p, 8);
        }
    }
}
