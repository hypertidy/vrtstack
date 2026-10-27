# Stack Rasters by Depth/Level into Multidimensional VRT

A convenience wrapper for
[`gdal_mdim_stack()`](https://hypertidy.github.io/vrtstack/reference/gdal_mdim_stack.md)
for vertical profile data (soil layers, atmospheric levels, ocean
depths, etc.)

## Usage

``` r
vrt_depth_stack(
  files,
  values,
  direction = "DOWN",
  unit = NULL,
  dim_name = NULL,
  array_name = NULL,
  output = NULL
)
```

## Arguments

- files:

  Character vector of file paths

- values:

  Numeric vector of depth/level values, or regex pattern to extract

- direction:

  Vertical direction: `"DOWN"` (depth increases), `"UP"` (elevation).
  Default: `"DOWN"`

- unit:

  Unit string (e.g., `"m"`, `"cm"`, `"hPa"`)

- dim_name:

  Dimension name. Default: `"depth"` if direction is DOWN, `"level"` if
  UP.

- array_name:

  Name for the data array

- output:

  Output VRT path

## Value

Path to VRT file (invisibly), or XML string if `output` is NULL.

## Examples

``` r
if (FALSE) { # \dontrun{
# Soil layers at specific depths
vrt_depth_stack(
  files = c("soil_0cm.tif", "soil_30cm.tif", "soil_100cm.tif"),
  values = c(0, 30, 100),
  unit = "cm",
  output = "soil_profile.vrt"
)

# Extract depth from filename
vrt_depth_stack(
  files = list.files(pattern = "temp_\\d+m\\.tif$"),
  values = "(\\d+)m",  # extracts "50" from "temp_50m.tif"
  unit = "m",
  output = "ocean_profile.vrt"
)
} # }
```
