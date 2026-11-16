# Control: another R package with the same Rust HTTP/TLS stack and no icechunk.
# rustycogs: object_store 0.13 + reqwest 0.13 "rustls" (aws-lc-rs, platform
# verifier), extendr, the same Makevars.win recipe (Rtools, libgcc_mock).
#   Rscript r/rustycogs.R <load|https>
case <- commandArgs(TRUE)[1]
suppressPackageStartupMessages(library(rustycogs))
d <- utils::packageDescription("rustycogs")
cat("rustycogs", d$Version, "sha", d$RemoteSha, "built", d$Built, "\n")
switch(case,
  load = invisible(),
  https = {
    x <- tiff_ifd_info("https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N00_00_E006_00_DEM/Copernicus_DSM_COG_10_N00_00_E006_00_DEM.tif")
    stopifnot(nrow(x) > 0); cat("IFDs read over HTTPS:", nrow(x), "\n")
  },
  stop("unknown case ", case)
)
cat("end of script\n")
