# vrtstack (development version)


## New features

* New `vrtstack()` is a single entry point with two construction paths that
  share one concat-axis resolver:
  - **from-scratch** (`template = NULL`) — the existing GeoTIFF/COG behaviour,
    stacking 2D sources into a single new 3D array.
  - **template-extend** (`template = <vrt>` or `template = TRUE`) — fleshes out
    a small "first-n" multidimensional VRT to a full file set, re-parameterising
    only the concat dimension and the per-array `<Source>` lists. Coordinate
    arrays, slab geometry, and per-array scale/offset/unit/attributes are carried
    through verbatim from the template.

* New `mdim_template_extend()` performs the recipe rewrite as a pure xml2
  tree operation (no GDAL required). It handles sources that themselves carry
  several arrays (e.g. OISST `anom`/`err`/`ice`/`sst`): data arrays are detected
  structurally as any `<Array>` owning a `<Source>`, and each array's
  `SourceArray` path and slab `count`/`step` are read from its first source
  rather than assumed from the array name. The concat axis position is taken
  from `DimensionRef` order, so it need not be axis 0.

* New `resolve_concat()` turns a concat-axis spec (explicit vector, single-group
  regex over basenames, function of basename, or date-parsing inputs) into axis
  values, and is shared by both construction paths.

* New `mdim_mosaic_xml()` builds the first-n recipe via `gdal mdim mosaic`
  through `/vsimem/`, so no template file need touch disk (requires gdalraster
  with the `gdal_run` algorithm interface).

## Minor improvements and fixes

* Filename extraction now uses `stringr::str_match()` instead of
  `regmatches()`/`regexec()`, which silently dropped non-matches and misaligned
  rows against `files`.

* VRT construction and editing now go through xml2 rather than string assembly,
  removing the hand-rolled XML escaping.

* `mdim_template_extend()` rejects `Date`/`POSIXct` `concat_values` with a clear
  message: coordinate values must already be in the array's declared units
  (e.g. days-since-epoch). Encode them first via `resolve_concat(origin=, unit=)`
  or read them from the source files.

## vrtstack (0.1.0)

* `gdal_mdim_stack()` and the convenience wrappers `vrt_time_stack()`,
  `vrt_depth_stack()`, and `vrt_regular_stack()` for stacking 2D rasters into a
  multidimensional VRT along a new dimension, with regular-axis detection,
  filename-based dimension values, and `/vsicurl/` support.
