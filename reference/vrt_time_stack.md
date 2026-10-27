# Stack Time Series Rasters into Multidimensional VRT

A convenience wrapper for
[`gdal_mdim_stack()`](https://hypertidy.github.io/vrtstack/reference/gdal_mdim_stack.md)
tailored for time series data. Extracts dates from filenames and encodes
them as numeric offsets from an origin.

## Usage

``` r
vrt_time_stack(
  files,
  pattern = "(\\d{8})",
  format = "%Y%m%d",
  origin = "1970-01-01",
  unit = "days",
  array_name = NULL,
  output = NULL
)
```

## Arguments

- files:

  Character vector of file paths

- pattern:

  Regex pattern with one capturing group for the date portion. Default:
  `"(\\d{8})"` matches 8-digit dates like `20230115`.

- format:

  strptime format for parsing. Default: `"%Y%m%d"`

- origin:

  Time origin as `"YYYY-MM-DD"` string. Default: `"1970-01-01"`

- unit:

  Time unit: `"days"`, `"hours"`, `"minutes"`, `"seconds"`. Default:
  `"days"`

- array_name:

  Name for the data array

- output:

  Output VRT path

## Value

Path to VRT file (invisibly), or XML string if `output` is NULL.

## Examples

``` r
if (FALSE) { # \dontrun{
# Daily temperature files: temp_20230101.tif, temp_20230102.tif, ...
vrt_time_stack(
  files = list.files(pattern = "temp_\\d{8}\\.tif$"),
  output = "temperature_timeseries.vrt"
)

# Custom pattern for ISO dates: data_2023-01-15.tif
vrt_time_stack(
  files = my_files,
  pattern = "(\\d{4}-\\d{2}-\\d{2})",
  format = "%Y-%m-%d",
  output = "timeseries.vrt"
)
} # }
```
