# Which array dimension carries each SRS axis.
#
# GDAL's `dataAxisToSRSAxisMapping` lists, for SRS axis i (in the order the
# CRS's WKT declares its axes), the 1-based index of the array dimension
# holding it. Indices run over every array dimension, the stack/time axis
# included. So for a (time, y, x) array:
#
#   * EPSG:4326 as GDAL writes it (AXIS latitude NORTH, longitude EAST):
#     latitude lives on dim 2 (y), longitude on dim 3 (x)  ->  "2,3"
#   * a projected or lon-first CRS (easting first)            ->  "3,2"
#
# A WKT with no AXIS is treated as easting-first, as GDAL does for WKT1.
# Leaving the attribute off is not safe: GDAL then assumes "1,2", which maps
# an SRS axis onto the time dimension, and a 2D slice of the array gets an
# invalid mapping.
.srs_axis_mapping <- function(wkt, y_dim, x_dim) {
  order <- .srs_axis_order(wkt)
  if (is.null(order)) order <- c("X", "Y")
  idx <- c(X = x_dim, Y = y_dim)
  paste(idx[order], collapse = ",")
}

# Horizontal axis order of a CRS from its WKT, e.g. c("Y", "X"); NULL when it
# cannot be read plainly (no AXIS, compound CRS, non-horizontal axes). Uses the
# last two AXIS entries: a WKT1 PROJCS may list its GEOGCS axes first, and in
# WKT1 and WKT2 the CRS's own axes come last.
.srs_axis_order <- function(wkt) {
  if (is.null(wkt) || is.na(wkt) || !nzchar(wkt)) return(NULL)
  if (grepl("COMPOUNDCRS|COMPD_CS", wkt, ignore.case = TRUE)) return(NULL)
  m <- regmatches(wkt, gregexpr('AXIS\\[\\s*"[^"]*"\\s*,\\s*[A-Za-z]+', wkt))[[1]]
  if (length(m) < 2) return(NULL)
  dirs <- tolower(sub('.*,\\s*', "", utils::tail(m, 2)))
  out <- ifelse(dirs %in% c("north", "south"), "Y",
                ifelse(dirs %in% c("east", "west"), "X", NA))
  if (anyNA(out) || !setequal(out, c("X", "Y"))) return(NULL)
  out
}
