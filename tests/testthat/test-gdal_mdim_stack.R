# Regression baseline for the file-probing from-scratch builder (needs GDAL).

test_that("regular spacing is detected and stored compactly", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("clay_0.tif", "clay_5.tif", "clay_10.tif"))
  xml <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "depth",
                    dim_values = c(0, 5, 10), dim_unit = "cm"))
  doc <- xml2::read_xml(xml)

  dn <- xml2::xml_find_first(doc, ".//Dimension[@name='depth']")
  expect_equal(xml2::xml_attr(dn, "size"), "3")

  rsv <- xml2::xml_find_first(doc, ".//Array[@name='depth']/RegularlySpacedValues")
  expect_false(inherits(rsv, "xml_missing"))
  expect_equal(xml2::xml_attr(rsv, "increment"), "5")
})

test_that("array name is the shared token of the file names", {
  # the variable token comes from the shared part of the names (here the
  # prefix "clay"); the differing part is the index.
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("clay_0.tif", "clay_5.tif", "clay_10.tif"))
  xml <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "depth", dim_values = c(0, 5, 10)))
  doc <- xml2::read_xml(xml)
  expect_false(
    inherits(xml2::xml_find_first(doc, ".//Array[@name='clay']"), "xml_missing"))
})

test_that("sources use SourceBand + SourceTranspose with stepped DestSlabs", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("clay_0.tif", "clay_5.tif", "clay_10.tif"))
  xml <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "depth", dim_values = c(0, 5, 10)))
  doc <- xml2::read_xml(xml)

  src <- xml2::xml_find_all(doc, ".//Array[@name='clay']/Source")
  expect_length(src, 3)
  expect_equal(xml2::xml_text(xml2::xml_find_all(src, "./SourceBand")),
               rep("1", 3))
  expect_equal(xml2::xml_text(xml2::xml_find_all(src, "./SourceTranspose")),
               rep("-1,0,1", 3))
  expect_equal(xml2::xml_attr(xml2::xml_find_all(src, "./DestSlab"), "offset"),
               c("0,0,0", "1,0,0", "2,0,0"))
})

test_that("SRS carries the data-axis-to-SRS-axis mapping, and NoData is set", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("clay_0.tif", "clay_5.tif", "clay_10.tif"))
  xml <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "depth", dim_values = c(0, 5, 10)))
  doc <- xml2::read_xml(xml)

  srs <- xml2::xml_find_first(doc, ".//Array[@name='clay']/SRS")
  expect_equal(xml2::xml_attr(srs, "dataAxisToSRSAxisMapping"), "2,1")
  nd <- xml2::xml_find_first(doc, ".//Array[@name='clay']/NoDataValue")
  expect_equal(xml2::xml_text(nd), "-999")
})

test_that("irregular values fall back to InlineValues", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("d_0.tif", "d_5.tif", "d_20.tif"))
  xml <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "depth", dim_values = c(0, 5, 20)))
  doc <- xml2::read_xml(xml)
  iv <- xml2::xml_find_first(doc, ".//Array[@name='depth']/InlineValues")
  expect_false(inherits(iv, "xml_missing"))
})

test_that("temporal dim carries type and a 'unit since origin' string", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("t_20240101.tif", "t_20240102.tif"))
  xml <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "time", dim_values = "(\\d{8})",
                    parse_format = "%Y%m%d", dim_type = "TEMPORAL",
                    time_origin = "2024-01-01", time_unit = "days"))
  doc <- xml2::read_xml(xml)
  dn <- xml2::xml_find_first(doc, ".//Dimension[@name='time']")
  expect_equal(xml2::xml_attr(dn, "type"), "TEMPORAL")
  u <- xml2::xml_find_first(doc, ".//Array[@name='time']/Unit")
  expect_equal(xml2::xml_text(u), "days since 2024-01-01")
})

test_that("output path is written and the VRT opens as multidim", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("m_1.tif", "m_2.tif", "m_3.tif"))
  out <- tempfile(fileext = ".vrt")
  res <- suppressMessages(
    gdal_mdim_stack(tifs, dim_name = "time",
                    dim_start = 1, dim_increment = 1, output = out))
  expect_equal(res, out)
  expect_true(file.exists(out))
  # opening via `gdal mdim info` is covered in test-emit_mdim_vrt.R, which
  # guards the GDAL-CLI capability; kept out here so this file runs on any
  # GDAL (the builder itself uses only the classic raster API).
})
