# Stack rasters into a multidimensional VRT (two paths, one entry point)

`vrtstack()` builds a GDAL multidimensional VRT that concatenates a set
of sources along one axis. Two construction paths share a single
concat-axis resolver:

## Usage

``` r
vrtstack(
  files,
  concat = NULL,
  template = NULL,
  concat_dim = "time",
  n_template = 10,
  parse_format = NULL,
  origin = NULL,
  unit = "days",
  metadata_from = "first",
  output = NULL,
  ...
)
```

## Arguments

- files:

  Character vector of source paths/URIs (full set).

- concat:

  Concat-axis spec, resolved by
  [`resolve_concat()`](https://hypertidy.github.io/vrtstack/reference/resolve_concat.md):
  a numeric/ character vector (length == `files`), a single regex with
  one capture group to pull from basenames, a function of basename, or
  `NULL` to use `concat_start`/`concat_increment` (from-scratch) or the
  template's own values (template-extend, when concat is `NULL`).

- template:

  One of: `NULL` (from-scratch); a path to a `.vrt`; an XML string; or
  `TRUE` to auto-generate the recipe from `head(files, n_template)` via
  `gdal mdim mosaic`.

- concat_dim:

  Name of the concatenation dimension. Default `"time"`.

- n_template:

  Files used to build the auto-generated recipe when `template = TRUE`.
  Default 10.

- parse_format, origin, unit:

  Passed to
  [`resolve_concat()`](https://hypertidy.github.io/vrtstack/reference/resolve_concat.md)
  for date parsing.

- metadata_from:

  Which source donates the coordinate units and root-group provenance
  restored onto an auto-generated recipe (`template = TRUE`): one of
  `"first"` (default), `"last"`, or an explicit source path. Ignored
  when `template` is a supplied VRT or XML string, which already carries
  its own metadata.

- output:

  Output VRT path, or `NULL` to return the XML string.

- ...:

  Passed to the from-scratch builder (`dim_type`, `dim_unit`,
  `array_name`, etc.) and ignored on the template path.

## Value

Path to the VRT (invisibly) or the XML string if `output` is `NULL`.

## Details

- **from-scratch** (`template = NULL`) - the original GeoTIFF/COG path.
  Each 2D source contributes one slab of a *single* new 3D array.
  Sources use the classic `<SourceBand>` + `<SourceTranspose>` form.

- **template-extend** (`template = <vrt>` or `template = TRUE`) - for
  mdim-recognised sources (NetCDF/Zarr/HDF5) that may carry *several*
  arrays (OISST: anom/err/ice/sst). A small "first-n" mdim VRT is taken
  as the recipe, and the full file set is fleshed out by
  re-parameterising only the concat dimension and the per-array
  `<Source>` lists. Everything else (coordinate arrays, slab geometry,
  scale/offset/unit/attributes) is carried verbatim from the template.

The template is the GDAL-native analogue of the "recipe-not-payload"
principle: GDAL's own `gdal mdim mosaic` writes the recipe for the first
n files; we only template the axis that varies with the file set.

## Examples

``` r
#vrt <- vrtstack(<files>, concat = "(\d{8})", parse_format = "%Y%m%d",
#origin = "1978-01-01", unit = "days",   # must match the template
#template = TRUE, concat_dim = "time")
```
