#' Stack rasters into a multidimensional VRT (two paths, one entry point)
#'
#' `vrtstack()` builds a GDAL multidimensional VRT that concatenates a set of
#' sources along one axis. Two construction paths share a single concat-axis
#' resolver:
#'
#' * **from-scratch** (`template = NULL`) — the original GeoTIFF/COG path. Each
#'   2D source contributes one slab of a *single* new 3D array. Sources use the
#'   classic `<SourceBand>` + `<SourceTranspose>` form.
#' * **template-extend** (`template = <vrt>` or `template = TRUE`) — for
#'   mdim-recognised sources (NetCDF/Zarr/HDF5) that may carry *several* arrays
#'   (OISST: anom/err/ice/sst). A small "first-n" mdim VRT is taken as the
#'   recipe, and the full file set is fleshed out by re-parameterising only the
#'   concat dimension and the per-array `<Source>` lists. Everything else
#'   (coordinate arrays, slab geometry, scale/offset/unit/attributes) is carried
#'   verbatim from the template.
#'
#' The template is the GDAL-native analogue of the "recipe-not-payload"
#' principle: GDAL's own `gdal mdim mosaic` writes the recipe for the first n
#' files; we only template the axis that varies with the file set.
#'
#' @param files Character vector of source paths/URIs (full set).
#' @param concat Concat-axis spec, resolved by [resolve_concat()]: a numeric/
#'   character vector (length == `files`), a single regex with one capture
#'   group to pull from basenames, a function of basename, or `NULL` to use
#'   `concat_start`/`concat_increment` (from-scratch) or the template's own
#'   values (template-extend, when concat is `NULL`).
#' @param template One of: `NULL` (from-scratch); a path to a `.vrt`; an XML
#'   string; or `TRUE` to auto-generate the recipe from `head(files, n_template)`
#'   via `gdal mdim mosaic`.
#' @param concat_dim Name of the concatenation dimension. Default `"time"`.
#' @param n_template Files used to build the auto-generated recipe when
#'   `template = TRUE`. Default 10.
#' @param parse_format,origin,unit Passed to [resolve_concat()] for date parsing.
#' @param output Output VRT path, or `NULL` to return the XML string.
#' @param ... Passed to the from-scratch builder (`dim_type`, `dim_unit`,
#'   `array_name`, etc.) and ignored on the template path.
#'
#' @return Path to the VRT (invisibly) or the XML string if `output` is `NULL`.
#' @examples
#' #vrt <- vrtstack(<files>, concat = "(\\d{8})", parse_format = "%Y%m%d",
#' #origin = "1978-01-01", unit = "days",   # must match the template
#' #template = TRUE, concat_dim = "time")
#'
#' @export
vrtstack <- function(files,
                     concat = NULL,
                     template = NULL,
                     concat_dim = "time",
                     n_template = 10,
                     parse_format = NULL,
                     origin = NULL,
                     unit = "days",
                     output = NULL,
                     ...) {
  stopifnot(length(files) > 0L)

  ## ---- shared concat-axis resolution -------------------------------------
  ## NULL is allowed on the template path (template carries its own values).
  concat_vals <- if (is.null(concat) && !is.null(template)) {
    NULL
  } else {
    resolve_concat(files, concat,
                   parse_format = parse_format, origin = origin, unit = unit)
  }

  ## ---- dispatch -----------------------------------------------------------
  if (is.null(template)) {
    ## from-scratch (2D -> single 3D array). Delegates to the existing builder.
    return(gdal_mdim_stack(files = files,
                           dim_name = concat_dim,
                           dim_values = concat_vals,
                           parse_format = parse_format,
                           output = output, ...))
  }

  ## template path -- obtain recipe XML
  xml <- if (isTRUE(template)) {
    mdim_mosaic_xml(utils::head(files, n_template))
  } else if (grepl("<VRTDataset", template, fixed = TRUE)) {
    template                       # already an XML string
  } else {
    paste(readLines(template, warn = FALSE), collapse = "\n")  # a path
  }

  doc <- mdim_template_extend(xml, files,
                              concat_values = concat_vals,
                              concat_dim = concat_dim)

  if (is.null(output)) {
    return(as.character(doc))
  }
  xml2::write_xml(doc, output)
  invisible(output)
}


#' Extend an mdim VRT recipe to a full file set
#'
#' Pure XML-tree rewrite (no GDAL needed). Sets the concat dimension size,
#' rewrites the concat coordinate array's values, and regenerates the
#' `<Source>` list of every *data* array (an `<Array>` that owns a `<Source>`).
#' Per-array `SourceArray` path and slab geometry are read from the array's
#' first source, never assumed from the array name.
#'
#' @param xml Template VRT as an XML string (or anything [xml2::read_xml()] takes).
#' @param files Full character vector of sources.
#' @param concat_values Values for the concat coordinate array, or `NULL` to
#'   keep the template's values (only valid when length matches `files`).
#' @param concat_dim Concat dimension name (default `"time"`); if not found,
#'   the dimension whose `size` equals the template's per-array source count is
#'   used.
#' @return An `xml_document` (serialise with [as.character()] / [xml2::write_xml()]).
#' @export
mdim_template_extend <- function(xml, files, concat_values = NULL,
                                 concat_dim = "time") {
  doc <- if (inherits(xml, "xml_document")) xml else xml2::read_xml(xml)
  grp <- xml2::xml_find_first(doc, ".//Group")
  n   <- length(files)

  ## --- locate the concat dimension ----------------------------------------
  dim_node <- xml2::xml_find_first(
    grp, sprintf("./Dimension[@name='%s']", concat_dim))
  if (inherits(dim_node, "xml_missing")) {
    ## fall back: the dim whose size matches the template source count
    a1 <- xml2::xml_find_first(grp, "./Array[Source]")
    ksrc <- length(xml2::xml_find_all(a1, "./Source"))
    dims <- xml2::xml_find_all(grp, "./Dimension")
    sizes <- as.integer(xml2::xml_attr(dims, "size"))
    hit <- which(sizes == ksrc)
    if (length(hit) != 1L)
      stop("Could not identify the concat dimension; pass `concat_dim`.")
    dim_node <- dims[[hit]]
    concat_dim <- xml2::xml_attr(dim_node, "name")
  }
  axis <- .concat_axis_index(grp, concat_dim)   # position in the slab tuples
  xml2::xml_set_attr(dim_node, "size", n)

  ## --- rewrite the concat coordinate array values -------------------------
  carr <- xml2::xml_find_first(grp, sprintf("./Array[@name='%s']", concat_dim))
  iv   <- xml2::xml_find_first(carr, "./InlineValues")
  if (!is.null(concat_values)) {
    stopifnot(length(concat_values) == n)
    if (inherits(concat_values, c("Date", "POSIXt")))
      stop("concat_values must be numbers in the coordinate's own units ",
           "(e.g. days-since-epoch), not Date/POSIXct. Encode first via ",
           "resolve_concat(origin=, unit=) or read them from the files.")
    xml2::xml_text(iv) <- paste(format(concat_values, scientific = FALSE,
                                       trim = TRUE), collapse = " ")
    if (!is.na(xml2::xml_attr(iv, "count")))
      xml2::xml_set_attr(iv, "count", n)
  } else if (length(xml2::xml_text(iv) |> strsplit("\\s+") |> unlist()) != n) {
    stop("concat_values is NULL but template values do not match length(files).")
  }

  ## --- regenerate sources for every data array ----------------------------
  for (arr in xml2::xml_find_all(grp, "./Array[Source]")) {
    srcs  <- xml2::xml_find_all(arr, "./Source")
    proto <- srcs[[1]]
    src_array <- xml2::xml_text(xml2::xml_find_first(proto, "./SourceArray"))
    sslab <- xml2::xml_find_first(proto, "./SourceSlab")
    count <- xml2::xml_attr(sslab, "count")
    step  <- xml2::xml_attr(sslab, "step")
    ndim  <- length(strsplit(count, ",")[[1]])

    ## anchor = first <Attribute>, so rebuilt sources stay ahead of metadata
    anchor <- xml2::xml_find_first(arr, "./Attribute")
    xml2::xml_remove(srcs)

    zero <- paste(rep("0", ndim), collapse = ",")
    for (i in seq_len(n)) {
      s <- .add_node(arr, anchor, "Source")
      xml2::xml_add_child(s, "SourceFilename", files[i])
      if (!is.na(src_array))
        xml2::xml_add_child(s, "SourceArray", src_array)
      dst <- rep("0", ndim); dst[axis] <- as.character(i - 1L)
      xml2::xml_set_attrs(xml2::xml_add_child(s, "SourceSlab"),
                          c(offset = zero, count = count, step = step))
      xml2::xml_set_attrs(xml2::xml_add_child(s, "DestSlab"),
                          c(offset = paste(dst, collapse = ",")))
    }
  }
  doc
}


#' Resolve concat-axis values (shared by both paths)
#'
#' Prefers `stringr::str_match()` over `regmatches()`/`regexec()`: the latter
#' silently drops non-matches and misaligns rows.
#' @keywords internal
#' @export
resolve_concat <- function(files, concat,
                           parse_format = NULL, origin = NULL, unit = "days") {
  if (is.null(concat)) return(NULL)
  if (is.function(concat)) {
    return(vapply(basename(files), concat, numeric(1), USE.NAMES = FALSE))
  }
  if (is.character(concat) && length(concat) == 1L && grepl("\\(", concat)) {
    vals <- stringr::str_match(basename(files), concat)[, 2]   # NA-safe
    if (anyNA(vals))
      stop("Pattern did not match: ",
           paste(utils::head(basename(files)[is.na(vals)], 3), collapse = ", "))
    if (!is.null(parse_format)) {
      t <- as.POSIXct(strptime(vals, parse_format, tz = "UTC"))
      if (anyNA(t)) stop("strptime failed with format '", parse_format, "'")
      if (is.null(origin)) return(as.numeric(t))
      o <- if (is.character(origin)) as.POSIXct(origin, tz = "UTC") else origin
      div <- c(seconds = 1, minutes = 60, hours = 3600, days = 86400)[[unit]]
      return(as.numeric(difftime(t, o, units = "secs")) / div)
    }
    num <- suppressWarnings(as.numeric(vals))
    return(if (anyNA(num)) vals else num)
  }
  stopifnot(length(concat) == length(files))
  concat
}


## ---- internal helpers ------------------------------------------------------

#' @keywords internal
.concat_axis_index <- function(grp, concat_dim) {
  ## DimensionRef order on a data array defines slab-tuple order.
  arr <- xml2::xml_find_first(grp, "./Array[Source]")
  refs <- xml2::xml_attr(xml2::xml_find_all(arr, "./DimensionRef"), "ref")
  idx <- match(concat_dim, refs)
  if (is.na(idx)) stop("concat_dim '", concat_dim, "' not in array dimensions.")
  idx
}

#' @keywords internal
.add_node <- function(parent, anchor, name) {
  if (inherits(anchor, "xml_missing") || is.null(anchor)) {
    xml2::xml_add_child(parent, name)              # no attributes: append
  } else {
    xml2::xml_add_sibling(anchor, name, .where = "before")  # keep ascending order
  }
}

#' Build a first-n mdim recipe with `gdal mdim mosaic` (no temp file)
#'
#' Writes to `/vsimem/` and reads the bytes back, so nothing hits disk.
#' Requires gdalraster with the `gdal_run` algorithm interface.
#' @keywords internal
mdim_mosaic_xml <- function(files) {
  stopifnot(requireNamespace("gdalraster", quietly = TRUE))
  lst <- tempfile(fileext = ".txt"); on.exit(unlink(lst), add = TRUE)
  writeLines(files, lst)
  mem <- sprintf("/vsimem/%s.vrt", basename(tempfile()))
  gdalraster::gdal_run(
    "mdim mosaic",
    c("--input", sprintf("@%s", lst), "--output", mem, "--overwrite"))
  on.exit(try(gdalraster::vsi_unlink(mem), silent = TRUE), add = TRUE)
  con <- gdalraster::VSIFile$new(mem)
  on.exit(con$close(), add = TRUE)
  rawToChar(con$ingest(-1))                 # whole file as raw -> character
}
