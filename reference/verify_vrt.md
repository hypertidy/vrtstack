# Verify a multidimensional VRT with `gdal mdim info`

Opens `path` through gdalraster's `mdim info` algorithm as a round-trip
check that the emitted VRT parses and can be interpreted by GDAL.

## Usage

``` r
verify_vrt(path)
```

## Arguments

- path:

  Path to a VRT.

## Value

The `gdal mdim info` output as a character string, invisibly.
