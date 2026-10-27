# Regression baseline for the pure-xml2 template-extend rewrite (no GDAL).

test_that("dimension size and per-array source count follow the file set", {
  doc <- mdim_template_extend(template_xml(),
                              files = c("f1.nc", "f2.nc", "f3.nc"),
                              concat_values = c(10, 20, 30))
  grp <- xml2::xml_find_first(doc, ".//Group")
  dn <- xml2::xml_find_first(grp, "./Dimension[@name='time']")
  expect_equal(xml2::xml_attr(dn, "size"), "3")
  srcs <- xml2::xml_find_all(grp, "./Array[@name='sst']/Source")
  expect_length(srcs, 3)
  expect_equal(
    xml2::xml_text(xml2::xml_find_all(srcs, "./SourceFilename")),
    c("f1.nc", "f2.nc", "f3.nc"))
})

test_that("concat coordinate values are rewritten", {
  doc <- mdim_template_extend(template_xml(), c("f1.nc", "f2.nc", "f3.nc"),
                              concat_values = c(10, 20, 30))
  iv <- xml2::xml_find_first(doc, ".//Array[@name='time']/InlineValues")
  expect_equal(xml2::xml_text(iv), "10 20 30")
})

test_that("DestSlab offsets increment along the concat axis", {
  doc <- mdim_template_extend(template_xml(), c("f1.nc", "f2.nc", "f3.nc"),
                              concat_values = c(10, 20, 30))
  ds <- xml2::xml_find_all(doc, ".//Array[@name='sst']/Source/DestSlab")
  expect_equal(xml2::xml_attr(ds, "offset"), c("0,0,0", "1,0,0", "2,0,0"))
})

test_that("SourceArray path and slab geometry are carried from the prototype", {
  doc <- mdim_template_extend(template_xml(), c("f1.nc", "f2.nc"),
                              concat_values = c(10, 20))
  sslab <- xml2::xml_find_all(doc, ".//Array[@name='sst']/Source/SourceSlab")
  expect_true(all(xml2::xml_attr(sslab, "count") == "1,4,5"))
  expect_true(all(xml2::xml_attr(sslab, "step") == "1,1,1"))
  sa <- xml2::xml_find_all(doc, ".//Array[@name='sst']/Source/SourceArray")
  expect_true(all(xml2::xml_text(sa) == "/sst"))
})

test_that("NULL concat_values keeps template values when the length matches", {
  doc <- mdim_template_extend(template_xml(), c("f1.nc", "f2.nc"),
                              concat_values = NULL)
  iv <- xml2::xml_find_first(doc, ".//Array[@name='time']/InlineValues")
  expect_equal(xml2::xml_text(iv), "0 1")
  expect_length(xml2::xml_find_all(doc, ".//Array[@name='sst']/Source"), 2)
})

test_that("NULL concat_values errors when template length disagrees", {
  expect_error(
    mdim_template_extend(template_xml(), c("f1.nc", "f2.nc", "f3.nc"),
                         concat_values = NULL),
    "do not match")
})

test_that("Date/POSIXct concat_values are rejected", {
  expect_error(
    mdim_template_extend(template_xml(), c("f1.nc", "f2.nc"),
                         concat_values = as.Date(c("2024-01-01", "2024-01-02"))),
    "Date/POSIX")
})
