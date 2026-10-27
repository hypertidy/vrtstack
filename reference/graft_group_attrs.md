# Inject invariant root-group provenance attributes dropped by mosaic

Inject invariant root-group provenance attributes dropped by mosaic

## Usage

``` r
graft_group_attrs(
  x,
  source = NULL,
  attrs = NULL,
  skip = c("Conventions", .MDIM_PER_FILE_GLOBALS)
)
```

## Arguments

- x:

  Mosaic recipe: xml2 document or XML string.

- source:

  One source path to read globals from (via `gdal mdim info`).

- attrs:

  Optional named character vector (name -\> value); bypasses `source`
  (handy for tests). All treated as String attributes.

- skip:

  Attribute names to exclude (default: `Conventions` + per-file).

## Value

Enriched `x` as an `xml_document`.
