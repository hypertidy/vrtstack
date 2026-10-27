# Package index

## Stack 2D rasters along a new dimension

Build a new axis from a collection of 2D rasters (COGs, GeoTIFFs).

- [`gdal_mdim_stack()`](https://hypertidy.github.io/vrtstack/reference/gdal_mdim_stack.md)
  : Create a Multidimensional VRT from 2D Rasters
- [`vrt_time_stack()`](https://hypertidy.github.io/vrtstack/reference/vrt_time_stack.md)
  : Stack Time Series Rasters into Multidimensional VRT
- [`vrt_depth_stack()`](https://hypertidy.github.io/vrtstack/reference/vrt_depth_stack.md)
  : Stack Rasters by Depth/Level into Multidimensional VRT
- [`vrt_regular_stack()`](https://hypertidy.github.io/vrtstack/reference/vrt_regular_stack.md)
  : Stack Rasters with Regular Spacing

## Extend a multidimensional recipe

Flesh a small “first-n” mdim VRT out to a full file set, and repair
metadata that mosaic drops.

- [`vrtstack()`](https://hypertidy.github.io/vrtstack/reference/vrtstack.md)
  : Stack rasters into a multidimensional VRT (two paths, one entry
  point)

- [`mdim_template_extend()`](https://hypertidy.github.io/vrtstack/reference/mdim_template_extend.md)
  : Extend an mdim VRT recipe to a full file set

- [`resolve_concat()`](https://hypertidy.github.io/vrtstack/reference/resolve_concat.md)
  : Resolve concat-axis values (shared by both paths)

- [`graft_coord_units()`](https://hypertidy.github.io/vrtstack/reference/graft_coord_units.md)
  :

  Inject `<Unit>` on coordinate arrays that lost it in
  `gdal mdim mosaic`

- [`graft_group_attrs()`](https://hypertidy.github.io/vrtstack/reference/graft_group_attrs.md)
  : Inject invariant root-group provenance attributes dropped by mosaic

## Emit a VRT from a catalog signature

Build a VRT from a sources table and a grid signature, without opening a
file.

- [`mdim_sources()`](https://hypertidy.github.io/vrtstack/reference/mdim_sources.md)
  : Construct a sources table for a multidimensional VRT

- [`mdim_signature()`](https://hypertidy.github.io/vrtstack/reference/mdim_signature.md)
  : Construct a grid signature for a multidimensional VRT

- [`stac_sufficiency()`](https://hypertidy.github.io/vrtstack/reference/stac_sufficiency.md)
  : Report mdim-VRT metadata sufficiency of a STAC item

- [`emit_mdim_vrt()`](https://hypertidy.github.io/vrtstack/reference/emit_mdim_vrt.md)
  : Emit a multidimensional VRT from a sources table and a signature

- [`verify_vrt()`](https://hypertidy.github.io/vrtstack/reference/verify_vrt.md)
  :

  Verify a multidimensional VRT with `gdal mdim info`
