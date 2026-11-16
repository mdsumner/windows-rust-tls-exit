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

Next steps, depending on the first: a minimal extendr package with only the
HTTPS GET (R + GNU + TLS, no icechunk); then swaps of aws-lc for ring, and of
the platform verifier for bundled roots.

## Data

`data/oisst-sample/`: ten days of NOAA OISST v2.1 as Icechunk repositories
(metadata and references only, 55 KB), from
[zarr-icechunk-assure](https://github.com/mdsumner/zarr-icechunk-assure)
via tabularberg's `inst/extdata`. See its README.
