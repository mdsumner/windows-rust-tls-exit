# OISST sample repositories

Ten days of NOAA OISST v2.1 AVHRR daily sea surface temperature
(1981-09-01 to 1981-09-10) as Icechunk repositories, from
[zarr-icechunk-assure](https://github.com/mdsumner/zarr-icechunk-assure)
(`fixtures/oisst-sample/`, commit `6078b62`). Open them with
`ic_example_oisst()`.

- `repo-https-2026-07-07.zip`, `repo-s3-2026-07-07.zip`: the same
  repository built twice, with the virtual references written as
  `https://www.ncei.noaa.gov/...` or as
  `s3://noaa-cdr-sea-surface-temp-optimum-interpolation-pds/...`. Written by
  icechunk-python 2.1.0 (format v2). Two tags: `as-virtualized` (the `time`
  array has no `units` attribute, a defect kept on purpose) and
  `cf-repaired` (the units added in a metadata-only commit).
- `probe.json`: the contract the repositories are checked against (shape,
  chunking, codecs, ref prefixes, and one probe pixel: lon 199.875, lat
  -9.875, day 1, sst 2782 packed = 27.82 degrees C).
- `refs-https/<variable>/refs.0.parq`: the kerchunk-Parquet references the
  https repository was built from (padded: rows with a null `path` are
  format, not data).

The zips hold metadata, coordinates and references only. The data values
stay in NOAA's archive (public domain), fetched only when a chunk is read.
