# Build a first-n mdim recipe with `gdal mdim mosaic` (no temp file)

Writes to `/vsimem/` and reads the bytes back, so nothing hits disk.
Requires gdalraster with the `gdal_run` algorithm interface.

## Usage

``` r
mdim_mosaic_xml(files)
```
