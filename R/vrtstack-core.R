# vrtstack-core.R
#
# The vrtstack-bound half of the catalog-to-mdim-VRT scoping work.
# Self-contained: base R + utils only, no HTTP, no JSON. Everything here
# consumes plain data structures and emits or inspects XML.
#
# Contents:
#   mdim_sources()     sources-table constructor (the interface contract)
#   mdim_signature()   per-collection grid signature constructor
#   stac_sufficiency() emitter-requirements checklist over a parsed item
#   emit_mdim_vrt()    (sources, signature) -> mdim VRT XML
#   verify_vrt()       gdalmdiminfo round-trip
#
# Merge notes for the real vrtstack refactor (vs .build_mdim_vrt_xml):
# adopt from the existing builder: Dimension type/direction/
# indexingVariable attributes, declared BlockSize, numeric CF time via
# time_origin/time_unit, pixel-centre coords from geotransform, dtype
# mapping, /vsicurl/ auto-prefix. Standardise rank-up on one of
# SourceTranspose "-1,0,1" / SourceView "[newaxis,...]" (both valid).

# --- schema -----------------------------------------------------------------

# One row per output time step. 'kind' selects the Source flavour:
#   "array" -> SourceArray (multidim source, e.g. netCDF variable path)
#   "band"  -> SourceBand  (classic 2D source, e.g. COG band index)
# 'source_ref' is the array path ("/sst") or the band number ("1").
# 'source_view' is a GetView expression that must bring the source to
# EXACTLY the rank of the destination array (verified in vrtmultidim.cpp:
# "Inconsistent number of dimensions" otherwise). Rank down with integer
# indexing (drop zlev: "[:,0,:,:]"), rank up with "[newaxis,...]" for 2D
# classic bands feeding a 3D cube. All slab attribute vectors, when
# present, are dest-rank; SourceSlab is optional (count defaults to full
# source extent), so DestSlab offset alone places each slice.
#' Construct a sources table for a multidimensional VRT
#'
#' One row per output step along the concat (time) axis. This is the interface
#' contract produced by adapters and consumed by [emit_mdim_vrt()].
#'
#' @param time Vector of per-step coordinate values (e.g. a `Date` vector).
#' @param dsn Source data source names (file paths or `/vsicurl/` URIs).
#' @param source_ref Array path (e.g. `"/sst"`) when `kind = "array"`, or band
#'   number (e.g. `"1"`) when `kind = "band"`.
#' @param kind Source flavour: `"array"` (`<SourceArray>`, a multidimensional
#'   source) or `"band"` (`<SourceBand>`, a classic 2D source).
#' @param step_in_file Zero-based step index within a multi-step file.
#' @param dest_index Zero-based destination position along the concat axis;
#'   defaults to the rank order of `time`.
#' @param source_view Optional GetView expression that brings each source to
#'   exactly the destination rank (e.g. `"[newaxis,...]"` to rank a 2D band up
#'   to a 3D cube, `"[:,0,:,:]"` to drop a singleton dimension). `NA` for none.
#' @return A data frame ordered by `dest_index`, one row per output step.
#' @seealso [mdim_signature()], [emit_mdim_vrt()]
#' @export
mdim_sources <- function(time, dsn, source_ref, kind,
                         step_in_file = 0L, dest_index = NULL,
                         source_view = NA_character_) {
  stopifnot(all(kind %in% c("array", "band")))
  if (is.null(dest_index)) dest_index <- order(order(time)) - 1L
  d <- data.frame(time = time, dsn = dsn, source_ref = source_ref,
                  kind = kind, step_in_file = step_in_file,
                  dest_index = dest_index, source_view = source_view,
                  stringsAsFactors = FALSE)
  d[order(d$dest_index), ]
}

# One row per collection, cached to parquet in anger; plain list here.
# chunk_nx/chunk_ny recorded even with harvesting parked -- cheap to keep,
# annoying to re-probe. 'provenance' records where each grid fact came
# from (catalog vs probe vs published grid).
#' Construct a grid signature for a multidimensional VRT
#'
#' One row (as a list) per collection: the grid geometry and array metadata the
#' emitter needs, derived from catalog metadata or a single cached probe. The
#' emitter trusts these values, so a collection with non-aligned assets is a
#' signature-gate refusal, never a resample.
#'
#' @param collection,variable Identifiers for the collection and data array.
#' @param nx,ny Grid dimensions in X and Y.
#' @param x0,dx,y0,dy Grid origin and spacing as pixel-centre coordinates in the
#'   array's own orientation (`dy` is typically negative for north-up grids).
#' @param srs Spatial reference (e.g. `"EPSG:4326"` or a WKT string).
#' @param dtype VRT data type of the array (e.g. `"Int16"`, `"Float32"`).
#' @param nodata,scale,offset,unit Optional array metadata; `NA` to omit.
#' @param steps_per_file Number of concat-axis steps stored in each source file.
#' @param chunk_nx,chunk_ny Optional source chunk (block) shape, recorded for
#'   later byte-range harvesting.
#' @param provenance Free text recording where the grid facts came from
#'   (catalog, probe, or a published grid).
#' @return A named list describing one collection's grid and array metadata.
#' @seealso [mdim_sources()], [emit_mdim_vrt()]
#' @export
mdim_signature <- function(collection, variable, nx, ny,
                           x0, dx, y0, dy, srs,
                           dtype, nodata = NA, scale = NA, offset = NA,
                           unit = NA_character_, steps_per_file = 1L,
                           chunk_nx = NA_integer_, chunk_ny = NA_integer_,
                           provenance = "probe") {
  list(collection = collection, variable = variable, nx = nx, ny = ny,
       x0 = x0, dx = dx, y0 = y0, dy = dy, srs = srs, dtype = dtype,
       nodata = nodata, scale = scale, offset = offset, unit = unit,
       steps_per_file = steps_per_file,
       chunk_nx = chunk_nx, chunk_ny = chunk_ny, provenance = provenance)
}

# --- sufficiency ------------------------------------------------------------

# The emitter's requirements expressed as a checklist over one parsed STAC
# item (a list, as from jsonlite::fromJSON(..., simplifyVector = FALSE)).
# No HTTP here: fetching items is the adapters' job. found_at is one of
# item-properties, asset, absent (-> probe needed). Notes:
#   - proj:epsg vs proj:code is a proj-extension version marker, not a
#     gap; either satisfies the CRS requirement.
#   - datetime may be null for interval items, with start_datetime /
#     end_datetime carrying the extent (noaa-cdr collections do this).
#' Report mdim-VRT metadata sufficiency of a STAC item
#'
#' The emitter's requirements expressed as a checklist over one already-parsed
#' STAC item (as from `jsonlite::fromJSON(..., simplifyVector = FALSE)`). No
#' HTTP is performed here; fetching items is an adapter's job.
#'
#' @param item A parsed STAC item (a list).
#' @param asset Optional asset key; when supplied, asset-level fields take
#'   precedence over item-level properties.
#' @return A data frame with one row per checked field: `field`, `found_at`
#'   (one of `"item-properties"`, `"asset"`, `"absent"`), and a short
#'   `value_preview`.
#' @details `proj:epsg` versus `proj:code` is a proj-extension version marker,
#'   not a gap: either satisfies the CRS requirement. `datetime` may be null for
#'   interval items, with `start_datetime`/`end_datetime` carrying the extent.
#' @export
stac_sufficiency <- function(item, asset = NULL) {
  want <- c("proj:epsg", "proj:code", "proj:shape", "proj:transform",
            "datetime", "start_datetime", "end_datetime", "raster:bands")
  a <- if (!is.null(asset)) item$assets[[asset]] else NULL
  look <- function(field) {
    if (!is.null(a) && !is.null(a[[field]]))
      return(list(where = "asset", value = a[[field]]))
    if (!is.null(item$properties[[field]]))
      return(list(where = "item-properties", value = item$properties[[field]]))
    list(where = "absent", value = NULL)
  }
  rows <- lapply(want, function(f) {
    r <- look(f)
    data.frame(field = f, found_at = r$where,
               value_preview = paste(utils::head(unlist(r$value), 6),
                                     collapse = ","),
               stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}

# --- emitter ----------------------------------------------------------------

# Emits one variable, dims (time, Y, X). Y/X are RegularlySpacedValues
# from the signature; time is inline string values from the sources table
# (numeric CF time is a merge item, see header). Verified against
# frmts/vrt/vrtmultidim.cpp:
#   - source rank after SourceTranspose/SourceView must equal dest rank
#   - all slab attribute vectors are dest-rank
#   - SourceSlab is optional (count 0 -> full source extent), so each
#     slice needs only its view and a DestSlab offset
# gdalmdimtranslate -of VRT remains the oracle for anything not covered.

#' @noRd
xml_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

#' Emit a multidimensional VRT from a sources table and a signature
#'
#' Writes a GDAL multidimensional VRT for one variable with dimensions
#' `(time, Y, X)`. `Y`/`X` are `<RegularlySpacedValues>` from the signature; the
#' concat coordinate is written as inline string values from the sources table.
#' One `<Source>` is emitted per file: a multi-step file contributes a single
#' source whose full extent lands at the `DestSlab` offset of its first step.
#'
#' @param sources A sources table from [mdim_sources()].
#' @param sig A signature from [mdim_signature()].
#' @param path Output VRT path.
#' @return `path`, invisibly.
#' @seealso [verify_vrt()]
#' @export
emit_mdim_vrt <- function(sources, sig, path) {
  n <- nrow(sources)
  ## time coordinate: one Value per output step (per row).
  ## Source elements: one per file -- a multi-step file (steps_per_file
  ## > 1, e.g. WHOI 8-per-file) contributes a single Source whose full
  ## source extent lands at the DestSlab offset of its first step.
  ## Assumes each file's steps are contiguous in dest_index and start at
  ## step_in_file 0; add an explicit SourceSlab if that is ever violated.
  first_of_file <- !duplicated(sources$dsn)
  src_xml <- vapply(which(first_of_file), function(i) {
    s <- sources[i, ]
    ref <- if (s$kind == "array") {
      sprintf("      <SourceArray>%s</SourceArray>", xml_escape(s$source_ref))
    } else {
      sprintf("      <SourceBand>%s</SourceBand>", xml_escape(s$source_ref))
    }
    view <- if (!is.na(s$source_view)) {
      sprintf("\n      <SourceView>%s</SourceView>", xml_escape(s$source_view))
    } else ""
    paste0(
      "    <Source>\n",
      sprintf("      <SourceFilename>%s</SourceFilename>\n",
              xml_escape(s$dsn)),
      ref, view, "\n",
      sprintf("      <DestSlab offset=\"%d,0,0\"/>\n", s$dest_index),
      "    </Source>")
  }, "")
  time_vals <- paste(sprintf("        <Value>%s</Value>",
                             format(sources$time, "%Y-%m-%d")),
                     collapse = "\n")
  opt <- function(tag, val) {
    if (is.na(val)) "" else sprintf("    <%s>%s</%s>\n", tag, val, tag)
  }
  xml <- paste0(
    "<VRTDataset>\n",
    "  <Group name=\"/\">\n",
    sprintf("    <Dimension name=\"time\" size=\"%d\"/>\n", n),
    sprintf("    <Dimension name=\"Y\" size=\"%d\"/>\n", sig$ny),
    sprintf("    <Dimension name=\"X\" size=\"%d\"/>\n", sig$nx),
    "    <Array name=\"time\">\n",
    "      <DataType>String</DataType>\n",
    "      <DimensionRef ref=\"time\"/>\n",
    "      <InlineValuesWithValueElement>\n", time_vals, "\n",
    "      </InlineValuesWithValueElement>\n",
    "    </Array>\n",
    "    <Array name=\"Y\">\n",
    "      <DataType>Float64</DataType>\n",
    "      <DimensionRef ref=\"Y\"/>\n",
    sprintf("      <RegularlySpacedValues start=\"%.10g\" increment=\"%.10g\"/>\n",
            sig$y0, sig$dy),
    "    </Array>\n",
    "    <Array name=\"X\">\n",
    "      <DataType>Float64</DataType>\n",
    "      <DimensionRef ref=\"X\"/>\n",
    sprintf("      <RegularlySpacedValues start=\"%.10g\" increment=\"%.10g\"/>\n",
            sig$x0, sig$dx),
    "    </Array>\n",
    sprintf("    <Array name=\"%s\">\n", sig$variable),
    sprintf("      <DataType>%s</DataType>\n", sig$dtype),
    "      <DimensionRef ref=\"time\"/>\n",
    "      <DimensionRef ref=\"Y\"/>\n",
    "      <DimensionRef ref=\"X\"/>\n",
    # Array dims are (time, Y, X): Y is dim 2, X is dim 3. Unit, NoData,
    # Offset, Scale follow in XSD order.
    sprintf("      <SRS dataAxisToSRSAxisMapping=\"%s\">%s</SRS>\n",
            .srs_axis_mapping(sig$srs, y_dim = 2L, x_dim = 3L),
            xml_escape(sig$srs)),
    opt("Unit", sig$unit),
    opt("NoDataValue", sig$nodata),
    opt("Offset", sig$offset),
    opt("Scale", sig$scale),
    paste(src_xml, collapse = "\n"), "\n",
    "    </Array>\n",
    "  </Group>\n",
    "</VRTDataset>\n")
  writeLines(xml, path)
  invisible(path)
}

#' Verify a multidimensional VRT with `gdal mdim info`
#'
#' Opens `path` through gdalraster's `mdim info` algorithm as a round-trip check
#' that the emitted VRT parses and can be interpreted by GDAL.
#'
#' @param path Path to a VRT.
#' @return The `gdal mdim info` output as a character string, invisibly.
#' @export
verify_vrt <- function(path) {
  stopifnot(requireNamespace("gdalraster", quietly = TRUE))
  invisible(gdalraster::gdal_run("mdim info", c(path))$output())
}
