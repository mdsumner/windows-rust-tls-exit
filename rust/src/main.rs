//! One read, then exit: does the process survive its own teardown?
//!
//! Usage: tls-exit <mode>
//!   none            build the runtime, do nothing
//!   http            reqwest GET of $HTTP_URL (plain http, no TLS)
//!   https           reqwest GET (Range) of a NOAA OISST file over HTTPS
//!   https-shutdown  as https, then shut the runtime down before exit
//!   object-store    object_store HttpStore get_range of the same file
//!                   (the client path icechunk's HTTP fetcher uses)
//!
//! Except for https-shutdown, the runtime lives in a static that is never
//! dropped, as in an R package (tabularberg before c741ef9): main() returns
//! with worker threads and connection pools still live.

use std::sync::OnceLock;
use std::time::Duration;
use tokio::runtime::Runtime;

const HOST: &str = "https://www.ncei.noaa.gov";
const KEY: &str = "data/sea-surface-temperature-optimum-interpolation/v2.1/access/avhrr/198109/oisst-avhrr-v02r01.19810901.nc";

static RT: OnceLock<Runtime> = OnceLock::new();

fn build() -> Runtime {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(4)
        .enable_all()
        .build()
        .expect("runtime")
}

fn rt() -> &'static Runtime {
    RT.get_or_init(build)
}

async fn reqwest_get(url: &str) -> usize {
    let client = reqwest::Client::new();
    let resp = client
        .get(url)
        .header("Range", "bytes=0-1023")
        .send()
        .await
        .expect("send");
    let status = resp.status();
    let n = resp.bytes().await.expect("body").len();
    println!("reqwest {url}: {status}, {n} bytes");
    n
}

async fn object_store_get() -> usize {
    use object_store::{http::HttpBuilder, path::Path, ObjectStoreExt};
    let store = HttpBuilder::new().with_url(HOST).build().expect("store");
    let b = store.get_range(&Path::from(KEY), 0..1024).await.expect("get_range");
    println!("object_store {HOST}/{KEY}: {} bytes", b.len());
    b.len()
}

fn main() {
    let mode = std::env::args().nth(1).unwrap_or_else(|| "none".into());
    println!("mode {mode}, target {}", std::env::consts::ARCH);
    let https = format!("{HOST}/{KEY}");
    match mode.as_str() {
        "none" => {
            rt();
        }
        "http" => {
            let url = std::env::var("HTTP_URL").expect("HTTP_URL");
            rt().block_on(reqwest_get(&url));
        }
        "https" => {
            rt().block_on(reqwest_get(&https));
        }
        "object-store" => {
            rt().block_on(object_store_get());
        }
        "https-shutdown" => {
            let local = build();
            local.block_on(reqwest_get(&https));
            local.shutdown_timeout(Duration::from_secs(2));
            println!("runtime shut down");
        }
        m => panic!("unknown mode {m}"),
    }
    println!("end of main");
}
