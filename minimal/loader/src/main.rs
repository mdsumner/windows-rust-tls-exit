//! Loads awslc_dll.dll from next to this exe with LoadLibraryW, as R loads
//! a package DLL, calls one export, and returns from main with the DLL still
//! loaded (R never frees package DLLs at exit), so the DLL's exit-time
//! destructors run on DLL_PROCESS_DETACH, inside ExitProcess.
//!   loader <mode>
//! Modes:
//!   load               load the DLL, call nothing
//!   rand               RAND_bytes on the main thread
//!   rand-thread        RAND_bytes on a thread joined before exit
//!   rand-thread-alive  RAND_bytes on a thread still running at exit
//!   rand-free          rand, then FreeLibrary before exit (detach outside ExitProcess)
//!   preload-rand       load bcryptprimitives.dll before the DLL, then rand
//!   rand-zeroize-now   rand, then run aws-lc's exit zeroization before exit
use std::ffi::c_void;
use std::process::ExitCode;

type Hmodule = *mut c_void;

#[link(name = "kernel32")]
extern "system" {
    fn LoadLibraryW(name: *const u16) -> Hmodule;
    fn GetModuleHandleW(name: *const u16) -> Hmodule;
    fn GetProcAddress(module: Hmodule, name: *const u8) -> *mut c_void;
    fn FreeLibrary(module: Hmodule) -> i32;
    fn GetLastError() -> u32;
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(Some(0)).collect()
}

fn bcrypt_loaded(when: &str) {
    let h = unsafe { GetModuleHandleW(wide("bcryptprimitives.dll").as_ptr()) };
    println!("{when}: bcryptprimitives.dll loaded: {}", !h.is_null());
}

fn main() -> ExitCode {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "rand".to_string());
    bcrypt_loaded("start");
    if mode.starts_with("preload") {
        let h = unsafe { LoadLibraryW(wide("bcryptprimitives.dll").as_ptr()) };
        println!("preloaded bcryptprimitives.dll: {}", !h.is_null());
    }
    let dll = std::env::current_exe().unwrap().with_file_name("awslc_dll.dll");
    let h = unsafe { LoadLibraryW(wide(&dll.to_string_lossy()).as_ptr()) };
    if h.is_null() {
        eprintln!("LoadLibraryW({}) failed: error {}", dll.display(), unsafe { GetLastError() });
        return ExitCode::from(2);
    }
    bcrypt_loaded("after loading awslc_dll.dll");
    let call = |sym: &str| -> i32 {
        let name = format!("{sym}\0");
        let p = unsafe { GetProcAddress(h, name.as_ptr()) };
        if p.is_null() {
            eprintln!("awslc_dll.dll has no export {sym}");
            std::process::exit(3);
        }
        let f: extern "C" fn() -> i32 = unsafe { std::mem::transmute(p) };
        f()
    };
    match mode.as_str() {
        "load" => {}
        "rand" | "rand-free" | "preload-rand" | "rand-zeroize-now" => {
            println!("RAND_bytes on the main thread: {}", call("awslc_rand_main"))
        }
        "rand-thread" => println!("RAND_bytes on a joined thread: {}", call("awslc_rand_joined_thread")),
        "rand-thread-alive" => println!("RAND_bytes on a live thread: {}", call("awslc_rand_live_thread")),
        m => {
            eprintln!("unknown mode {m}");
            return ExitCode::from(2);
        }
    }
    bcrypt_loaded("after the call");
    if mode == "rand-zeroize-now" {
        println!("aws-lc exit zeroization, run now: {}", call("awslc_zeroize_now"));
    }
    if mode == "rand-free" {
        println!("FreeLibrary: {}", unsafe { FreeLibrary(h) });
    }
    println!("end of main");
    ExitCode::SUCCESS
}
