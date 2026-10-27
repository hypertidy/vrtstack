# Report mdim-VRT metadata sufficiency of a STAC item

The emitter's requirements expressed as a checklist over one
already-parsed STAC item (as from
`jsonlite::fromJSON(..., simplifyVector = FALSE)`). No HTTP is performed
here; fetching items is an adapter's job.

## Usage

``` r
stac_sufficiency(item, asset = NULL)
```

## Arguments

- item:

  A parsed STAC item (a list).

- asset:

  Optional asset key; when supplied, asset-level fields take precedence
  over item-level properties.

## Value

A data frame with one row per checked field: `field`, `found_at` (one of
`"item-properties"`, `"asset"`, `"absent"`), and a short
`value_preview`.

## Details

`proj:epsg` versus `proj:code` is a proj-extension version marker, not a
gap: either satisfies the CRS requirement. `datetime` may be null for
interval items, with `start_datetime`/`end_datetime` carrying the
extent.
