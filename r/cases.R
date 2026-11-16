# One case per process: Rscript r/cases.R <case>
# tabularberg is the r-universe Windows binary (built with Rtools, the GNU
# toolchain). From c741ef9 on it also shuts its tokio runtime down from an R
# exit finalizer; that did not stop the crash.
case <- commandArgs(TRUE)[1]
suppressPackageStartupMessages(library(tabularberg))
d <- utils::packageDescription("tabularberg")
cat("tabularberg", d$Version, "sha", d$RemoteSha, "built", d$Built, "\n")
cat("features:", ic_compiled_features(), "\n")

read_oisst <- function(cell) {
  ox <- ic_example_oisst(cell)
  s <- ic_session_readonly(ic_repo_open(ox$path, authorize = ox$authorize), tag = "cf-repaired")
  cat(cell, "chunk bytes:", length(ic_get(s, "sst/c/0/0/0/0")), "\n")
  invisible(s)
}

switch(case,
  # the package loaded, nothing else
  load = invisible(),
  # Icechunk on local files only: example repo, virtual refs to file://
  local = {
    ex <- ic_example_repo()
    s <- ic_session_readonly(ic_repo_open(ex$path, authorize = ex$authorize), branch = "main")
    cat("local chunk bytes:", length(ic_get(s, "from_bin/c/0/0")), "\n")
  },
  # opens the https repository (metadata is local), no chunk read
  "https-open" = {
    ox <- ic_example_oisst("https")
    s <- ic_session_readonly(ic_repo_open(ox$path, authorize = ox$authorize), tag = "cf-repaired")
    cat("refs:", nrow(ic_chunk_refs(s, "/sst")), "\n")
  },
  # one virtual chunk read from NOAA over HTTPS
  https = read_oisst("https"),
  # the same, then every Rust object dropped and the runtime shut down
  "https-drop-all" = {
    read_oisst("https")
    rm(list = ls(all.names = TRUE)); invisible(gc()); invisible(gc())
    cat("runtime shutdown:", tabularberg:::ic_runtime_shutdown_(), "\n")
  },
  # one virtual chunk read from the NOAA bucket over S3 (anonymous)
  s3 = read_oisst("s3"),
  stop("unknown case ", case)
)
cat("end of script\n")
