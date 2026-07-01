## Restore coordinate-array *units* dropped by `gdal mdim mosaic`.
##
## Supersedes the earlier attribute-graft: the lost metadata is the array Unit
## (GetUnit()/`<Unit>`), NOT an `<Attribute name="units">`. The netCDF driver
## lifts CF `units` (e.g. "days since ...") into the array Unit, and mosaic's
## indexing-variable recreation copies attributes but never replays the Unit.
## (mosaic keeps units on *data* arrays, which are sourced; only recreated
## coordinate/indexing variables like `time` lose it.)
##
## Wiring: in vrtstack(), `template = TRUE` branch ->
##     xml <- mdim_recipe_xml(files, n_template = n_template)


#' Assemble a first-n mdim recipe, with dropped coordinate units restored
#' @keywords internal
mdim_recipe_xml <- function(files, n_template = 10, enrich = TRUE) {
  x <- mdim_mosaic_xml(utils::head(files, n_template))
  if (isTRUE(enrich)) {
    x <- as.character(graft_coord_units(x, source = files[[1L]]))
  }
  x
}


#' Inject `<Unit>` on coordinate arrays that lost it in `gdal mdim mosaic`
#'
#' A coordinate array is any `<Array>` with no `<Source>`. Units are read from
#' one source via `gdal mdim info` (or supplied directly via `units`). Arrays
#' that already carry a `<Unit>` are left untouched, so this is idempotent and a
#' no-op once GDAL propagates the unit itself.
#'
#' @param x Mosaic recipe: xml2 document or XML string.
#' @param source One source path to read units from (via `gdal mdim info`).
#' @param units Optional named character vector (array name -> unit); bypasses
#'   `source` and needs no GDAL (handy for tests).
#' @return Enriched `x` as an `xml_document`.
#' @export
graft_coord_units <- function(x, source = NULL, units = NULL) {
  if (is.null(units)) {
    if (is.null(source)) stop("Supply either `source` or `units`.")
    units <- mdim_source_units(source)
  }
  xd  <- if (inherits(x, "xml_document")) x else xml2::read_xml(x)
  grp <- xml2::xml_find_first(xd, ".//Group")

  for (arr in xml2::xml_find_all(grp, "./Array")) {
    if (!inherits(xml2::xml_find_first(arr, "./Source"), "xml_missing")) next  # data array
    if (!inherits(xml2::xml_find_first(arr, "./Unit"), "xml_missing"))   next  # already set
    u <- units[[xml2::xml_attr(arr, "name")]]
    if (is.null(u) || is.na(u) || !nzchar(u)) next
    xml2::xml_add_child(arr, "Unit", u)          # order-insensitive in VRT
  }
  xd
}


#' Per-array units of a multidimensional source, via `gdal mdim info`
#'
#' Returns a named character vector (array name -> unit) for arrays that declare
#' one. Recurses nested groups.
#' @keywords internal
mdim_source_units <- function(source) {
  stopifnot(requireNamespace("gdalraster", quietly = TRUE),
            requireNamespace("jsonlite",  quietly = TRUE))
  ## `gdal mdim info` emits JSON; capture it. Adjust to your gdalraster's
  ## gdal_run result accessor if it does not return stdout as a string.
  txt <- gdalraster::gdal_run("mdim info", c(source))$output()  # <- confirm accessor
  info <- jsonlite::fromJSON(txt, simplifyVector = FALSE)

  out <- character()
  walk <- function(node) {
    for (nm in names(node[["arrays"]] %||% list())) {
      u <- node[["arrays"]][[nm]][["unit"]]
      if (!is.null(u) && nzchar(u)) out[[nm]] <<- u
    }
    for (g in node[["groups"]] %||% list()) walk(g)
  }
  walk(info)
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a
