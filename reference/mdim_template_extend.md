# Extend an mdim VRT recipe to a full file set

Pure XML-tree rewrite (no GDAL needed). Sets the concat dimension size,
rewrites the concat coordinate array's values, and regenerates the
`<Source>` list of every *data* array (an `<Array>` that owns a
`<Source>`). Per-array `SourceArray` path and slab geometry are read
from the array's first source, never assumed from the array name.

## Usage

``` r
mdim_template_extend(xml, files, concat_values = NULL, concat_dim = "time")
```

## Arguments

- xml:

  Template VRT as an XML string (or anything
  [`xml2::read_xml()`](http://xml2.r-lib.org/reference/read_xml.md)
  takes).

- files:

  Full character vector of sources.

- concat_values:

  Values for the concat coordinate array, or `NULL` to keep the
  template's values (only valid when length matches `files`).

- concat_dim:

  Concat dimension name (default `"time"`); if not found, the dimension
  whose `size` equals the template's per-array source count is used.

## Value

An `xml_document` (serialise with
[`as.character()`](https://rdrr.io/r/base/character.html) /
[`xml2::write_xml()`](http://xml2.r-lib.org/reference/write_xml.md)).
