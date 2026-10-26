# A source without a <SourceSlab> count makes GDAL open every source, in
# order, to learn its shape on each read through the VRT. With the count,
# a read opens only the sources it touches.

temp_dir <- function() {
  d <- tempfile("vrtstack-")
  dir.create(d)
  d
}

make_stack <- function(dir, ny = 5L, nx = 7L, nt = 6L) {
  files <- file.path(dir, sprintf("f%d.tif", seq_len(nt) - 1L))
  for (t in seq_len(nt)) {
    gdalraster::create("GTiff", files[t], nx, ny, 1L, "Float32", return_obj = FALSE)
    ds <- methods::new(gdalraster::GDALRaster, files[t], read_only = FALSE)
    ds$setGeoTransform(c(0, 1, 0, ny, 0, -1))
    # row-major values, offset by 100 per step, so each step is distinct
    v <- matrix(seq_len(ny * nx) - 1 + 100 * (t - 1), nrow = ny, byrow = TRUE)
    ds$write(1L, 0L, 0L, nx, ny, as.vector(t(v)))
    ds$close()
  }
  list(files = files, ny = ny, nx = nx)
}

read_step <- function(vrt, t, ny, nx) {
  # the view drops the stack axis, leaving (y, x) as dimensions 0 and 1
  r <- gdalraster::mdim_as_classic(vrt, "v", idx_xdim = 1L, idx_ydim = 0L,
                                   view_expr = sprintf("[%d,:,:]", t))
  on.exit(r$close())
  r$read(1L, 0L, 0L, nx, ny, nx, ny)
}

test_that("each source carries a SourceSlab count in (stack, y, x) order", {
  dir <- temp_dir()
  s <- make_stack(dir)
  xml <- gdal_mdim_stack(s$files, "t", dim_start = 0, dim_increment = 1,
                         array_name = "v")
  slabs <- regmatches(xml, gregexpr("<SourceSlab[^>]*>", xml))[[1]]
  expect_length(slabs, length(s$files))
  expect_true(all(grepl(sprintf('count="1,%d,%d"', s$ny, s$nx), slabs, fixed = TRUE)))
})

test_that("reading one step needs only that step's file", {
  dir <- temp_dir()
  s <- make_stack(dir)
  vrt <- file.path(dir, "stack.vrt")
  gdal_mdim_stack(s$files, "t", dim_start = 0, dim_increment = 1,
                  array_name = "v", output = vrt)
  # every source but step 3 removed: without the count GDAL fails on f0.tif
  file.remove(s$files[-4])
  got <- read_step(vrt, 3L, s$ny, s$nx)
  expect_equal(got, seq_len(s$ny * s$nx) - 1 + 300)
})
