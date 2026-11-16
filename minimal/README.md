# Minimal repro: static aws-lc in a DLL aborts at process exit

No R, no TLS, no icechunk. `awslc-dll` is a DLL whose only content is
aws-lc (aws-lc-rs 1.19.0 / aws-lc-sys 0.47.0, as rustls pulls it in), with
exports that call `RAND_bytes`. `loader` loads it with `LoadLibraryW`, as R
loads a package DLL, calls one export, and returns from `main` with the DLL
still loaded. aws-lc's exit-time zeroization then runs from the DLL's own
atexit table on `DLL_PROCESS_DETACH`, inside `ExitProcess`.

```
cargo build --release --target x86_64-pc-windows-gnu   # or -msvc
target/<target>/release/loader.exe rand                 # expected: 0xC0000409
```

Modes (see `loader/src/main.rs`): `load`, `rand`, `rand-thread` (on a thread
joined before exit), `rand-thread-alive` (on a thread still running at exit,
like tokio's workers), `rand-free` (`FreeLibrary` before exit), `preload-rand`
(`bcryptprimitives.dll` loaded before the DLL), `rand-zeroize-now` (aws-lc's
exit zeroization called before exit).

aws-lc build variants, through `AWS_LC_SYS_CFLAGS` (CI: `../.github/workflows/minimal.yaml`):

| variant | flags | what it changes |
|---|---|---|
| base | none | as rustls builds it |
| shared | `-DBORINGSSL_SHARED_LIBRARY` | the zeroization uses zeros, as aws-lc's own DLL build does (also makes the aws-lc API `dllexport`) |
| win7 | `-D_WIN32_WINNT=0x0601` | `CRYPTO_sysrand` uses `BCryptGenRandom` (bcrypt.dll, a static import) instead of `ProcessPrng` (bcryptprimitives.dll, loaded on demand) |
