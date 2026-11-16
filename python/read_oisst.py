"""One case per process: python python/read_oisst.py <https|s3|open>

The same OISST repository and chunk as r/cases.R, through icechunk-python,
whose Windows wheels are built with MSVC (R packages: the GNU toolchain).
"""

import json
import pathlib
import sys
import tempfile
import zipfile

import icechunk
import zarr

case = sys.argv[1] if len(sys.argv) > 1 else "https"
cell = "s3" if case == "s3" else "https"
here = pathlib.Path(__file__).resolve().parent.parent / "data" / "oisst-sample"
probe = json.loads((here / "probe.json").read_text())
zp = next(here.glob(f"repo-{cell}-*.zip"))
d = pathlib.Path(tempfile.mkdtemp()) / "repo"
zipfile.ZipFile(zp).extractall(d)

prefix = probe["cells"][cell]["ref_prefix"]
if cell == "s3":
    auth = icechunk.containers_credentials({prefix: icechunk.s3_anonymous_credentials()})
else:
    auth = {prefix: None}
repo = icechunk.Repository.open(
    icechunk.local_filesystem_storage(str(d)),
    authorize_virtual_chunk_access=auth,
)
session = repo.readonly_session(tag="cf-repaired")
print("icechunk", icechunk.__version__, "| zarr", zarr.__version__, "| case", case)
arr = zarr.open_array(session.store, path="sst", mode="r")
if case == "open":
    print("sst shape:", arr.shape)
else:
    p = probe["probe"]
    v = int(arr[p["time_index"], 0, p["iy_stored"], p["ix"]])
    print(cell, "probe value:", v, "expected:", p["sst_packed"])
print("end of script")
