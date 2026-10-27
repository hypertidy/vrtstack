# Create a Multidimensional VRT from 2D Rasters

Stack 2D rasters along a new dimension, producing a GDAL
Multidimensional VRT. This enables treating a collection of 2D rasters
(COGs, GeoTIFFs, etc.) as a single multidimensional array, readable by
GDAL's multidim API and xarray backends.

## Usage

``` r
gdal_mdim_stack(
  files,
  dim_name,
  dim_values = NULL,
  dim_start = NULL,
  dim_increment = NULL,
  dim_type = NULL,
  dim_direction = NULL,
  dim_unit = NULL,
  time_origin = NULL,
  time_unit = "days",
  parse_format = NULL,
  array_name = NULL,
  output = NULL
)
```

## Arguments

- files:

  Character vector of file paths (COGs, GeoTIFFs, /vsicurl/ URIs, etc.)

- dim_name:

  Name for the new dimension (e.g., "time", "depth", "level")

- dim_values:

  Dimension values. One of:

  - Numeric vector of values (length must match files)

  - A regex pattern with one capturing group to extract from filenames

  - A function taking filename (basename) and returning a numeric value

  - NULL if using `dim_start` + `dim_increment`

- dim_start, dim_increment:

  For regular axes, specify start and increment instead of explicit
  values. Files are assumed to be in the correct order.

- dim_type:

  Optional dimension type: `"TEMPORAL"`, `"VERTICAL"`, `"PARAMETRIC"`

- dim_direction:

  Optional direction: `"NORTH"`, `"SOUTH"`, `"EAST"`, `"WEST"`, `"UP"`,
  `"DOWN"`, `"FUTURE"`, `"PAST"`

- dim_unit:

  Unit string for the dimension (e.g., `"days since 1970-01-01"`,
  `"cm"`)

- time_origin:

  For temporal dimensions, origin date as `"YYYY-MM-DD"` or POSIXct.
  When set with `parse_format`, values are encoded as offsets from this
  origin.

- time_unit:

  For temporal dimensions: `"seconds"`, `"minutes"`, `"hours"`, `"days"`

- parse_format:

  For date/time extraction, a
  [`strptime()`](https://rdrr.io/r/base/strptime.html) format string
  (e.g., `"%Y%m%d"` for `"20230115"`)

- array_name:

  Name for the data array in the VRT. Default: derived from common
  filename prefix, or `"data"`.

- output:

  Output VRT path. If NULL, returns XML string without writing.

## Value

Path to VRT file (invisibly), or XML string if `output` is NULL.

## Details

The function generates a GDAL Multidimensional VRT that virtually stacks
2D rasters along a new dimension. Key features:

- **Regular axes**: When dimension values are evenly spaced (or
  specified via `dim_start`/`dim_increment`), the VRT uses
  `<RegularlySpacedValues>` for compact representation.

- **Auto-detection**: Even with explicit `dim_values`, regular spacing
  is detected automatically and converted to the compact form.

- **Filename parsing**: Extract dimension values from filenames using
  regex, with optional date/time parsing. Useful for time series like
  `"temperature_20230101.tif"`.

- **Cloud-native**: Supports `/vsicurl/` URIs for remote files. HTTP(S)
  URLs are automatically prefixed with `/vsicurl/`.

The resulting VRT can be read by:

- GDAL's multidim API: `gdalmdiminfo`, `gdalmdimtranslate`

- Python xarray backends: gdx, xgdal

- Any tool supporting GDAL multidimensional rasters

## Examples

``` r
if (FALSE) { # \dontrun{
# Stack soil layers by depth
gdal_mdim_stack(
  files = c("soil_0cm.tif", "soil_30cm.tif", "soil_100cm.tif"),
  dim_name = "depth",
  dim_values = c(0, 30, 100),
  dim_type = "VERTICAL",
  dim_direction = "DOWN",
  dim_unit = "cm",
  output = "soil_stack.vrt"
)

# Time series with regex extraction
gdal_mdim_stack(
  files = list.files(pattern = "temp_\\d{8}\\.tif$"),
  dim_name = "time",
  dim_values = "(\\d{8})",
  parse_format = "%Y%m%d",
  dim_type = "TEMPORAL",
  time_origin = "1970-01-01",
  time_unit = "days",
  output = "temperature.vrt"
)

# Regular axis - monthly data
gdal_mdim_stack(
  files = sprintf("precip_%02d.tif", 1:12),
  dim_name = "month",
  dim_start = 1,
  dim_increment = 1,
  output = "monthly.vrt"
)

# Cloud-hosted COGs
gdal_mdim_stack(
  files = paste0(
    "https://storage.googleapis.com/solus100pub/claytotal_",
    c(0, 5, 15, 30, 60, 100, 150), "_cm_p.tif"
  ),
  dim_name = "depth",
  dim_values = c(0, 5, 15, 30, 60, 100, 150),
  dim_type = "VERTICAL",
  dim_unit = "cm",
  array_name = "claytotal",
  output = "solus_clay.vrt"
)
} # }
```
