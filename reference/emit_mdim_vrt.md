# Emit a multidimensional VRT from a sources table and a signature

Writes a GDAL multidimensional VRT for one variable with dimensions
`(time, Y, X)`. `Y`/`X` are `<RegularlySpacedValues>` from the
signature; the concat coordinate is written as inline string values from
the sources table. One `<Source>` is emitted per file: a multi-step file
contributes a single source whose full extent lands at the `DestSlab`
offset of its first step.

## Usage

``` r
emit_mdim_vrt(sources, sig, path)
```

## Arguments

- sources:

  A sources table from
  [`mdim_sources()`](https://hypertidy.github.io/vrtstack/reference/mdim_sources.md).

- sig:

  A signature from
  [`mdim_signature()`](https://hypertidy.github.io/vrtstack/reference/mdim_signature.md).

- path:

  Output VRT path.

## Value

`path`, invisibly.

## See also

[`verify_vrt()`](https://hypertidy.github.io/vrtstack/reference/verify_vrt.md)
