# The concat dimension need not be named "time" nor sit at axis 0. The extender
# takes the axis position from DimensionRef order, so a source list is rebuilt
# with the per-file slab incrementing on whichever axis the concat dim occupies.
# Pure xml2 rewrite -- no GDAL needed.

zlev_template <- function() {
  paste(
    '<VRTDataset><Group name="/">',
    '  <Dimension name="time" size="1"/>',
    '  <Dimension name="zlev" size="2"/>',
    '  <Dimension name="y" size="3"/>',
    '  <Dimension name="x" size="4"/>',
    '  <Array name="zlev"><DataType>Float64</DataType>',
    '    <DimensionRef ref="zlev"/><InlineValues>0 10</InlineValues></Array>',
    '  <Array name="v"><DataType>Int16</DataType>',
    '    <DimensionRef ref="time"/><DimensionRef ref="zlev"/>',
    '    <DimensionRef ref="y"/><DimensionRef ref="x"/>',
    '    <Source><SourceFilename>a.nc</SourceFilename><SourceArray>/v</SourceArray>',
    '      <SourceSlab offset="0,0,0,0" count="1,1,3,4" step="1,1,1,1"/>',
    '      <DestSlab offset="0,0,0,0"/></Source>',
    '    <Source><SourceFilename>b.nc</SourceFilename><SourceArray>/v</SourceArray>',
    '      <SourceSlab offset="0,0,0,0" count="1,1,3,4" step="1,1,1,1"/>',
    '      <DestSlab offset="0,1,0,0"/></Source>',
    '  </Array>',
    '</Group></VRTDataset>',
    sep = "\n"
  )
}

test_that("a non-axis-0, non-time concat dimension extends on its own axis", {
  files <- c("d0.nc", "d1.nc", "d2.nc")
  doc <- mdim_template_extend(zlev_template(), files,
                              concat_values = c(0, 10, 20), concat_dim = "zlev")

  grp <- xml2::xml_find_first(doc, ".//Group")
  expect_equal(xml2::xml_attr(
    xml2::xml_find_first(grp, "./Dimension[@name='zlev']"), "size"), "3")
  expect_equal(xml2::xml_text(xml2::xml_find_first(
    grp, "./Array[@name='zlev']/InlineValues")), "0 10 20")

  srcs <- xml2::xml_find_all(grp, "./Array[@name='v']/Source")
  expect_length(srcs, 3L)
  # slab increments on axis 1 (zlev), not axis 0 (time)
  expect_equal(
    xml2::xml_attr(xml2::xml_find_all(grp, "./Array[@name='v']//DestSlab"), "offset"),
    c("0,0,0,0", "0,1,0,0", "0,2,0,0")
  )
  expect_equal(
    xml2::xml_text(xml2::xml_find_all(grp, "./Array[@name='v']/Source/SourceFilename")),
    files
  )
  # per-source slab geometry carried from the prototype, unchanged
  expect_true(all(xml2::xml_attr(
    xml2::xml_find_all(grp, "./Array[@name='v']//SourceSlab"), "count") == "1,1,3,4"))
})

test_that("the concat dimension is found by size when the name is absent", {
  # drop the name hint: concat_dim defaults to "time" (size 1), which does not
  # match; the fallback picks the dimension whose size equals the source count.
  doc <- mdim_template_extend(zlev_template(), c("d0.nc", "d1.nc"),
                              concat_values = c(0, 10))
  grp <- xml2::xml_find_first(doc, ".//Group")
  # the size-2 dimension (zlev) is the one whose size matches the source count
  expect_equal(xml2::xml_attr(
    xml2::xml_find_first(grp, "./Dimension[@name='zlev']"), "size"), "2")
})
