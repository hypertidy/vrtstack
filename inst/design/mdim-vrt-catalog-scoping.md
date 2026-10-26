# Catalog-driven multidimensional VRT: scoping notes

2026-08-26. Context: hypertidy ecosystem. Touches vrtstack, sds, starc,
cmrlifecycle, with gdalxarray and blocklist as downstream consumers.

## Goal

Derive a valid and rich GDAL multidimensional VRT entirely from a catalog
query (STAC, CMR, or a URL template), with at most one cached probe per
collection. "odc-stac without rasterio": the output is a document, not a
live object; GDAL mdim does all IO; any GDAL binding can open it.

The generator's contract is "identical grid or refuse". No warping, no
target grid. Non-aligned assets are a signature-gate refusal. Note for
later: same-grid-different-extent placement (mosaic on a shared grid) is
expressible in pure slab arithmetic with no warp, so the refusal gate is
"not on the same grid", not "not the same extent".

## Core data structures

Two things, both plain R structures, forming the interface contract
between packages:

The **sources table**: one row per output time step. Columns: time, dsn,
source_ref (array path "/sst" or band number "1"), kind ("array" |
"band"), step_in_file, dest_index, source_view. Produced by adapters
(sds for construction, starc/cmrlifecycle for enumeration at scale);
consumed by the emitter (vrtstack).

The **signature**: one row per collection. Grid (nx, ny, x0, dx, y0, dy),
srs, dtype, nodata, scale, offset, unit, steps_per_file, chunk shape,
provenance. Derived from catalog metadata when sufficient, otherwise from
one probe, then cached. Candidate format: cache the gdalmdiminfo JSON
verbatim as the probe artifact and derive named fields on demand
(precedent: sds::mursst_meta() already embeds exactly this shape).
chunk_nx/chunk_ny are recorded now even though byte-reference harvesting
is parked -- cheap to keep, annoying to re-probe.

## Verified mdim VRT semantics

Read from frmts/vrt/vrtmultidim.cpp (GDAL master), then confirmed by
round-trip against gdalmdiminfo:

1. Source rank after SourceTranspose/SourceView must equal destination
   rank exactly ("Inconsistent number of dimensions" at open otherwise).
   Rank down with integer indexing in a view (drop zlev: "[:,0,:,:]");
   rank up with "[newaxis,...]" for 2D classic bands feeding a 3D cube.
   vrtstack independently solved rank-up as SourceTranspose "-1,0,1"
   (Transpose's newaxis form); both are valid, standardise on one.
2. All slab attribute vectors (SourceSlab offset/count/step, DestSlab
   offset) are destination-rank when present ("Wrong number of values"
   at parse otherwise).
3. SourceSlab is optional: count 0 defaults to full source extent from
   offset 0. The minimal Source is filename + ref + view + DestSlab.
4. Aside, not yet used: SourceView accepts a "resample=true," prefix
   routed through GetResampled. Filed next to the warp scope-out.

Multi-step files (e.g. WHOI SST CDR, 8 steps per netCDF): one Source
element per file, one time Value per step. A file's full source extent
lands at the DestSlab offset of its first step. Current assumption: each
file's steps are contiguous in dest_index and start at step 0; add an
explicit SourceSlab if a collection ever violates this.

All three shapes verified with gdalmdiminfo reading correct values:
slice-per-file via SourceBand + newaxis; 3D SourceArray with no view and
no slab; multi-step file as a single Source.

## OISST pair results

Route A (no catalog; NCEI https template, netCDF SourceArray): 31-day
VRT valid and rich -- WKT2 CRS with data_axis_to_srs_axis_mapping,
unit, nodata, scale/offset all carried. Preliminary/final file
replacement (~2 weeks) handled by HEAD fallback; this is the
cmrlifecycle staleness question restated for a provider with no catalog.

Route B (Planetary Computer STAC, COG SourceBand): zero-probe
sufficiency confirmed. Report for one item, asset "sst":

| field          | found_at        | value                    |
|----------------|-----------------|--------------------------|
| proj:epsg      | item-properties | 4326                     |
| proj:code      | absent          | (older proj-ext vintage) |
| proj:shape     | item-properties | 720,1440                 |
| proj:transform | item-properties | 0.25,0,-180,0,-0.25,90   |
| datetime       | absent          | (interval item)          |
| start_datetime | item-properties | 2024-01-02T00:00:00Z     |
| end_datetime   | item-properties | 2024-01-02T23:59:59Z     |
| raster:bands   | asset           | Celsius, ~0.01, -999, int16 |

Findings folded into the design:

- Interval items: STAC allows datetime null with
  start_datetime/end_datetime. Every adapter owns the interval-to-instant
  decision (start used here; visible choice for sub-daily collections).
- proj:epsg vs proj:code is a proj-extension version marker, not a gap;
  the sufficiency report tracks both and either satisfies CRS.
- raster:bands scale is 0.01 round-tripped through float32
  (0.00999999977648258). Pixel cross-checks compare raw Int16, and the
  signature records scale provenance (catalog vs file attribute).
- Known divergences between routes, recorded as signature orientation,
  never resampled: COGs are -180..180 and north-up; netCDF is 0..360 and
  lat-ascending. Reconciliation for the cross-check is a 720-column roll
  in X plus a flip in Y.

## Package placement

Three layers, all existing packages, joined by the plain-data-frame
contract (no dependency edges):

- **sds**: naming, query construction, URL templates, signatures. Where a
  source is and what its grid looks like. Already partway there:
  stacit() (query builder with antimeridian splitting), mpc(),
  cdr_urls() (the sea ice template), mursst_meta() (a proto-signature).
  Style: construction stays fetch-free; cheap HEAD-style checks at most.
- **starc / cmrlifecycle**: enumeration at scale and lifecycle state --
  paged searches, credentialed endpoints, parquet stores, audit tables.
  Anything paged or credentialed lives here, not in sds.
- **vrtstack**: the schema definitions (sources table, signature), the
  emitter, the sufficiency report (it is the emitter's requirements
  expressed as a checklist, taking already-parsed items, HTTP-free).
  Imports stay gdalraster-only.

vrtstack merge notes (from comparing with .build_mdim_vrt_xml): adopt
from the existing builder its Dimension type/direction/indexingVariable
attributes, declared BlockSize (prerequisite for later GetRawBlockInfo
harvesting), numeric CF time via time_origin/time_unit (drop String
time), pixel-centre coordinate derivation, dtype mapping, and /vsicurl/
auto-prefixing. Adopt from the scoping code: SourceArray sources, rank
views, multi-step grouping, mixed kinds, per-array Scale/Offset/Unit.
The gdal mdim mosaic lineage (vrtstack(), mdim_template_extend) becomes
a differential-test oracle rather than a production path; the enrich
grafts become unnecessary once the signature declares units up front
(and the unit-dropping they patch is a small upstream GDAL fix).

## Parked, deliberately

- Warping / target grids: out of scope; identical grid or refuse.
- Byte-reference harvesting: the endpoint stays reachable from this side.
  GetRawBlockInfo works on VRT when the Array declares a BlockSize and
  each VRT block maps 1:1 to one source block, so a chunk-aligned
  generated VRT is itself harvestable (catalog -> VRT -> blocklist ->
  kerchunk parquet). Chunk shape is therefore a mandatory signature
  column. GTiff lacks GetRawBlockInfo; implementing it is close to
  transcribing TileOffsets/TileByteCounts and would give COG mirrors
  harvest parity -- small, self-contained, future.
- CMR-as-meta-driver: the empirical route runs through this work; the
  cmr-stac sufficiency diff (target #4) is the evidence base.

## Next

1. Pixel cross-check, route A vs route B, raw Int16, roll+flip.
2. cmr-stac gap report for MUR (same sufficiency function, diff vs PC).
3. MUR audit table (cmrlifecycle) feeding the same assembler; per-era
   VRT splitting (Scale/Offset/NoDataValue are array-level, not
   per-source -- era heterogeneity means per-era VRTs, the one place the
   per-chunk-codec model of kerchunk/icechunk is strictly richer).
4. Sea ice CDR via cmr_find_collections or NSIDC template (projected CRS
   test: polar stereo, axis mapping, north and south as separate arrays).
5. LAADS swath negative control: the signature gate must refuse with a
   reason, not emit a plausible lie.
