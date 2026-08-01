//! sophia-ffi — the C ABI the Swift shell drives the core through (blueprint §20).
//!
//! Contract, non-negotiable:
//! - No Rust panic crosses the boundary: `catch_unwind` at every entry point;
//!   a panic degrades the lint to an empty issue list, it does not kill the
//!   agent (AC-13).
//! - Every returned pointer is freed by an explicit `sophia_free`.
//! - Payloads are UTF-8 JSON so the boundary stays debuggable and versionable.

use std::ffi::{c_char, CStr, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};

use sophia_core::LintOptions;

fn to_c(json: Vec<u8>) -> *mut c_char {
    CString::new(json)
        .unwrap_or_else(|_| CString::new("[]").expect("static JSON"))
        .into_raw()
}

unsafe fn c_str<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }
    CStr::from_ptr(ptr).to_str().ok()
}

/// Lint `text` (UTF-8, NUL-terminated) with `opts_json` (may be null — see
/// [`sophia_core::LintOptions`]). Returns a heap JSON array of issues; release
/// with [`sophia_free`]. Never null, never panics across the boundary; any
/// internal failure returns `[]`.
///
/// # Safety
/// `text` and `opts_json` must each be null or a valid NUL-terminated C string.
#[no_mangle]
pub unsafe extern "C" fn sophia_lint(
    text: *const c_char,
    opts_json: *const c_char,
) -> *mut c_char {
    let json = catch_unwind(AssertUnwindSafe(|| {
        let Some(text) = c_str(text) else {
            return b"[]".to_vec();
        };
        let opts = c_str(opts_json)
            .and_then(|s| serde_json_from(s))
            .unwrap_or_default();
        sophia_core::lint_text(text, &opts)
    }))
    .unwrap_or_else(|_| b"[]".to_vec());
    to_c(json)
}

fn serde_json_from(s: &str) -> Option<LintOptions> {
    // serde_json is a sophia-core dependency; parse there to keep this crate thin.
    sophia_core::parse_options(s)
}

/// Pre-load the dictionary and rule set so the first real lint is fast.
/// Call once at agent launch, off the main thread.
#[no_mangle]
pub extern "C" fn sophia_warmup() {
    let _ = catch_unwind(sophia_core::warmup);
}

/// Release a string returned by `sophia_lint`.
///
/// # Safety
/// `ptr` must be a pointer previously returned by this library, or null.
#[no_mangle]
pub unsafe extern "C" fn sophia_free(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    #[test]
    fn null_inputs_degrade_to_empty() {
        unsafe {
            let out = sophia_lint(std::ptr::null(), std::ptr::null());
            assert_eq!(CStr::from_ptr(out).to_str().unwrap(), "[]");
            sophia_free(out);
        }
    }

    #[test]
    fn round_trip_with_options() {
        let text = CString::new("I met Addisuna yesterday.").unwrap();
        let opts = CString::new(r#"{"dictionary":["Addisuna"]}"#).unwrap();
        unsafe {
            let out = sophia_lint(text.as_ptr(), opts.as_ptr());
            let s = CStr::from_ptr(out).to_str().unwrap();
            assert!(!s.contains("Addisuna"), "dictionary term flagged: {s}");
            sophia_free(out);
        }
    }
}
