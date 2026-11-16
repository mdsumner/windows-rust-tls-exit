# windows-rust-tls-exit

Which layer crashes a Windows process at exit after a network read?

## The symptom

[tabularberg](https://github.com/hypertidy/tabularberg) (R, Rust via
extendr, [icechunk](https://github.com/earth-mover/icechunk) 2.3.1) works
on Windows: it builds, and every test passes. But any R process that has read
over the network crashes when it exits:

- the tests pass (`[ FAIL 0 | ... | PASS 330 ]`), then R CMD check reports
  "Running the tests failed" right after the final `proc.time()`
- `R CMD check --run-donttest`: the one example that reads a chunk from NOAA
  over HTTPS gets the right bytes, reaches `quit()`, and the run fails
- the examples run without `--run-donttest` (no network, but local Icechunk
  repositories, virtual references to local files, commits) exits cleanly

The same on Linux and macOS is fine. Shutting the tokio runtime down from
an R exit finalizer (tabularberg `c741ef9`) did not help. The TLS stack is
the same in every build tier: rustls 0.23 on aws-lc-rs 1.19, with
rustls-platform-verifier 0.7 (Windows CryptoAPI) and reqwest 0.13, under
object_store 0.14.

One difference stands out: R packages on Windows are built with the GNU
toolchain (Rtools, `x86_64-pc-windows-gnu`), while icechunk's Python wheels
are built with MSVC.

## Finding (runs 2 and 3, 2026-11-16)

**It is aws-lc's exit-time zeroization, run from `DLL_PROCESS_DETACH`.**
Not icechunk, tabularberg or extendr: rustycogs (same Rust TLS stack, no
icechunk) crashes the same way.

| case | exit |
|---|---|
| R + tabularberg: `load`, `local`, `https-open` (no chunk fetched) | 0 |
| R + tabularberg: `https`, `s3`, `https-drop-all` (all objects dropped, runtime shut down) | `0xC0000409` |
| R + rustycogs: `load` / `https` | 0 / `0xC0000409` |
| Python + icechunk wheel (MSVC): `open`, `https`, `s3` | 0 |
| Rust exe, same crates, GNU (Rtools) and MSVC: all modes | 0 |

Under cdb (`Rterm.exe`, run 3), the fail-fast is `FAST_FAIL_FATAL_APP_EXIT`
from `ucrtbase!abort`, with this stack (tabularberg; rustycogs is identical
with aws-lc 0.44). Frames named from the disassembly of the r-universe
binary (stripped; `.pdata` function bounds, import table, the string
`" once %p is %d\n"`) against aws-lc-sys 0.47.0's source:

```
R_CleanUp -> exit() -> ExitProcess -> ntdll!LdrShutdownProcess
  -> tabularberg.dll DllMain (DLL_PROCESS_DETACH, MinGW CRT)
    -> ucrtbase!execute_onexit_table         the DLL's own atexit list
      -> rand_thread_local_state_clear_all   __attribute__((destructor)), rand.c
        -> tree_jitter_zeroize_thread_drbg   (via entropy_source->methods->zeroize_thread)
          -> CRYPTO_once -> pthread_once (winpthreads)
            -> tree_jitter_zeroize_global_drbg
              -> tree_jitter_zeroize_drbg    tree_drbg_jitter_entropy.c
                -> CRYPTO_sysrand_if_available -> CRYPTO_sysrand (rand_extra/windows.c)
                  -> ProcessPrng fails -> abort()
```

aws-lc documents this exact hazard, and handles it for shared builds only
(`tree_drbg_jitter_entropy.c`, above `tree_jitter_zeroize_drbg`):

> Windows shared builds take the zeros option: there this runs from a
> libcrypto global destructor on `DLL_PROCESS_DETACH`, after `ExitProcess`,
> where `CRYPTO_sysrand` faults on bcryptprimitives.dll (loaded on demand,
> so not kept alive by libcrypto's dependency graph). Static builds run it
> from the executable's `atexit` and are unaffected.

```c
#if defined(OPENSSL_WINDOWS) && defined(BORINGSSL_SHARED_LIBRARY)
  OPENSSL_memset(random_data, 0, CTR_DRBG_ENTROPY_LEN);
#else
  CRYPTO_sysrand_if_available(random_data, CTR_DRBG_ENTROPY_LEN);
#endif
```

The gap: a **static** aws-lc linked **into a DLL** (an R package, any Rust
cdylib) is not `BORINGSSL_SHARED_LIBRARY`, so it takes the sysrand path, but
its destructors run on `DLL_PROCESS_DETACH` like a shared build's. That is
every R package using rustls with its default aws-lc-rs provider on Windows.
It needs random state to exist (a TLS handshake), hence network-only.

The plain exe survives because its destructor runs from the exe's `atexit`
inside `exit()`, before `ExitProcess`. Why the Python wheel (MSVC, also a
DLL) survives is not established; its aws-lc may predate the tree-jitter
DRBG.

Candidate fixes: upstream, take the zeros option on Windows whenever the
destructor may run during process shutdown (all Windows builds, or when
`RtlDllShutdownInProgress()`), or not abort there; downstream, define
`BORINGSSL_SHARED_LIBRARY` for aws-lc's C build (untested, affects exports),
or carry that one-line patch.

## The experiments

`.github/workflows/exit.yaml`, all on `windows-latest`. Each case is its own
process, run through `scripts/run-case.ps1`, which records the exit code
(`0xC0000005` access violation, `0xC0000409` fail-fast, ...), the
Application Error event (faulting module, exception code, offset), and a
WER minidump, analysed with cdb when the runner has it. Each job writes a
results table to its summary.

| job | what | separates |
|---|---|---|
| R + tabularberg | the r-universe Windows binary; cases `load`, `local`, `https-open`, `https`, `https-drop-all` (every Rust object dropped and the runtime shut down before exit), `s3` | network vs local Icechunk; open vs read; held objects vs global state |
| R + rustycogs (control) | another R package with the same Rust HTTP/TLS stack (object_store + reqwest 0.13 rustls/aws-lc, extendr, the same Makevars.win recipe), no icechunk: `load`, `https` (IFDs of a Copernicus DEM COG) | icechunk/tabularberg vs any R + Rust + this TLS stack |
| Python + icechunk | the same repository and chunk through the icechunk wheel (MSVC) | icechunk/object_store upstream vs our build |
| Rust exe, GNU and MSVC | one read with the same pinned crates, no R, no icechunk: `none`, `http` (local server, no TLS), `https`, `https-shutdown`, `object-store`; the GNU build is linked with Rtools' gcc, as R's Makevars.win does | toolchain; TLS vs plain HTTP; reqwest vs object_store |

Run 4 (`.github/workflows/minimal.yaml`, [`minimal/`](minimal/)): the abort
without R (a DLL containing only aws-lc, loaded by a small exe; GNU and MSVC),
and candidate workarounds, each also tried in tabularberg built from source:
aws-lc's C built with `-DBORINGSSL_SHARED_LIBRARY` (zeros) or
`-D_WIN32_WINNT=0x0601` (`BCryptGenRandom`), and tabularberg running aws-lc's
exit zeroization itself from R's exit finalizer
(`patches/tabularberg-awslc-zeroize-at-exit.patch`).

## Data

`data/oisst-sample/`: ten days of NOAA OISST v2.1 as Icechunk repositories
(metadata and references only, 55 KB), from
[zarr-icechunk-assure](https://github.com/mdsumner/zarr-icechunk-assure)
via tabularberg's `inst/extdata`. See its README.
