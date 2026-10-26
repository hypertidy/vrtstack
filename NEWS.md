# vrtstack (development version)

## New features

* `vrtstack()` gains `metadata_from` (`"first"`, `"last"`, or an explicit source
  path) to choose which source donates the coordinate units and root-group
  provenance restored onto an auto-generated recipe (`template = TRUE`).

* The concat dimension may be any axis, not only axis 0, and need not be named
  `"time"`: `mdim_template_extend()` takes the axis position from `DimensionRef`
  order. A regularly-spaced concat coordinate is converted to explicit inline
  values when `concat_values` are supplied.

## Bug fixes

* `mdim_template_extend()` now gives a clear error when the concat dimension has
  no coordinate array of the same name, instead of an opaque xml node-type
  error, and validates inline-vs-regular coordinate values robustly.

## Packaging

* `.Rbuildignore` now excludes `.github` and local scratch directories.

# vrtstack 0.2.0

## Bug fixes

* `gdal_mdim_stack()` no longer derives the data-array name from a bare common
  filename prefix, which could produce a numeric, invalid array name (e.g.
  `200206` from a shared date). The resolver now takes the variable token from
  the shared part of the names -- the first identifier word of the common
  prefix or the last of the common suffix, whichever carries more letters (e.g.
  `analysed_sst` from GHRSST tiles, `claytotal` from soil layers) -- never a
  leading-digit name, and falls back to `band1`. An explicit `array_name` still
  overrides. Band-description-based naming is left as a later option. (#1)

* `gdal_mdim_stack()` now writes a `<SourceSlab offset="0,0,0"
  count="1,nrow,ncol" step="1,1,1"/>` in every source. Without the count,
  GDAL opens every source, in order, to learn its shape on each read
  through the VRT (a HEAD and a header GET per `/vsicurl/` COG), so even a
  one-step read of a long remote stack touched every file. With it, a read
  opens only the sources it covers. Same finding as
  mdsumner/raad.virtualize#14; see also hypertidy/gdalxarray#39, which
  stops sparse selections being widened to a covering read. The
  template-extend path in `vrtstack()` already copied the count from its
  template. Tests added (`tests/testthat/test-sourceslab.R`).


## New features

* New `graft_coord_units()` and `graft_group_attrs()` restore metadata that
  `gdal mdim mosaic` drops from a recipe: coordinate-array units (CF `units`,
  which the netCDF driver lifts into the array Unit rather than an attribute)
  and invariant root-group provenance attributes (title, source, references).
  Both are idempotent and read the values from one source via `gdal mdim info`,
  or from a supplied `units=`/`attrs=` vector that needs no GDAL. They are wired
  into the `template = TRUE` path of `vrtstack()` via an internal
  `mdim_recipe_xml()`, and become no-ops once GDAL propagates the metadata
  itself.

* New `vrtstack()` is a single entry point with two construction paths that
  share one concat-axis resolver:
  - **from-scratch** (`template = NULL`) - the existing GeoTIFF/COG behaviour,
    stacking 2D sources into a single new 3D array.
  - **template-extend** (`template = <vrt>` or `template = TRUE`) - fleshes out
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

## Packaging

* Declared `xml2`, `stringr`, `jsonlite` and `utils` in `Imports` (they were
  used but undeclared, an `R CMD check` error).

* Added continuous integration: a standard `R-CMD-check` matrix, and a canary
  job that checks against a development GDAL build (hypertidy
  `gdal-r-python:dev`), so changes in GDAL's multidim surface are caught early.

## vrtstack (0.1.0)

* `gdal_mdim_stack()` and the convenience wrappers `vrt_time_stack()`,
  `vrt_depth_stack()`, and `vrt_regular_stack()` for stacking 2D rasters into a
  multidimensional VRT along a new dimension, with regular-axis detection,
  filename-based dimension values, and `/vsicurl/` support.
