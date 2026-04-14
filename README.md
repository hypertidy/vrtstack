# vrtstack

<!-- badges: start -->
<!-- badges: end -->

Stack 2D rasters along a new dimension, producing GDAL Multidimensional VRT files.

See a real example in "./example.R" where we generate MDIM VRT in a one line call, it parses the date from the file URIs. (Write that to textxml.vrt 
for later reuse). 


## The Problem

You have a directory of COGs or GeoTIFFs representing slices along some dimension:

```
claytotal_0_cm.tif    # depth = 0 cm
claytotal_5_cm.tif    # depth = 5 cm
claytotal_15_cm.tif   # depth = 15 cm
...
```

Or a time series:

```
temperature_20230101.tif
temperature_20230102.tif
temperature_20230103.tif
...
```

You want to treat these as a **single multidimensional array** — selectable by depth or time — without copying data into a new format.

## The Solution

GDAL's [Multidimensional VRT driver](https://gdal.org/drivers/raster/vrt_multidimensional.html) can virtually assemble 2D rasters into a multidimensional structure. But creating the VRT XML by hand is tedious.

**vrtstack** generates these VRTs programmatically:
```r
library(vrtstack)

gdal_mdim_stack(
  files = list.files(pattern = "claytotal_.*\\.tif$"),
  dim_name = "depth",
  dim_values = c(0, 5, 15, 30, 60, 100, 150),
  dim_type = "VERTICAL",
  dim_direction = "DOWN",
  dim_unit = "cm",
  output = "claytotal.vrt"
)
```

The resulting VRT can be read by:
- GDAL's multidim API (`gdalmdiminfo`, `gdalmdimtranslate`)
- Python xarray via [gdx](https://github.com/mdsumner/gdx) or [xgdal](https://github.com/scottyhq/xgdal)
- Any tool supporting GDAL multidimensional rasters

## Key Features

### Regular Axes

When values are evenly spaced, the VRT uses compact `<RegularlySpacedValues>`:

```r
# Just specify start + increment, not every value
gdal_mdim_stack(
  files = monthly_files,
  dim_name = "month",
  dim_start = 1,
  dim_increment = 1,
  output = "monthly.vrt"
)
```

Even with explicit values, regular spacing is auto-detected:
```r
gdal_mdim_stack(
  files = files,
  dim_name = "depth",
  dim_values = c(0, 5, 10, 15, 20),  # Regular! 
  output = "depth.vrt"
)
#> Detected regular spacing: start=0, increment=5
```

The VRT stores `<RegularlySpacedValues start="0" increment="5"/>` instead of `<InlineValues>0 5 10 15 20</InlineValues>`.

### Extract Dates from Filenames

```r
gdal_mdim_stack(
  files = list.files(pattern = "temp_\\d{8}\\.tif$"),
  dim_name = "time",
  dim_values = "(\\d{8})",          # Regex with capture group
  parse_format = "%Y%m%d",           # strptime format
  dim_type = "TEMPORAL",
  time_origin = "1970-01-01",
  time_unit = "days",
  output = "timeseries.vrt"
)
```

### Cloud-Native Sources

HTTP/HTTPS URLs are automatically wrapped in `/vsicurl/`:

```r
gdal_mdim_stack(
  files = paste0(
    "https://storage.googleapis.com/solus100pub/claytotal_",
    c(0, 5, 15), "_cm_p.tif"
  ),
  dim_name = "depth",
  dim_values = c(0, 5, 15),
  output = "cloud_soil.vrt"
)
```

### Convenience Wrappers

```r
# Time series
vrt_time_stack(files, output = "timeseries.vrt")

# Depth/level profiles
vrt_depth_stack(files, values = c(0, 30, 100), unit = "cm", output = "soil.vrt")

# Regular spacing
vrt_regular_stack(files, dim_name = "band", start = 1, increment = 1, output = "bands.vrt")
```

## Installation

```r
# install.packages("pak")
pak::pak("hypertidy/vrtstack")
```

Requires **gdalraster** (or **vapour** as fallback) for reading raster metadata.

## Relation to Other Tools

### gdal mdim mosaic

`gdal mdim mosaic` spatially mosaics existing multidimensional arrays. **vrtstack** does something different: it *stacks* 2D rasters along a *new* dimension. Think of it as the missing `gdal mdim stack`.

### VirtualiZarr / kerchunk

Similar concept — creating virtual references to chunked data — but for Zarr ecosystems. **vrtstack** creates GDAL VRTs, which integrate with the broader GDAL toolchain and any GDAL-based reader.

### xgdal

[scottyhq/xgdal](https://github.com/scottyhq/xgdal) is a Python xarray backend using GDAL's multidim API. It can *read* these VRTs and also generate them from existing xarray Datasets. **vrtstack** generates VRTs from R, directly from file lists.

### hypertidy ecosystem

Part of the [hypertidy](https://github.com/hypertidy) philosophy: thin, composable tools that work directly with GDAL. See also:
- **vapour** / **gdalraster** — GDAL bindings for R
- **grout** — grid tiling specs
- **vaster** — grid geometry primitives
- **gdx** — xarray backend for GDAL multidim (Python)

## License
MIT
