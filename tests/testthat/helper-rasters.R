# Skip a test when the installed GDAL lacks the unified CLI algorithms that
# gdal_run() drives (verify_vrt, the mdim mosaic/info paths). That interface
# needs GDAL >= 3.11.3; older builds error "gdal_run() requires GDAL >= ...".
# gdalraster's version accessor return shape varies, so parse defensively.
skip_if_no_gdal_cli <- function() {
  testthat::skip_if_not_installed("gdalraster")
  ok <- tryCatch({
    v <- as.character(gdalraster::gdal_version())[1]
    num <- suppressWarnings(as.integer(v))          # some builds: "3110300"
    if (is.na(num)) {
      m <- regmatches(v, regexpr("[0-9]+\\.[0-9]+\\.[0-9]+", v))  # "GDAL 3.11.3"
      if (length(m)) {
        p <- as.integer(strsplit(m, ".", fixed = TRUE)[[1]])
        num <- p[1] * 1000000L + p[2] * 10000L + p[3] * 100L
      }
    }
    !is.na(num) && num >= 3110300L
  }, error = function(e) FALSE)
  if (!ok) testthat::skip("gdal_run() requires GDAL >= 3.11.3")
}

# Evaluate a gdal_run()-backed expression, but skip (not fail) when the error
# is a CLI-capability gap rather than a real defect. A version check is not
# enough: some builds report GDAL >= 3.11.3 yet cannot instantiate the unified
# CLI algorithms (seen on Windows: "failed to instantiate CLI algorithm from
# path"). Skipping only on the real call's capability errors means capable
# platforms still run the assertions -- no silent over-skip.
skip_on_gdal_cli_error <- function(expr) {
  res <- tryCatch(expr, error = function(e) e)
  if (inherits(res, "error")) {
    msg <- conditionMessage(res)
    if (grepl("requires GDAL|instantiate", msg, ignore.case = TRUE))
      testthat::skip(paste("GDAL CLI unavailable:", msg))
    stop(res)                       # a genuine error still fails the test
  }
  res
}

# Small on-disk GeoTIFFs to exercise the file-probing paths without network.
# EPSG:4326, 0.25-degree grid, single Int16 band, optional NoData.
make_tifs <- function(names,
                      dir = tempfile("vrtstack-tests"),
                      nx = 8L, ny = 6L, nodata = -999) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dir, names)
  for (i in seq_along(paths)) {
    gdalraster::create(format = "GTiff", dst_filename = paths[i],
                       xsize = nx, ysize = ny, nbands = 1L,
                       dataType = "Int16")
    ds <- methods::new(gdalraster::GDALRaster, paths[i], read_only = FALSE)
    ds$setGeoTransform(c(0, 0.25, 0, 90, 0, -0.25))
    ds$setProjection(gdalraster::epsg_to_wkt(4326))
    if (!is.na(nodata)) ds$setNoDataValue(1L, nodata)
    ds$write(band = 1L, 0L, 0L, nx, ny,
             matrix(as.integer(i * seq_len(nx * ny)), ny, nx))
    ds$close()
  }
  paths
}

# A minimal multidimensional-VRT recipe (time, y, x) with SourceArray sources,
# used to exercise mdim_template_extend() without touching GDAL.
template_xml <- function() {
  paste(
    '<VRTDataset>',
    '  <Group name="/">',
    '    <Dimension name="time" size="2"/>',
    '    <Dimension name="y" size="4"/>',
    '    <Dimension name="x" size="5"/>',
    '    <Array name="time">',
    '      <DataType>Float64</DataType>',
    '      <DimensionRef ref="time"/>',
    '      <InlineValues>0 1</InlineValues>',
    '    </Array>',
    '    <Array name="sst">',
    '      <DataType>Int16</DataType>',
    '      <DimensionRef ref="time"/>',
    '      <DimensionRef ref="y"/>',
    '      <DimensionRef ref="x"/>',
    '      <Source>',
    '        <SourceFilename>a.nc</SourceFilename>',
    '        <SourceArray>/sst</SourceArray>',
    '        <SourceSlab offset="0,0,0" count="1,4,5" step="1,1,1"/>',
    '        <DestSlab offset="0,0,0"/>',
    '      </Source>',
    '      <Source>',
    '        <SourceFilename>b.nc</SourceFilename>',
    '        <SourceArray>/sst</SourceArray>',
    '        <SourceSlab offset="0,0,0" count="1,4,5" step="1,1,1"/>',
    '        <DestSlab offset="1,0,0"/>',
    '      </Source>',
    '    </Array>',
    '  </Group>',
    '</VRTDataset>', sep = "\n")
}
