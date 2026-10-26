# mdimvrt-scoping.R
#
# Scoping: can we derive a valid, rich multidimensional VRT entirely from a
# catalog query (STAC or CMR), with at most one cached probe per collection?
#
# This file is deliberately not-a-package: it is the sources-table schema,
# two adapters for the OISST pair (targets #1 and #2), a STAC sufficiency
# report, and a minimal mdim VRT emitter -- enough to close the
# self-validating loop (same files via COG/SourceBand and via
# netCDF/SourceArray must agree numerically).
#
# Explicitly out of scope: any warping, any target grid. The generator's
# contract is "identical grid or refuse". Non-aligned assets are a
# signature-gate refusal, not a warp.
#
# Deps: curl, jsonlite. Verification shells out to gdalmdiminfo.

# ---------------------------------------------------------------------------
# 1. schema
# ---------------------------------------------------------------------------

# One row per (output time step). 'kind' selects the Source flavour:
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
# chunk_nx/chunk_ny recorded now even with harvesting parked -- cheap to
# keep, annoying to re-probe.
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

# ---------------------------------------------------------------------------
# 2. adapter: OISST via NCEI https template (no catalog)
# ---------------------------------------------------------------------------

# Layout: .../access/avhrr/YYYYMM/oisst-avhrr-v02r01.YYYYMMDD.nc
# Near-real-time days exist as ..._preliminary.nc until the final file
# lands (~2 weeks). We generate the final URL and fall back to preliminary
# on a failed HEAD. That prelim->final replacement is the same staleness
# question cmrlifecycle answers for CMR, restated for a provider with no
# catalog at all -- worth keeping in view.

oisst_ncei_url <- function(date, preliminary = FALSE) {
  base <- "https://www.ncei.noaa.gov/data/sea-surface-temperature-optimum-interpolation/v2.1/access/avhrr"
  ym <- format(date, "%Y%m")
  ymd <- format(date, "%Y%m%d")
  suffix <- if (preliminary) "_preliminary.nc" else ".nc"
  sprintf("%s/%s/oisst-avhrr-v02r01.%s%s", base, ym, ymd, suffix)
}

head_ok <- function(url) {
  h <- curl::new_handle(nobody = TRUE, followlocation = TRUE)
  res <- tryCatch(curl::curl_fetch_memory(url, handle = h),
                  error = function(e) NULL)
  !is.null(res) && res$status_code < 400
}

sources_oisst_ncei <- function(dates, variable = "sst",
                               check_preliminary = TRUE) {
  urls <- vapply(dates, oisst_ncei_url, "", preliminary = FALSE)
  if (check_preliminary) {
    ## only recent dates can be preliminary; don't HEAD the whole record
    recent <- dates > (Sys.Date() - 30)
    for (i in which(recent)) {
      if (!head_ok(urls[i])) {
        urls[i] <- oisst_ncei_url(dates[i], preliminary = TRUE)
      }
    }
  }
  mdim_sources(time = dates,
               dsn = paste0("/vsicurl/", urls),
               source_ref = paste0("/", variable),
               kind = "array",
               ## OISST netCDF variable dims: (time=1, zlev=1, lat, lon).
               ## Keep time (dest is 3D), drop zlev only -> (1, lat, lon).
               source_view = "[:,0,:,:]")
}

# Known-grid signature for the netCDF route (lat ascending in file,
# lon on the 0..360 domain). Values are the published grid; treat as a
# probe result and confirm once with gdalmdiminfo on a single file.
signature_oisst_ncei <- function(variable = "sst") {
  mdim_signature(
    collection = "oisst-avhrr-v02r01-ncei", variable = variable,
    nx = 1440L, ny = 720L,
    x0 = 0.125, dx = 0.25,
    y0 = -89.875, dy = 0.25,           # ascending latitude, as stored
    srs = "EPSG:4326",
    dtype = "Int16", nodata = -999, scale = 0.01, offset = 0,
    unit = "Celsius", steps_per_file = 1L,
    provenance = "published-grid; confirm by probe")
}

# ---------------------------------------------------------------------------
# 3. adapter: OISST via Planetary Computer STAC (COG assets)
# ---------------------------------------------------------------------------

pc_search <- function(collection, datetime, limit = 100) {
  url <- "https://planetarycomputer.microsoft.com/api/stac/v1/search"
  body <- list(collections = list(collection), datetime = datetime,
               limit = limit)
  items <- list()
  repeat {
    h <- curl::new_handle()
    curl::handle_setheaders(h, "Content-Type" = "application/json")
    curl::handle_setopt(h, postfields = jsonlite::toJSON(body, auto_unbox = TRUE))
    res <- curl::curl_fetch_memory(url, handle = h)
    stopifnot(res$status_code < 400)
    page <- jsonlite::fromJSON(rawToChar(res$content), simplifyVector = FALSE)
    items <- c(items, page$features)
    nxt <- Filter(function(l) identical(l$rel, "next"), page$links)
    if (length(nxt) == 0) break
    body <- nxt[[1]]$body
    url <- nxt[[1]]$href
  }
  items
}

pc_sign_token <- function(collection) {
  url <- sprintf("https://planetarycomputer.microsoft.com/api/sas/v1/token/%s",
                 collection)
  res <- curl::curl_fetch_memory(url)
  stopifnot(res$status_code < 400)
  jsonlite::fromJSON(rawToChar(res$content))$token
}

# STAC allows datetime: null for interval-based items, with
# start_datetime/end_datetime carrying the temporal extent -- the noaa-cdr
# collections do exactly this. That is a sufficiency fact (recorded in
# stac_sufficiency below), and the adapter must handle both forms.
stac_item_time <- function(item) {
  p <- item$properties
  v <- p$datetime
  if (is.null(v)) v <- p$start_datetime
  if (is.null(v)) NA_character_ else v
}

sources_oisst_pc <- function(datetime, variable = "sst") {
  collection <- "noaa-cdr-sea-surface-temperature-optimum-interpolation"
  items <- pc_search(collection, datetime)
  items <- Filter(function(x) !is.null(x$assets[[variable]]), items)
  token <- pc_sign_token(collection)
  time <- as.Date(vapply(items, stac_item_time, ""))
  href <- vapply(items, function(x) x$assets[[variable]]$href, "")
  mdim_sources(time = time,
               dsn = paste0("/vsicurl/", href, "?", token),
               source_ref = "1",
               kind = "band",
               ## 2D classic band -> 3D dest: rank up with newaxis
               source_view = "[newaxis,...]")
}

# ---------------------------------------------------------------------------
# 4. STAC sufficiency report -- the actual "investigation"
# ---------------------------------------------------------------------------

# For one item: which mdim-VRT-relevant fields are present, and where.
# found_at is one of: item-properties, asset, absent (-> probe needed).
# Run this on Planetary Computer items (expect near-complete) and on the
# same-collection cmr-stac items (target #4; expect gaps) -- the diff is
# the "what would make cmr-stac STACIT/mdim-viable" report.
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

# ---------------------------------------------------------------------------
# 5. minimal mdim VRT emitter
# ---------------------------------------------------------------------------

# Emits one variable, dims (time, Y, X). Y/X are RegularlySpacedValues from
# the signature; time is inline string values from the sources table.
# Verified against frmts/vrt/vrtmultidim.cpp:
#   - source rank after SourceTranspose/SourceView must equal dest rank
#   - all slab attribute vectors are dest-rank
#   - SourceSlab is optional (count 0 -> full source extent), so each
#     slice needs only its view and a DestSlab offset
# gdalmdimtranslate -of VRT remains the oracle for anything not covered.

xml_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  gsub(">", "&gt;", x, fixed = TRUE)
}

emit_mdim_vrt <- function(sources, sig, path) {
  n <- nrow(sources)
  ## time coordinate: one Value per output step (per row).
  ## Source elements: one per file -- a multi-step file (steps_per_file > 1,
  ## e.g. WHOI 8-per-file) contributes a single Source whose full source
  ## extent lands at the DestSlab offset of its first step. Assumes each
  ## file's steps are contiguous in dest_index and start at step_in_file 0.
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
    sprintf("      <SRS>%s</SRS>\n", xml_escape(sig$srs)),
    opt("NoDataValue", sig$nodata),
    opt("Scale", sig$scale),
    opt("Offset", sig$offset),
    opt("Unit", sig$unit),
    paste(src_xml, collapse = "\n"), "\n",
    "    </Array>\n",
    "  </Group>\n",
    "</VRTDataset>\n")
  writeLines(xml, path)
  invisible(path)
}

verify_vrt <- function(path) {
  system(paste("gdalmdiminfo", shQuote(path)))
}

# ---------------------------------------------------------------------------
# 6. the loop
# ---------------------------------------------------------------------------

dates <- seq(as.Date("2024-01-01"), as.Date("2024-01-31"), by = "1 day")

  ## route A: no catalog, template
  srcA <- sources_oisst_ncei(dates)
  sigA <- signature_oisst_ncei()
  emit_mdim_vrt(srcA, sigA, "oisst-ncei.vrt")
  verify_vrt("oisst-ncei.vrt")

  ## route B: Planetary Computer STAC, COG assets
  srcB <- sources_oisst_pc("2024-01-01/2024-01-31")
  ## sufficiency first -- this is the point of the exercise
  items <- pc_search("noaa-cdr-sea-surface-temperature-optimum-interpolation",
                     "2024-01-01/2024-01-02")
  print(stac_sufficiency(items[[1]], asset = "sst"))
  ## derive sigB from proj:shape/proj:transform + raster:bands where present;
  ## expect Y orientation (COG north-up vs netCDF lat-ascending) and possibly
  ## the lon domain (0..360 vs -180..180) to differ from sigA -- the
  ## cross-check exists to surface exactly this.

  ## acceptance: read the same (time, y, x) slab through both VRTs
  ## (gdalraster / vapour) and compare, flipping/rolling per the recorded
  ## orientations. Scale/offset applied consistently or compared raw.
