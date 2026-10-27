# Stack Rasters with Regular Spacing

A convenience wrapper for
[`gdal_mdim_stack()`](https://hypertidy.github.io/vrtstack/reference/gdal_mdim_stack.md)
when files represent regularly spaced values (e.g., monthly data, hourly
snapshots, uniform vertical levels).

## Usage

``` r
vrt_regular_stack(
  files,
  dim_name,
  start,
  increment,
  unit = NULL,
  array_name = NULL,
  output = NULL
)
```

## Arguments

- files:

  Character vector of file paths, in order

- dim_name:

  Name for the new dimension

- start:

  Starting value

- increment:

  Spacing between values

- unit:

  Unit string

- array_name:

  Name for the data array

- output:

  Output VRT path

## Value

Path to VRT file (invisibly), or XML string if `output` is NULL.

## Examples

``` r
if (FALSE) { # \dontrun{
# 12 monthly files
vrt_regular_stack(
  files = sprintf("precip_%02d.tif", 1:12),
  dim_name = "month",
  start = 1,
  increment = 1,
  output = "monthly_precip.vrt"
)

# Pressure levels at 50 hPa intervals
vrt_regular_stack(
  files = level_files,
  dim_name = "pressure",
  start = 1000,
  increment = -50,
  unit = "hPa",
  output = "pressure_levels.vrt"
)
} # }
```
