#' Create a Multidimensional VRT from 2D Rasters
#'
#' Stack 2D rasters along a new dimension, producing a GDAL Multidimensional VRT.
#' This enables treating a collection of 2D rasters (COGs, GeoTIFFs, etc.) as a
#' single multidimensional array, readable by GDAL's multidim API and xarray backends.
#'
#' @param files Character vector of file paths (COGs, GeoTIFFs, /vsicurl/ URIs, etc.)
#' @param dim_name Name for the new dimension (e.g., "time", "depth", "level")
#' @param dim_values Dimension values. One of:
#'   - Numeric vector of values (length must match files)
#'   - A regex pattern with one capturing group to extract from filenames
#'   - A function taking filename (basename) and returning a numeric value
#'   - NULL if using `dim_start` + `dim_increment`
#' @param dim_start,dim_increment For regular axes, specify start and increment
#'   instead of explicit values. Files are assumed to be in the correct order.
#' @param dim_type Optional dimension type: `"TEMPORAL"`, `"VERTICAL"`, `"PARAMETRIC"`
#' @param dim_direction Optional direction: `"NORTH"`, `"SOUTH"`, `"EAST"`, `"WEST"`,
#'   `"UP"`, `"DOWN"`, `"FUTURE"`, `"PAST"`
#' @param dim_unit Unit string for the dimension (e.g., `"days since 1970-01-01"`, `"cm"`)
#' @param time_origin For temporal dimensions, origin date as `"YYYY-MM-DD"` or POSIXct.
#'   When set with `parse_format`, values are encoded as offsets from this origin.
#' @param time_unit For temporal dimensions: `"seconds"`, `"minutes"`, `"hours"`, `"days"`
#' @param parse_format For date/time extraction, a [strptime()] format string
#'   (e.g., `"%Y%m%d"` for `"20230115"`)
#' @param array_name Name for the data array in the VRT. Default: derived from
#'   common filename prefix, or `"data"`.
#' @param output Output VRT path. If NULL, returns XML string without writing.
#'
#' @return Path to VRT file (invisibly), or XML string if `output` is NULL.
#'
#' @details
#' The function generates a GDAL Multidimensional VRT that virtually stacks
#' 2D rasters along a new dimension. Key features:
#'
#' - **Regular axes**: When dimension values are evenly spaced (or specified via
#'   `dim_start`/`dim_increment`), the VRT uses `<RegularlySpacedValues>` for
#'   compact representation.
#'
#' - **Auto-detection**: Even with explicit `dim_values`, regular spacing is
#'   detected automatically and converted to the compact form.
#'
#' - **Filename parsing**: Extract dimension values from filenames using regex,
#'   with optional date/time parsing. Useful for time series like

#'   `"temperature_20230101.tif"`.
#'
#' - **Cloud-native**: Supports `/vsicurl/` URIs for remote files. HTTP(S) URLs
#'   are automatically prefixed with `/vsicurl/`.
#'
#' The resulting VRT can be read by:
#' - GDAL's multidim API: `gdalmdiminfo`, `gdalmdimtranslate`
#' - Python xarray backends: gdx, xgdal
#' - Any tool supporting GDAL multidimensional rasters
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Stack soil layers by depth
#' gdal_mdim_stack(
#'   files = c("soil_0cm.tif", "soil_30cm.tif", "soil_100cm.tif"),
#'   dim_name = "depth",
#'   dim_values = c(0, 30, 100),
#'   dim_type = "VERTICAL",
#'   dim_direction = "DOWN",
#'   dim_unit = "cm",
#'   output = "soil_stack.vrt"
#' )
#'
#' # Time series with regex extraction
#' gdal_mdim_stack(
#'   files = list.files(pattern = "temp_\\d{8}\\.tif$"),
#'   dim_name = "time",
#'   dim_values = "(\\d{8})",
#'   parse_format = "%Y%m%d",
#'   dim_type = "TEMPORAL",
#'   time_origin = "1970-01-01",
#'   time_unit = "days",
#'   output = "temperature.vrt"
#' )
#'
#' # Regular axis - monthly data
#' gdal_mdim_stack(
#'   files = sprintf("precip_%02d.tif", 1:12),
#'   dim_name = "month",
#'   dim_start = 1,
#'   dim_increment = 1,
#'   output = "monthly.vrt"
#' )
#'
#' # Cloud-hosted COGs
#' gdal_mdim_stack(
#'   files = paste0(
#'     "https://storage.googleapis.com/solus100pub/claytotal_",
#'     c(0, 5, 15, 30, 60, 100, 150), "_cm_p.tif"
#'   ),
#'   dim_name = "depth",
#'   dim_values = c(0, 5, 15, 30, 60, 100, 150),
#'   dim_type = "VERTICAL",
#'   dim_unit = "cm",
#'   array_name = "claytotal",
#'   output = "solus_clay.vrt"
#' )
#' }
gdal_mdim_stack <- function(
    files,
    dim_name,
    dim_values = NULL,
    dim_start = NULL,
    dim_increment = NULL,
    dim_type = NULL,
    dim_direction = NULL,
    dim_unit = NULL,
    time_origin = NULL,
    time_unit = "days",
    parse_format = NULL,
    array_name = NULL,
    output = NULL
) {
  stopifnot(length(files) > 0)

stopifnot(is.character(dim_name), length(dim_name) == 1)

  # Normalize paths - allow /vsi* to pass through
  files <- vapply(files, function(f) {
    if (grepl("^/vsi|^https?://", f)) f else normalizePath(f, mustWork = TRUE)
  }, FUN.VALUE = character(1), USE.NAMES = FALSE)

  n_files <- length(files)

  # --- Resolve dimension values ---
  use_regular <- !is.null(dim_start) && !is.null(dim_increment)

  if (use_regular) {
    dim_vals <- NULL
    dim_size <- n_files
  } else if (is.null(dim_values)) {
    stop("Provide dim_values, or dim_start + dim_increment for regular axis")
  } else if (is.character(dim_values) && length(dim_values) == 1 &&
             grepl("\\(", dim_values)) {
    # Regex pattern
    dim_vals <- .extract_dim_from_filenames(
      files, dim_values, parse_format, time_origin, time_unit
    )
    dim_size <- length(dim_vals)
  } else if (is.function(dim_values)) {
    dim_vals <- vapply(basename(files), dim_values, FUN.VALUE = numeric(1))
    dim_size <- length(dim_vals)
  } else {
    stopifnot(length(dim_values) == n_files)
    dim_vals <- dim_values
    dim_size <- n_files
  }

  # Sort by dimension value and check for regular spacing
  if (!is.null(dim_vals) && is.numeric(dim_vals)) {
    ord <- order(dim_vals)
    files <- files[ord]
    dim_vals <- dim_vals[ord]

    if (length(dim_vals) >= 2) {
      diffs <- diff(dim_vals)
      if (length(unique(round(diffs, 10))) == 1) {
        message("Detected regular spacing: start=", dim_vals[1],
                ", increment=", diffs[1])
        dim_start <- dim_vals[1]
        dim_increment <- diffs[1]
        use_regular <- TRUE
      }
    }
  }

  # --- Get reference raster info ---
  ref_info <- .get_raster_info(files[1])

  # --- Determine array name ---
  if (is.null(array_name)) {
    array_name <- .array_name_from_files(files)
  }

  # --- Build unit string for temporal ---
  if (!is.null(dim_type) && dim_type == "TEMPORAL" &&
      !is.null(time_origin) && is.null(dim_unit)) {
    origin_str <- if (inherits(time_origin, "POSIXt")) {
      format(time_origin, "%Y-%m-%d")
    } else {
      as.character(time_origin)
    }
    dim_unit <- sprintf("%s since %s", time_unit, origin_str)
  }

  # --- Build VRT XML ---
  xml <- .build_mdim_vrt_xml(
    files = files,
    ref_info = ref_info,
    dim_name = dim_name,
    dim_size = dim_size,
    dim_vals = dim_vals,
    dim_start = dim_start,
    dim_increment = dim_increment,
    dim_type = dim_type,
    dim_direction = dim_direction,
    dim_unit = dim_unit,
    use_regular = use_regular,
    array_name = array_name
  )

  if (is.null(output)) {
    return(xml)
  }

  writeLines(xml, output)
  message("Wrote: ", output)
  invisible(output)
}


#' @noRd
.extract_dim_from_filenames <- function(files, pattern, parse_format,
                                         time_origin, time_unit) {
  basenames <- basename(files)
  # Use stringr-style extraction via regmatches
  matches <- regmatches(basenames, regexec(pattern, basenames))

  vals <- vapply(matches, function(m) {
    if (length(m) < 2) NA_character_ else m[2]
  }, FUN.VALUE = character(1))

  if (any(is.na(vals))) {
    bad <- basenames[is.na(vals)]
    stop("Pattern did not match: ", paste(utils::head(bad, 3), collapse = ", "))
  }

  # Parse as date/time if format provided
  if (!is.null(parse_format)) {
    parsed <- as.POSIXct(strptime(vals, format = parse_format, tz = "UTC"))
    if (any(is.na(parsed))) {
      stop("Failed to parse dates with format '", parse_format, "'")
    }

    if (!is.null(time_origin)) {
      if (is.character(time_origin)) {
        time_origin <- as.POSIXct(time_origin, tz = "UTC")
      }
      diff_secs <- as.numeric(difftime(parsed, time_origin, units = "secs"))
      divisor <- switch(time_unit,
        "seconds" = 1, "minutes" = 60, "hours" = 3600, "days" = 86400, 86400
      )
      return(diff_secs / divisor)
    }
    return(as.numeric(parsed))
  }

  # Try numeric
  numeric_vals <- suppressWarnings(as.numeric(vals))
  if (!any(is.na(numeric_vals))) {
    return(numeric_vals)
  }
  # Return as character if not numeric
  vals
}


#' @noRd
.has_value <- function(x) !is.null(x) && length(x) == 1L && !is.na(x)
.num_or_na <- function(x) {
  if (!.has_value(x)) return(NA_real_)
  suppressWarnings(as.numeric(x))
}

.get_raster_info <- function(file) {
  if (requireNamespace("gdalraster", quietly = TRUE)) {
    ds <- methods::new(gdalraster::GDALRaster, file, TRUE)
    on.exit(ds$close())
    return(list(
      ncol = ds$getRasterXSize(),
      nrow = ds$getRasterYSize(),
      gt = ds$getGeoTransform(),
      srs = ds$getProjectionRef(),
      dtype = ds$getDataTypeName(1),
      nodata = ds$getNoDataValue(1),
      blocksize = ds$getBlockSize(1),
      scale = ds$getScale(1),
      offset = ds$getOffset(1),
      unit = ds$getUnitType(1)
    ))
  }

  if (requireNamespace("vapour", quietly = TRUE)) {
    info <- vapour::vapour_raster_info(file)
    return(list(
      ncol = info$dimXY[1],
      nrow = info$dimXY[2],
      gt = info$geotransform,
      srs = info$projection,
      dtype = "Float32",
      nodata = NA_real_,
      blocksize = c(256, 256)
    ))
  }

  stop("Requires 'gdalraster' or 'vapour' package")
}


#' @noRd
.gdal_to_vrt_dtype <- function(dtype) {
  mapping <- c(
    Byte = "Byte", UInt8 = "Byte",
    UInt16 = "UInt16", Int16 = "Int16",
    UInt32 = "UInt32", Int32 = "Int32",
    UInt64 = "UInt64", Int64 = "Int64",
    Float32 = "Float32", Float64 = "Float64"
  )
  if (dtype %in% names(mapping)) mapping[[dtype]] else "Float64"
}


#' @noRd
.xml_escape <- function(x) {
  x <- gsub("&", "&amp;", x, fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  x <- gsub("\"", "&quot;", x, fixed = TRUE)
  x
}


#' @noRd
.common_affix <- function(strings, side = c("prefix", "suffix")) {
  side <- match.arg(side)
  if (!length(strings)) return("")
  rev_str <- function(s) vapply(s, function(x)
    paste(rev(strsplit(x, "", fixed = TRUE)[[1]]), collapse = ""),
    character(1), USE.NAMES = FALSE)
  if (side == "suffix") strings <- rev_str(strings)
  if (length(strings) < 2) {
    out <- strings[1]
  } else {
    chars <- strsplit(strings, "", fixed = TRUE)
    min_len <- min(lengths(chars))
    out <- ""
    for (i in seq_len(min_len)) {
      ch <- unique(vapply(chars, `[`, character(1), i))
      if (length(ch) == 1) out <- paste0(out, ch) else break
    }
  }
  if (side == "suffix") out <- rev_str(out)
  out
}

# Derive a data-array name from a file collection. The shared part of the
# names carries the variable (e.g. GHRSST "...analysed_sst.tif"); the varying
# part is the index (a date, a depth). Take the first identifier word of the
# common prefix and the last of the common suffix, drop trailing digits, and
# keep whichever has the most letters. A collection whose only shared part is a
# date (leading digits) yields no valid identifier that way, so the result is
# "band1" rather than a numeric, invalid name. An explicit `array_name` always
# overrides this.
#' @noRd
.array_name_from_files <- function(files) {
  bn <- sub("\\.[^.]*$", "", basename(files))        # drop extension
  first_word <- function(s) {
    m <- regmatches(s, regexpr("[A-Za-z][A-Za-z0-9_]*", s))
    if (length(m)) m else ""
  }
  last_word <- function(s) {
    m <- regmatches(s, gregexpr("[A-Za-z][A-Za-z0-9_]*", s))[[1]]
    if (length(m)) m[length(m)] else ""
  }
  tidy <- function(t) sub("^_+|_+$", "", sub("[_0-9]+$", "", t))

  cand <- c(tidy(first_word(.common_affix(bn, "prefix"))),
            tidy(last_word(.common_affix(bn, "suffix"))))
  cand <- cand[grepl("^[A-Za-z][A-Za-z0-9_]*$", cand)]
  if (!length(cand)) return("band1")
  cand[[which.max(nchar(gsub("[^A-Za-z]", "", cand)))]]
}


#' @noRd
.build_mdim_vrt_xml <- function(
    files, ref_info, dim_name, dim_size, dim_vals,
    dim_start, dim_increment, dim_type, dim_direction, dim_unit,
    use_regular, array_name
) {
  gt <- ref_info$gt
  ncol <- ref_info$ncol
  nrow <- ref_info$nrow

  # Pixel centers
  x_start <- gt[1] + gt[2] / 2
  x_inc <- gt[2]
  y_start <- gt[4] + gt[6] / 2
  y_inc <- gt[6]

  lines <- c('<VRTDataset>', '  <Group name="/">')

  # --- Dimensions ---
  dim_attrs <- sprintf('name="%s" size="%d"', dim_name, dim_size)
  if (!is.null(dim_type)) dim_attrs <- paste0(dim_attrs, sprintf(' type="%s"', dim_type))
  if (!is.null(dim_direction)) dim_attrs <- paste0(dim_attrs, sprintf(' direction="%s"', dim_direction))
  dim_attrs <- paste0(dim_attrs, sprintf(' indexingVariable="%s"', dim_name))

  lines <- c(lines,
    sprintf('    <Dimension %s/>', dim_attrs),
    sprintf('    <Dimension name="y" size="%d" type="HORIZONTAL_Y" direction="NORTH" indexingVariable="y"/>', nrow),
    sprintf('    <Dimension name="x" size="%d" type="HORIZONTAL_X" direction="EAST" indexingVariable="x"/>', ncol)
  )

  # --- Coordinate arrays ---
  # Stacking dimension
  lines <- c(lines, sprintf('    <Array name="%s">', dim_name))
  # <Unit> precedes the value carrier in the XSD's Array sequence.
  unit_line <- if (!is.null(dim_unit)) {
    sprintf('      <Unit>%s</Unit>', .xml_escape(dim_unit))
  } else character(0)
  if (use_regular) {
    lines <- c(lines,
      '      <DataType>Float64</DataType>',
      sprintf('      <DimensionRef ref="%s"/>', dim_name),
      unit_line,
      sprintf('      <RegularlySpacedValues start="%s" increment="%s"/>',
              format(dim_start, scientific = FALSE, trim = TRUE),
              format(dim_increment, scientific = FALSE, trim = TRUE))
    )
  } else {
    dtype <- if (is.numeric(dim_vals)) "Float64" else "String"
    vals_str <- if (is.numeric(dim_vals)) {
      paste(format(dim_vals, scientific = FALSE, trim = TRUE), collapse = " ")
    } else {
      paste(dim_vals, collapse = " ")
    }
    lines <- c(lines,
      sprintf('      <DataType>%s</DataType>', dtype),
      sprintf('      <DimensionRef ref="%s"/>', dim_name),
      unit_line,
      sprintf('      <InlineValues>%s</InlineValues>', vals_str)
    )
  }
  lines <- c(lines, '    </Array>')

  # Y and X coordinates
  lines <- c(lines,
    '    <Array name="y">',
    '      <DataType>Float64</DataType>',
    '      <DimensionRef ref="y"/>',
    sprintf('      <RegularlySpacedValues start="%.10g" increment="%.10g"/>', y_start, y_inc),
    '    </Array>',
    '    <Array name="x">',
    '      <DataType>Float64</DataType>',
    '      <DimensionRef ref="x"/>',
    sprintf('      <RegularlySpacedValues start="%.10g" increment="%.10g"/>', x_start, x_inc),
    '    </Array>'
  )

  # --- Data array ---
  vrt_dtype <- .gdal_to_vrt_dtype(ref_info$dtype)
  block_y <- min(ref_info$blocksize[2], 512)
  block_x <- min(ref_info$blocksize[1], 512)

  lines <- c(lines,
    sprintf('    <Array name="%s">', array_name),
    sprintf('      <DataType>%s</DataType>', vrt_dtype),
    sprintf('      <DimensionRef ref="%s"/>', dim_name),
    '      <DimensionRef ref="y"/>',
    '      <DimensionRef ref="x"/>',
    sprintf('      <BlockSize>1,%d,%d</BlockSize>', block_y, block_x)
  )

  if (!is.null(ref_info$srs) && nchar(ref_info$srs) > 0) {
    # Array dims are (stack, y, x): y is dim 2, x is dim 3.
    lines <- c(lines,
      sprintf('      <SRS dataAxisToSRSAxisMapping="%s">%s</SRS>',
              .srs_axis_mapping(ref_info$srs, y_dim = 2L, x_dim = 3L),
              .xml_escape(ref_info$srs))
    )
  }

  # Unit / NoData / Offset / Scale, in XSD order. The VRT reads source
  # bytes, so a packed band (e.g. GHRSST MUR analysed_sst: Int16, scale
  # 0.001, offset 25) needs its scale and offset here or unscaled reads
  # return raw counts.
  if (.has_value(ref_info$unit) && nzchar(ref_info$unit)) {
    lines <- c(lines, sprintf('      <Unit>%s</Unit>', .xml_escape(ref_info$unit)))
  }
  if (!is.null(ref_info$nodata) && !is.na(ref_info$nodata)) {
    lines <- c(lines, sprintf('      <NoDataValue>%s</NoDataValue>', ref_info$nodata))
  }
  scale <- .num_or_na(ref_info$scale)
  offset <- .num_or_na(ref_info$offset)
  packed <- (!is.na(scale) && scale != 1) || (!is.na(offset) && offset != 0)
  if (packed) {
    lines <- c(lines,
      sprintf('      <Offset>%.15g</Offset>', if (is.na(offset)) 0 else offset),
      sprintf('      <Scale>%.15g</Scale>', if (is.na(scale)) 1 else scale))
  }

  # Sources. Each states its extent in a <SourceSlab>: without the count,
  # GDAL opens every source, in order, to learn its shape on each read
  # through the VRT (a HEAD and a header GET per /vsicurl/ COG). With it,
  # a read opens only the sources it touches. The count is in the
  # transposed (stack, y, x) order, so 1, nrow, ncol.
  source_slab <- sprintf(
    '        <SourceSlab offset="0,0,0" count="1,%d,%d" step="1,1,1"/>',
    nrow, ncol
  )
  for (i in seq_along(files)) {
    src <- files[i]
    if (grepl("^https?://", src)) src <- paste0("/vsicurl/", src)
    lines <- c(lines,
      '      <Source>',
      sprintf('        <SourceFilename>%s</SourceFilename>', .xml_escape(src)),
      '        <SourceBand>1</SourceBand>',
      '        <SourceTranspose>-1,0,1</SourceTranspose>',
      source_slab,
      sprintf('        <DestSlab offset="%d,0,0"/>', i - 1),
      '      </Source>'
    )
  }

  lines <- c(lines, '    </Array>', '  </Group>', '</VRTDataset>')
  paste(lines, collapse = "\n")
}
