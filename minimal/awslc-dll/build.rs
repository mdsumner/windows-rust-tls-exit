// The "win7" variant (AWS_LC_SYS_CFLAGS selects aws-lc's BCryptGenRandom
// path) needs bcrypt; MSVC gets it from a #pragma in aws-lc, MinGW does not.
// Harmless otherwise: GNU ld only pulls what is referenced.
fn main() {
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
    if os == "windows" && env == "gnu" {
        println!("cargo:rustc-link-lib=bcrypt");
    }
}
