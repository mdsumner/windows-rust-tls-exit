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

## Finding (runs 2-5, 2026-11-16)

**aws-lc's exit-time DRBG zeroization calls `BCryptGenRandom` from
`DLL_PROCESS_DETACH`, inside `ExitProcess`. There it fails, and aws-lc
calls `abort()`.** This needs aws-lc to be:

- **statically linked into a DLL**, so its exit destructor sits in the DLL's
  own atexit table, which the CRT runs on `DLL_PROCESS_DETACH`. That is
  every R package using rustls with its default aws-lc-rs provider.
- **built for the Windows 7 API level**. Rtools' gcc (14.3.0) defaults to
  `_WIN32_WINNT=0x0601`. At that level `CRYPTO_sysrand`
  (`rand_extra/windows.c`) uses `BCryptGenRandom`; from Windows 8 on it uses
  `ProcessPrng`, which works at that point.

It is not icechunk, tabularberg or extendr: rustycogs crashes the same way.
MSVC builds (the icechunk Python wheel) are fine, because they get
`ProcessPrng`.

**Fix for R packages:** build aws-lc's C at the Windows 10 level. In
`Makevars.win`, before `cargo build`:
`export AWS_LC_SYS_CFLAGS="-D_WIN32_WINNT=0x0A00"`. Rust's own Windows
targets require Windows 10 anyway. tabularberg does this from `b3497ff`.

### Minimal repro, no R (runs 4-5, [`minimal/`](minimal/))

`awslc_dll.dll` contains only aws-lc (aws-lc-rs 1.19.0 / aws-lc-sys 0.47.0).
`loader.exe` loads it with `LoadLibraryW`, calls `RAND_bytes`, and returns
from `main` with the DLL still loaded, as R does. Exit codes for `rand`:

| aws-lc C build (`AWS_LC_SYS_CFLAGS`) | `CRYPTO_sysrand` uses | GNU (Rtools) | MSVC |
|---|---|---|---|
| base | GNU: `BCryptGenRandom`, MSVC: `ProcessPrng` | `0xC0000409` | 0 |
| `-D_WIN32_WINNT=0x0601` | `BCryptGenRandom` | `0xC0000409` | `0xC0000409` |
| `-D_WIN32_WINNT=0x0A00` | `ProcessPrng` | 0 | 0 |
| `-DBORINGSSL_SHARED_LIBRARY` | zeros at exit (aws-lc's own DLL build) | 0 | 0 |

The `BCryptGenRandom` builds (GNU base, both win7) behave the same across the modes:

| mode | exit |
|---|---|
| `load` (no RAND) | 0 |
| `rand` on the main thread | `0xC0000409` |
| `rand-thread`: on a thread joined before exit, so its state is freed | 0 |
| `rand-thread-alive`: on a thread killed by `ExitProcess`, like tokio's workers | `0xC0000409` |
| `rand-free`: `FreeLibrary` before exit, so detach runs outside `ExitProcess` | 0 |
| `preload-rand`: bcryptprimitives.dll loaded first (it was already) | `0xC0000409` |
| `rand-zeroize-now`: aws-lc's zeroization called before exit | 0 |

These builds were checked from the binaries, not assumed. The GNU base DLL
imports `bcrypt!BCryptGenRandom` and lacks the `L"bcryptprimitives"` string
that the `ProcessPrng` path loads. The same holds for the r-universe
tabularberg.dll. With `0x0A00` the import goes away.

Stack, MSVC build with `-D_WIN32_WINNT=0x0601` (PDB, so aws-lc's frames
are named):

```
ucrtbase!abort
awslc_dll!aws_lc_0_47_0_CRYPTO_sysrand+0x69            rand_extra/windows.c @ 48: BCryptGenRandom failed
awslc_dll!aws_lc_0_47_0_CRYPTO_sysrand_if_available    (inline)
awslc_dll!tree_jitter_zeroize_drbg+0x2d                fipsmodule/rand/entropy/tree_drbg_jitter_entropy.c
awslc_dll!rand_thread_local_state_clear_all+0x7e       fipsmodule/rand/rand.c @ 124
ucrtbase!execute_onexit_table                          the DLL's own atexit list
awslc_dll!dllmain_crt_process_detach                   dll_dllmain.cpp @ 182
ntdll!LdrShutdownProcess
ntdll!RtlExitUserProcess / KERNEL32!ExitProcessImplementation
ucrtbase!common_exit
loader!__scrt_common_main_seh
```

The GNU builds (cdb has no symbols for them) and R + tabularberg (run 3)
show the same shape, with `pthread_once` in between: MinGW gcc builds aws-lc
with pthreads. Run 3 named the last frame `ProcessPrng`, read against the
source's default branch. The binaries show it is `BCryptGenRandom`.

### R + tabularberg built from source (runs 4-5)

| aws-lc build | `load`, `local` | `https`, `s3` |
|---|---|---|
| base | 0 | `0xC0000409` |
| `-D_WIN32_WINNT=0x0601` | 0 | `0xC0000409` |
| `-D_WIN32_WINNT=0x0A00` | 0 | 0 |
| `-DBORINGSSL_SHARED_LIBRARY` (the DLL then exports ~2,900 aws-lc symbols) | 0 | 0 |
| base, plus aws-lc's zeroization called from R's exit finalizer ([patch](patches/tabularberg-awslc-zeroize-at-exit.patch); a test-only, version-prefixed symbol) | 0 | 0 |

### Earlier runs (2-3)

| case | exit |
|---|---|
| R + tabularberg (r-universe binary): `load`, `local`, `https-open` (no chunk fetched) | 0 |
| R + tabularberg: `https`, `s3`, `https-drop-all` (all objects dropped, runtime shut down) | `0xC0000409` |
| R + rustycogs: `load` / `https` | 0 / `0xC0000409` |
| Python + icechunk wheel (MSVC): `open`, `https`, `s3` | 0 |
| Rust exe, same crates, GNU (Rtools) and MSVC: all modes | 0 |

A plain exe survives because its destructor runs from the exe's `atexit`
inside `exit()`, before `ExitProcess`.

### Upstream

aws-lc already handles this hazard, but only for its own DLL build
(`tree_drbg_jitter_entropy.c`, above `tree_jitter_zeroize_drbg`):

> Windows shared builds take the zeros option: there this runs from a
> libcrypto global destructor on `DLL_PROCESS_DETACH`, after `ExitProcess`,
> [...] Static builds run it from the executable's `atexit` and are
> unaffected.

That doesn't hold for a static aws-lc linked into a DLL. Two possible fixes:

- **aws-lc:** take the zeros option on Windows wherever this can run on
  `DLL_PROCESS_DETACH` (any Windows build), or don't `abort()` in
  `CRYPTO_sysrand_if_available`.
- **aws-lc-sys:** its cc builder sets `_WIN32_WINNT=0x0601` for `-win7-`
  triples. It could set `0x0A00` for the other Windows triples, so MinGW
  builds stop inheriting the toolchain's Windows 7 default.

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
