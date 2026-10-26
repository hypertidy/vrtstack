# Regression baseline for the convenience wrappers (needs GDAL).

test_that("vrt_time_stack produces a TEMPORAL dimension", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("temp_20230101.tif", "temp_20230102.tif"))
  doc <- xml2::read_xml(suppressMessages(vrt_time_stack(tifs)))
  dn <- xml2::xml_find_first(doc, ".//Dimension[@name='time']")
  expect_equal(xml2::xml_attr(dn, "type"), "TEMPORAL")
})

test_that("vrt_depth_stack produces a VERTICAL/DOWN dimension", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("s_0.tif", "s_30.tif", "s_100.tif"))
  doc <- xml2::read_xml(
    suppressMessages(vrt_depth_stack(tifs, values = c(0, 30, 100), unit = "cm")))
  dn <- xml2::xml_find_first(doc, ".//Dimension[@name='depth']")
  expect_equal(xml2::xml_attr(dn, "type"), "VERTICAL")
  expect_equal(xml2::xml_attr(dn, "direction"), "DOWN")
})

test_that("vrt_regular_stack uses a regularly spaced axis", {
  skip_if_not_installed("gdalraster")
  tifs <- make_tifs(c("p_1.tif", "p_2.tif", "p_3.tif"))
  doc <- xml2::read_xml(
    suppressMessages(vrt_regular_stack(tifs, dim_name = "month",
                                       start = 1, increment = 1)))
  rsv <- xml2::xml_find_first(doc, ".//Array[@name='month']/RegularlySpacedValues")
  expect_equal(xml2::xml_attr(rsv, "start"), "1")
})
