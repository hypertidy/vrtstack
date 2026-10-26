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


#' Assemble a first-n mdim recipe, with dropped coordinate units and root-group
#' provenance attributes restored
#'
#' @param metadata_from Which source donates the restored metadata: `"first"`,
#'   `"last"`, or an explicit source path. Units are invariant across the stack
#'   so the choice only affects the provenance globals.
#' @keywords internal
mdim_recipe_xml <- function(files, n_template = 10, enrich = TRUE,
                            metadata_from = "first") {
  x <- mdim_mosaic_xml(utils::head(files, n_template))
  if (isTRUE(enrich)) {
    donor <- .resolve_donor(files, metadata_from)
    doc <- graft_coord_units(x, source = donor)
    doc <- graft_group_attrs(doc, source = donor)
    x <- as.character(doc)
  }
  x
}

#' Resolve the metadata donor source from a `metadata_from` spec
#'
#' `"first"`/`"last"` pick an end of `files`; any other string is taken as an
#' explicit source path and used as given (it need not be one of `files`).
#' @keywords internal
.resolve_donor <- function(files, metadata_from = "first") {
  if (length(metadata_from) != 1L || is.na(metadata_from) ||
      !nzchar(metadata_from))
    stop("`metadata_from` must be \"first\", \"last\", or a single source path.")
  switch(metadata_from,
         first = files[[1L]],
         last  = files[[length(files)]],
         metadata_from)            # explicit path, used as-is
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
  info <- jsonlite::fromJSON(.mdim_info_json(source), simplifyVector = FALSE)

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

#' JSON report of a multidimensional source, via `gdal mdim info`
#'
#' For an info-type algorithm `gdal_run()$output()` returns the report string
#' directly; the object is released once the string is in hand.
#' @keywords internal
.mdim_info_json <- function(source) {
  stopifnot(requireNamespace("gdalraster", quietly = TRUE),
            requireNamespace("jsonlite",  quietly = TRUE))
  alg <- gdalraster::gdal_run("mdim info", c("--input", source))
  on.exit(alg$release(), add = TRUE)
  alg$output()
}

`%||%` <- function(a, b) if (is.null(a)) b else a


## ---- root-group provenance attributes -------------------------------------
## `gdal mdim mosaic` copies no root-group attributes (translate's CopyGroup /
## root pass does: apps/gdalmdimtranslate_lib.cpp:1446,1614). This restores the
## invariant provenance globals (title/source/references/...) onto the VRT
## <Group>, mirroring translate: skip Conventions (the writer stamps its own),
## and drop per-file fields that are meaningless once many files are stacked.

## fields that legitimately vary per input file -> not carried into a stack
.MDIM_PER_FILE_GLOBALS <- c(
  "id", "uuid", "date_created", "date_modified", "date_issued", "history",
  "time_coverage_start", "time_coverage_end", "time_coverage_duration"
)

#' Inject invariant root-group provenance attributes dropped by mosaic
#'
#' @param x Mosaic recipe: xml2 document or XML string.
#' @param source One source path to read globals from (via `gdal mdim info`).
#' @param attrs Optional named character vector (name -> value); bypasses
#'   `source` (handy for tests). All treated as String attributes.
#' @param skip Attribute names to exclude (default: `Conventions` + per-file).
#' @return Enriched `x` as an `xml_document`.
#' @export
graft_group_attrs <- function(x, source = NULL, attrs = NULL,
                              skip = c("Conventions", .MDIM_PER_FILE_GLOBALS)) {
  if (is.null(attrs)) {
    if (is.null(source)) stop("Supply either `source` or `attrs`.")
    attrs <- mdim_source_globals(source)
  }
  xd  <- if (inherits(x, "xml_document")) x else xml2::read_xml(x)
  grp <- xml2::xml_find_first(xd, ".//Group")
  have <- xml2::xml_attr(xml2::xml_find_all(grp, "./Attribute"), "name")
  ## insert before the first <Dimension> so group attributes lead the group
  anchor <- xml2::xml_find_first(grp, "./Dimension")

  for (nm in names(attrs)) {
    if (nm %in% skip || nm %in% have) next
    val <- attrs[[nm]]
    if (is.null(val) || is.na(val) || !nzchar(val)) next
    node <- if (inherits(anchor, "xml_missing"))
      xml2::xml_add_child(grp, "Attribute")
    else
      xml2::xml_add_sibling(anchor, "Attribute", .where = "before")
    xml2::xml_set_attr(node, "name", nm)
    xml2::xml_add_child(node, "DataType", "String")
    xml2::xml_add_child(node, "Value", val)
  }
  xd
}

#' Root-group (global) string attributes of a source, via `gdal mdim info`
#' @keywords internal
mdim_source_globals <- function(source) {
  info <- jsonlite::fromJSON(.mdim_info_json(source), simplifyVector = FALSE)
  a <- info[["attributes"]] %||% list()
  vapply(a, function(v) if (is.character(v) || is.numeric(v))
    as.character(v) else NA_character_, character(1))
}
