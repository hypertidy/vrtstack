# Construct a sources table for a multidimensional VRT

One row per output step along the concat (time) axis. This is the
interface contract produced by adapters and consumed by
[`emit_mdim_vrt()`](https://hypertidy.github.io/vrtstack/reference/emit_mdim_vrt.md).

## Usage

``` r
mdim_sources(
  time,
  dsn,
  source_ref,
  kind,
  step_in_file = 0L,
  dest_index = NULL,
  source_view = NA_character_
)
```

## Arguments

- time:

  Vector of per-step coordinate values (e.g. a `Date` vector).

- dsn:

  Source data source names (file paths or `/vsicurl/` URIs).

- source_ref:

  Array path (e.g. `"/sst"`) when `kind = "array"`, or band number (e.g.
  `"1"`) when `kind = "band"`.

- kind:

  Source flavour: `"array"` (`<SourceArray>`, a multidimensional source)
  or `"band"` (`<SourceBand>`, a classic 2D source).

- step_in_file:

  Zero-based step index within a multi-step file.

- dest_index:

  Zero-based destination position along the concat axis; defaults to the
  rank order of `time`.

- source_view:

  Optional GetView expression that brings each source to exactly the
  destination rank (e.g. `"[newaxis,...]"` to rank a 2D band up to a 3D
  cube, `"[:,0,:,:]"` to drop a singleton dimension). `NA` for none.

## Value

A data frame ordered by `dest_index`, one row per output step.

## See also

[`mdim_signature()`](https://hypertidy.github.io/vrtstack/reference/mdim_signature.md),
[`emit_mdim_vrt()`](https://hypertidy.github.io/vrtstack/reference/emit_mdim_vrt.md)
