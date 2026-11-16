//! A DLL with aws-lc statically linked, and nothing else: each export draws
//! random bytes through aws-lc-rs (RAND_bytes), which is what a TLS handshake
//! does first. Returns 1 if the bytes came back, 0 otherwise.

fn fill() -> i32 {
    let mut buf = [0u8; 32];
    match aws_lc_rs::rand::fill(&mut buf) {
        Ok(()) => 1,
        Err(_) => 0,
    }
}

/// RAND_bytes on the calling thread (the exe's main thread).
#[no_mangle]
pub extern "C" fn awslc_rand_main() -> i32 {
    fill()
}

/// RAND_bytes on a new thread, joined before returning: the thread's
/// aws-lc state is released by its thread-exit destructor.
#[no_mangle]
pub extern "C" fn awslc_rand_joined_thread() -> i32 {
    std::thread::spawn(fill).join().unwrap_or(0)
}

/// RAND_bytes on a new thread that is still running when the process exits,
/// like tokio's worker threads in R: ExitProcess kills it without running
/// its thread-exit destructors.
#[no_mangle]
pub extern "C" fn awslc_rand_live_thread() -> i32 {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || {
        let _ = tx.send(fill());
        loop {
            std::thread::park();
        }
    });
    rx.recv().unwrap_or(0)
}

// aws-lc's exit-time zeroization (rand.c), exposed for its tests; global in
// every build. Idempotent: once run, the destructor's own run is a no-op.
extern "C" {
    fn aws_lc_0_47_0_rand_thread_local_state_clear_all_FOR_TESTING();
}

/// Run aws-lc's exit-time zeroization now, before the exe exits (a candidate
/// downstream workaround: R packages could call this from an exit finalizer).
/// After this, RAND would block; only call it on the way out.
#[no_mangle]
pub extern "C" fn awslc_zeroize_now() -> i32 {
    unsafe { aws_lc_0_47_0_rand_thread_local_state_clear_all_FOR_TESTING() };
    1
}
