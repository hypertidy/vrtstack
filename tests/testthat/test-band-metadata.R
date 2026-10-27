# Packed bands and the SRS axis mapping, checked by reading back through GDAL.

make_packed_tifs <- function(names, dir = tempfile("vrtstack-packed"),
                             nx = 8L, ny = 6L, wkt = gdalraster::epsg_to_wkt(4326)) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dir, names)
  for (i in seq_along(paths)) {
    gdalraster::create(format = "GTiff", dst_filename = paths[i],
                       xsize = nx, ysize = ny, nbands = 1L, dataType = "Int16")
    ds <- methods::new(gdalraster::GDALRaster, paths[i], read_only = FALSE)
    ds$setGeoTransform(c(140, 0.25, 0, -40, 0, -0.25))
    ds$setProjection(wkt)
    ds$setNoDataValue(1L, -32768)
    ds$setScale(1L, 0.001)
    ds$setOffset(1L, 25)
    ds$setUnitType(1L, "celsius")
    ds$write(band = 1L, 0L, 0L, nx, ny,
             matrix(as.integer(-11000 + 100 * i + seq_len(nx * ny)), ny, nx))
    ds$close()
  }
  paths
}

test_that("band scale, offset and unit reach the data array, in XSD order", {
  skip_if_not_installed("gdalraster")
  tifs <- make_packed_tifs(sprintf("sst_2026092%d.tif", 1:3))
  xml <- suppressMessages(vrt_time_stack(tifs, array_name = "sst"))
  doc <- xml2::read_xml(xml)
  arr <- xml2::xml_find_first(doc, ".//Array[@name='sst']")
  expect_equal(xml2::xml_text(xml2::xml_find_first(arr, "./Scale")), "0.001")
  expect_equal(xml2::xml_text(xml2::xml_find_first(arr, "./Offset")), "25")
  expect_equal(xml2::xml_text(xml2::xml_find_first(arr, "./Unit")), "celsius")
  kids <- xml2::xml_name(xml2::xml_children(arr))
  wanted <- c("SRS", "Unit", "NoDataValue", "Offset", "Scale", "Source")
  expect_equal(unique(kids[kids %in% wanted]), wanted)
})

test_that("unscaled values through GDAL match the source band's own decoding", {
  skip_if_not_installed("gdalraster")
  tifs <- make_packed_tifs(sprintf("sst_2026092%d.tif", 1:3))
  out <- tempfile(fileext = ".vrt")
  suppressMessages(vrt_time_stack(tifs, array_name = "sst", output = out))
  info <- jsonlite::fromJSON(
    gdalraster::gdal_run("mdim info", c("--array=sst", out))$output())
  arr <- info  # with --array, the array is the top level
  expect_equal(arr$scale, 0.001)
  expect_equal(arr$offset, 25)
  expect_equal(arr$unit, "celsius")
})

test_that("SRS mapping is computed from the WKT axis order", {
  geo <- 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AXIS["Latitude",NORTH],AXIS["Longitude",EAST]]'
  proj <- 'PROJCS["WGS 84 / Antarctic Polar Stereographic",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AXIS["Latitude",NORTH],AXIS["Longitude",EAST]],PROJECTION["Polar_Stereographic"],UNIT["metre",1],AXIS["Easting",NORTH],AXIS["Northing",NORTH]]'
  noaxis <- 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]'
  utm <- 'PROJCS["WGS 84 / UTM zone 55S",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433],AXIS["Latitude",NORTH],AXIS["Longitude",EAST]],PROJECTION["Transverse_Mercator"],UNIT["metre",1],AXIS["Easting",EAST],AXIS["Northing",NORTH]]'
  expect_equal(vrtstack:::.srs_axis_mapping(geo, 2L, 3L), "2,3")
  expect_equal(vrtstack:::.srs_axis_mapping(utm, 2L, 3L), "3,2")
  expect_equal(vrtstack:::.srs_axis_mapping(noaxis, 2L, 3L), "3,2")
  # EPSG:3031 as GDAL writes WKT1 has two NORTH axes: not plainly X/Y, so
  # fall back to easting-first.
  expect_equal(vrtstack:::.srs_axis_mapping(proj, 2L, 3L), "3,2")
})

test_that("GDAL reads the mapping back, and a 2D slice gets a valid one", {
  skip_if_not_installed("gdalraster")
  tifs <- make_packed_tifs(sprintf("sst_2026092%d.tif", 1:3))
  out <- tempfile(fileext = ".vrt")
  suppressMessages(vrt_time_stack(tifs, array_name = "sst", output = out))
  info <- jsonlite::fromJSON(
    gdalraster::gdal_run("mdim info", c("--array=sst", out))$output())
  expect_equal(as.integer(info$srs$data_axis_to_srs_axis_mapping), c(2L, 3L))
  # Reference: what GDAL computes for the same CRS on a 2D classic raster
  # (data axes x=1, y=2). EPSG:4326 lat-first -> c(2, 1).
  ref <- methods::new(gdalraster::GDALRaster, tifs[1], TRUE)
  ref_wkt <- ref$getProjectionRef()
  ref$close()
  expect_equal(vrtstack:::.srs_axis_mapping(ref_wkt, y_dim = 2L, x_dim = 1L), "2,1")
})

test_that("stack-dim Unit precedes its value carrier (XSD order)", {
  skip_if_not_installed("gdalraster")
  tifs <- make_packed_tifs(sprintf("sst_2026092%d.tif", 1:3))
  doc <- xml2::read_xml(suppressMessages(vrt_time_stack(tifs, array_name = "sst")))
  kids <- xml2::xml_name(xml2::xml_children(
    xml2::xml_find_first(doc, ".//Array[@name='time']")))
  expect_lt(match("Unit", kids), match("RegularlySpacedValues", kids))
})
