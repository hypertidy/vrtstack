# metadata_from selects which source donates the restored units and provenance
# on an auto-generated recipe. The selection is pure; the subsequent read needs
# GDAL, so only the resolver is exercised here.

test_that(".resolve_donor picks first, last, or an explicit path", {
  files <- c("a.nc", "b.nc", "c.nc")
  expect_equal(.resolve_donor(files, "first"), "a.nc")
  expect_equal(.resolve_donor(files, "last"), "c.nc")
  expect_equal(.resolve_donor(files, "/some/other/ref.nc"), "/some/other/ref.nc")
  # default is first
  expect_equal(.resolve_donor(files), "a.nc")
})

test_that(".resolve_donor rejects a non-scalar or empty spec", {
  files <- c("a.nc", "b.nc")
  expect_error(.resolve_donor(files, c("first", "last")))
  expect_error(.resolve_donor(files, ""))
  expect_error(.resolve_donor(files, NA_character_))
})
