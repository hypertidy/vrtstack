# The grafts repair metadata that `gdal mdim mosaic` drops. They are exercised
# here through the units=/attrs= bypass, so no GDAL is needed: the XML rewrite
# is what is under test.

mini_vrt <- function() {
  paste(
    '<VRTDataset>',
    '  <Group name="/">',
    '    <Dimension name="time" size="2"/>',
    '    <Array name="time">',
    '      <DataType>Float64</DataType>',
    '      <DimensionRef ref="time"/>',
    '      <InlineValues>1339 1340</InlineValues>',
    '    </Array>',
    '    <Array name="sst">',
    '      <DataType>Float64</DataType>',
    '      <DimensionRef ref="time"/>',
    '      <Unit>Celsius</Unit>',
    '      <Source>',
    '        <SourceFilename>a.nc</SourceFilename>',
    '        <SourceArray>/sst</SourceArray>',
    '      </Source>',
    '    </Array>',
    '  </Group>',
    '</VRTDataset>',
    sep = "\n"
  )
}

test_that("graft_coord_units adds <Unit> to coordinate arrays only", {
  doc  <- graft_coord_units(mini_vrt(), units = c(time = "days since 1978-01-01"))
  time <- xml2::xml_find_first(doc, ".//Array[@name='time']")
  sst  <- xml2::xml_find_first(doc, ".//Array[@name='sst']")

  expect_equal(xml2::xml_text(xml2::xml_find_first(time, "./Unit")),
               "days since 1978-01-01")
  # the data array already had a Unit; it must not gain a second one
  expect_length(xml2::xml_find_all(sst, "./Unit"), 1L)
  expect_equal(xml2::xml_text(xml2::xml_find_first(sst, "./Unit")), "Celsius")
  # coordinate values untouched
  expect_equal(xml2::xml_text(xml2::xml_find_first(time, "./InlineValues")),
               "1339 1340")
})

test_that("graft_coord_units is idempotent (leaves an existing unit alone)", {
  once  <- graft_coord_units(mini_vrt(), units = c(time = "u"))
  twice <- graft_coord_units(once,       units = c(time = "DIFFERENT"))
  time  <- xml2::xml_find_first(twice, ".//Array[@name='time']")
  expect_length(xml2::xml_find_all(time, "./Unit"), 1L)
  expect_equal(xml2::xml_text(xml2::xml_find_first(time, "./Unit")), "u")
})

test_that("graft_group_attrs adds provenance, skips Conventions and per-file fields", {
  doc <- graft_group_attrs(mini_vrt(), attrs = c(
    title             = "OISST",
    source            = "AVHRR",
    Conventions       = "CF-1.6",
    time_coverage_end = "1981-09-01"
  ))
  grp   <- xml2::xml_find_first(doc, ".//Group")
  names <- xml2::xml_attr(xml2::xml_find_all(grp, "./Attribute"), "name")

  expect_true(all(c("title", "source") %in% names))
  expect_false("Conventions" %in% names)        # the writer stamps its own
  expect_false("time_coverage_end" %in% names)  # per-file, meaningless stacked
})

test_that("grafts need either a source or the bypass argument", {
  expect_error(graft_coord_units(mini_vrt()))
  expect_error(graft_group_attrs(mini_vrt()))
})
