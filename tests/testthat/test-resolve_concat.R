# Regression baseline for the shared concat-axis resolver (pure R, no GDAL).

test_that("NULL concat resolves to NULL", {
  expect_null(resolve_concat(c("a", "b"), NULL))
})

test_that("explicit vector passes through, with a length check", {
  expect_equal(resolve_concat(c("a", "b"), c(10, 20)), c(10, 20))
  expect_error(resolve_concat(c("a", "b"), c(10, 20, 30)))
})

test_that("a function is applied to basenames", {
  files <- c("dir/x1.tif", "dir/x2.tif")
  expect_equal(
    resolve_concat(files, function(b) as.numeric(gsub("\\D", "", b))),
    c(1, 2))
})

test_that("single-group regex extracts numeric values in file order", {
  files <- c("t_0.tif", "t_5.tif", "t_10.tif")
  expect_equal(resolve_concat(files, "_(\\d+)\\."), c(0, 5, 10))
})

test_that("regex + parse_format + origin/unit gives day offsets", {
  files <- c("s_20240101.tif", "s_20240103.tif")
  expect_equal(
    resolve_concat(files, "(\\d{8})", parse_format = "%Y%m%d",
                   origin = "2024-01-01", unit = "days"),
    c(0, 2))
})

test_that("a non-matching regex errors informatively", {
  expect_error(resolve_concat("nope.tif", "(\\d{8})"), "did not match")
})
