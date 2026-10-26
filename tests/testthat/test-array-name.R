# The data array name is derived from the shared part of the file names, which
# carries the variable; the varying part is the index (a date, a depth). A
# shared part that is only a date must not become a numeric, invalid name.

test_that("array name is the variable token from the shared part of the names", {
  ghrsst <- c(
    "20020601090000-JPL-L4_GHRSST-SSTfnd-MUR-GLOB-v02.0-fv04.1_analysed_sst.tif",
    "20020602090000-JPL-L4_GHRSST-SSTfnd-MUR-GLOB-v02.0-fv04.1_analysed_sst.tif"
  )
  expect_equal(.array_name_from_files(ghrsst), "analysed_sst")
  expect_equal(
    .array_name_from_files(c("claytotal_0_cm.tif", "claytotal_5_cm.tif")),
    "claytotal"
  )
  expect_equal(
    .array_name_from_files(c("temp_20230101.tif", "temp_20230102.tif")),
    "temp"
  )
})

test_that("a date-only shared part yields band1, never a numeric name", {
  nm <- .array_name_from_files(c("20020601.tif", "20020602.tif"))
  expect_equal(nm, "band1")
  expect_false(grepl("^[0-9]", nm))
})

test_that("the result is always a valid identifier", {
  for (f in list(
    c("20020601.tif", "20020602.tif"),
    c("a.tif"),
    c("claytotal_0_cm.tif", "claytotal_5_cm.tif")
  )) {
    expect_match(.array_name_from_files(f), "^[A-Za-z][A-Za-z0-9_]*$")
  }
})
