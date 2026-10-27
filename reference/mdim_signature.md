# Construct a grid signature for a multidimensional VRT

One row (as a list) per collection: the grid geometry and array metadata
the emitter needs, derived from catalog metadata or a single cached
probe. The emitter trusts these values, so a collection with non-aligned
assets is a signature-gate refusal, never a resample.

## Usage

``` r
mdim_signature(
  collection,
  variable,
  nx,
  ny,
  x0,
  dx,
  y0,
  dy,
  srs,
  dtype,
  nodata = NA,
  scale = NA,
  offset = NA,
  unit = NA_character_,
  steps_per_file = 1L,
  chunk_nx = NA_integer_,
  chunk_ny = NA_integer_,
  provenance = "probe"
)
```

## Arguments

- collection, variable:

  Identifiers for the collection and data array.

- nx, ny:

  Grid dimensions in X and Y.

- x0, dx, y0, dy:

  Grid origin and spacing as pixel-centre coordinates in the array's own
  orientation (`dy` is typically negative for north-up grids).

- srs:

  Spatial reference (e.g. `"EPSG:4326"` or a WKT string).

- dtype:

  VRT data type of the array (e.g. `"Int16"`, `"Float32"`).

- nodata, scale, offset, unit:

  Optional array metadata; `NA` to omit.

- steps_per_file:

  Number of concat-axis steps stored in each source file.

- chunk_nx, chunk_ny:

  Optional source chunk (block) shape, recorded for later byte-range
  harvesting.

- provenance:

  Free text recording where the grid facts came from (catalog, probe, or
  a published grid).

## Value

A named list describing one collection's grid and array metadata.

## See also

[`mdim_sources()`](https://hypertidy.github.io/vrtstack/reference/mdim_sources.md),
[`emit_mdim_vrt()`](https://hypertidy.github.io/vrtstack/reference/emit_mdim_vrt.md)
