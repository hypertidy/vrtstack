# sds-adapters.R
#
# The sds-bound half: source construction and enumeration for the OISST
# pair. Depends on vrtstack-core.R for mdim_sources()/mdim_signature()
# (source it first; in package form this is an Import on vrtstack).
# Deps: curl, jsonlite.
#
# Placement notes: URL construction (oisst_ncei_url) and known-grid
# signatures are sds territory (fetch-free descriptions, cf. stacit(),
# cdr_urls(), mursst_meta()). The enumerating/credentialed pieces
# (pc_search paging, pc_sign_token) sit here for now but belong with the
# scale layer (starc for STAC) if they grow beyond this.

# --- OISST via NCEI https template (no catalog) -----------------------------

# Layout: .../access/avhrr/YYYYMM/oisst-avhrr-v02r01.YYYYMMDD.nc
# Near-real-time days exist as ..._preliminary.nc until the final file
# lands (~2 weeks). We generate the final URL and fall back to
# preliminary on a failed HEAD. That prelim->final replacement is the
# same staleness question cmrlifecycle answers for CMR, restated for a
# provider with no catalog at all.

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

# Known-grid signature for the netCDF route (lat ascending in file, lon
# on the 0..360 domain). Values are the published grid; treat as a probe
# result and confirm once with gdalmdiminfo on a single file.
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

# --- OISST via Planetary Computer STAC (COG assets) -------------------------

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
# start_datetime/end_datetime carrying the temporal extent -- the
# noaa-cdr collections do exactly this. Every adapter owns the
# interval-to-instant decision (start used here; a visible choice for
# sub-daily collections like WHOI 3-hourly).
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

# --- the loop ---------------------------------------------------------------

if (FALSE) {
  source("vrtstack-core.R")
  dates <- seq(as.Date("2024-01-01"), as.Date("2024-01-31"), by = "1 day")

  ## route A: no catalog, template
  srcA <- sources_oisst_ncei(dates)
  sigA <- signature_oisst_ncei()
  emit_mdim_vrt(srcA, sigA, "oisst-ncei.vrt")
  verify_vrt("oisst-ncei.vrt")

  ## route B: Planetary Computer STAC, COG assets
  srcB <- sources_oisst_pc("2024-01-01/2024-01-31")
  ## sufficiency first
  items <- pc_search("noaa-cdr-sea-surface-temperature-optimum-interpolation",
                     "2024-01-01/2024-01-02")
  print(stac_sufficiency(items[[1]], asset = "sst"))
  ## derive sigB from proj:shape/proj:transform + raster:bands (all
  ## present on PC); expect Y orientation (COG north-up vs netCDF
  ## lat-ascending) and lon domain (0..360 vs -180..180) to differ from
  ## sigA -- recorded as signature orientation, never resampled.

  ## acceptance: read the same (time, y, x) slab through both VRTs
  ## (gdalraster / vapour), roll 720 columns in X, flip in Y, compare
  ## raw Int16 (raster:bands scale is 0.01 through float32, so scaled
  ## comparison would differ in the last bits).
}
