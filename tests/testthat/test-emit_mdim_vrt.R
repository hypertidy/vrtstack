# Baseline for the signature/sources -> mdim VRT emitter.

emit_to_doc <- function(src, sig) {
  p <- tempfile(fileext = ".vrt")
  emit_mdim_vrt(src, sig, p)
  xml2::read_xml(p)
}

band_src <- function() {
  mdim_sources(time = as.Date(c("2024-01-02", "2024-01-01")),
               dsn = c("/vsicurl/b.tif", "/vsicurl/a.tif"),
               source_ref = "1", kind = "band",
               source_view = "[newaxis,...]")
}

base_sig <- function(...) {
  mdim_signature("demo", "sst", 8L, 6L, 0.125, 0.25, 89.875, -0.25,
                 "EPSG:4326", "Int16", ...)
}

test_that("steps are ordered by time and dimensions are stamped", {
  doc <- emit_to_doc(band_src(), base_sig())
  tv <- xml2::xml_text(xml2::xml_find_all(
    doc, ".//Array[@name='time']/InlineValuesWithValueElement/Value"))
  expect_equal(tv, c("2024-01-01", "2024-01-02"))
  expect_equal(
    xml2::xml_attr(xml2::xml_find_first(doc, ".//Dimension[@name='time']"), "size"), "2")
  expect_equal(
    xml2::xml_attr(xml2::xml_find_first(doc, ".//Dimension[@name='Y']"), "size"), "6")
  expect_equal(
    xml2::xml_attr(xml2::xml_find_first(doc, ".//Dimension[@name='X']"), "size"), "8")
})

test_that("band sources carry SourceBand, SourceView and stepped DestSlabs", {
  doc <- emit_to_doc(band_src(), base_sig())
  src <- xml2::xml_find_all(doc, ".//Array[@name='sst']/Source")
  expect_length(src, 2)
  # sorted by dest_index, so a.tif (earlier date) comes first
  expect_equal(xml2::xml_text(xml2::xml_find_all(src, "./SourceFilename")),
               c("/vsicurl/a.tif", "/vsicurl/b.tif"))
  expect_equal(xml2::xml_text(xml2::xml_find_all(src, "./SourceBand")), c("1", "1"))
  expect_equal(xml2::xml_text(xml2::xml_find_all(src, "./SourceView")),
               c("[newaxis,...]", "[newaxis,...]"))
  expect_equal(xml2::xml_attr(xml2::xml_find_all(src, "./DestSlab"), "offset"),
               c("0,0,0", "1,0,0"))
})

test_that("array-kind sources emit SourceArray", {
  s <- mdim_sources(as.Date(c("2024-01-01", "2024-01-02")),
                    c("/vsicurl/a.nc", "/vsicurl/b.nc"),
                    "/sst", "array", source_view = "[:,0,:,:]")
  doc <- emit_to_doc(s, base_sig())
  sa <- xml2::xml_find_all(doc, ".//Array[@name='sst']/Source/SourceArray")
  expect_length(sa, 2)
  expect_true(all(xml2::xml_text(sa) == "/sst"))
})

test_that("optional array metadata is emitted only when present", {
  with_meta <- emit_to_doc(
    band_src(), base_sig(nodata = -999, scale = 0.01, offset = 0, unit = "Celsius"))
  expect_equal(
    xml2::xml_text(xml2::xml_find_first(with_meta, ".//Array[@name='sst']/NoDataValue")), "-999")
  expect_equal(
    xml2::xml_text(xml2::xml_find_first(with_meta, ".//Array[@name='sst']/Unit")), "Celsius")

  bare <- emit_to_doc(band_src(), base_sig())
  expect_true(inherits(
    xml2::xml_find_first(bare, ".//Array[@name='sst']/NoDataValue"), "xml_missing"))
  expect_true(inherits(
    xml2::xml_find_first(bare, ".//Array[@name='sst']/Unit"), "xml_missing"))
})

test_that("a multi-step file contributes a single Source", {
  s <- mdim_sources(
    time = as.Date(c("2024-01-01", "2024-01-02", "2024-01-03")),
    dsn = c("/vsicurl/multi.nc", "/vsicurl/multi.nc", "/vsicurl/single.nc"),
    source_ref = "/sst", kind = "array", source_view = "[:,0,:,:]")
  doc <- emit_to_doc(s, base_sig())
  src <- xml2::xml_find_all(doc, ".//Array[@name='sst']/Source")
  expect_length(src, 2)
  expect_equal(xml2::xml_text(xml2::xml_find_all(src, "./SourceFilename")),
               c("/vsicurl/multi.nc", "/vsicurl/single.nc"))
})

test_that("an emitted VRT opens in GDAL with the declared grid and metadata", {
  skip_if_no_gdal_cli()                           # verify_vrt needs gdal_run
  skip_if_not_installed("jsonlite")
  tifs <- make_tifs(c("a.tif", "b.tif"))          # 8x6 Int16 sources
  s <- mdim_sources(as.Date(c("2024-01-02", "2024-01-01")),
                    tifs[c(2, 1)], "1", "band", source_view = "[newaxis,...]")
  vrt <- tempfile(fileext = ".vrt")
  emit_mdim_vrt(s, base_sig(nodata = -999, unit = "Celsius"), vrt)

  info <- jsonlite::fromJSON(skip_on_gdal_cli_error(verify_vrt(vrt)),
                             simplifyVector = FALSE)
  expect_equal(info$driver, "VRT")

  sst <- info$arrays$sst
  expect_equal(sst$datatype, "Int16")
  expect_equal(unlist(sst$dimensions), c("/time", "/Y", "/X"))
  expect_equal(unlist(sst$dimension_size), c(2L, 6L, 8L))
  expect_equal(sst$unit, "Celsius")
  expect_equal(sst$nodata_value, -999)
})

test_that("verify_vrt returns mdim info for a valid VRT", {
  skip_if_no_gdal_cli()                           # verify_vrt needs gdal_run
  tifs <- make_tifs(c("v1.tif", "v2.tif"))
  s <- mdim_sources(as.Date(c("2024-01-01", "2024-01-02")),
                    tifs, "1", "band", source_view = "[newaxis,...]")
  vrt <- tempfile(fileext = ".vrt")
  emit_mdim_vrt(s, base_sig(), vrt)
  expect_match(skip_on_gdal_cli_error(verify_vrt(vrt)), "\"driver\": \"VRT\"")
})
