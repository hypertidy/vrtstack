# Baseline for the STAC sufficiency checklist (pure R, no HTTP, no GDAL).

test_that("fields are located across item properties and assets", {
  item <- list(
    properties = list(
      "proj:epsg" = 4326L,
      "proj:shape" = c(720L, 1440L),
      "proj:transform" = c(0.25, 0, -180, 0, -0.25, 90),
      start_datetime = "2024-01-02T00:00:00Z",
      end_datetime = "2024-01-02T23:59:59Z"),
    assets = list(
      sst = list("raster:bands" = list(list(scale = 0.01, nodata = -999)))))

  rep <- stac_sufficiency(item, asset = "sst")
  expect_s3_class(rep, "data.frame")
  loc <- setNames(rep$found_at, rep$field)

  expect_equal(loc[["proj:epsg"]], "item-properties")
  expect_equal(loc[["raster:bands"]], "asset")
  expect_equal(loc[["start_datetime"]], "item-properties")
  # proj:code and datetime are legitimately absent here
  expect_equal(loc[["proj:code"]], "absent")
  expect_equal(loc[["datetime"]], "absent")
})

test_that("without an asset, only item-level properties are consulted", {
  item <- list(properties = list("proj:epsg" = 4326L),
               assets = list(sst = list("raster:bands" = list())))
  rep <- stac_sufficiency(item)          # no asset
  loc <- setNames(rep$found_at, rep$field)
  expect_equal(loc[["proj:epsg"]], "item-properties")
  expect_equal(loc[["raster:bands"]], "absent")
})
