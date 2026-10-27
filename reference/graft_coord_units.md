# Inject `<Unit>` on coordinate arrays that lost it in `gdal mdim mosaic`

A coordinate array is any `<Array>` with no `<Source>`. Units are read
from one source via `gdal mdim info` (or supplied directly via `units`).
Arrays that already carry a `<Unit>` are left untouched, so this is
idempotent and a no-op once GDAL propagates the unit itself.

## Usage

``` r
graft_coord_units(x, source = NULL, units = NULL)
```

## Arguments

- x:

  Mosaic recipe: xml2 document or XML string.

- source:

  One source path to read units from (via `gdal mdim info`).

- units:

  Optional named character vector (array name -\> unit); bypasses
  `source` and needs no GDAL (handy for tests).

## Value

Enriched `x` as an `xml_document`.
