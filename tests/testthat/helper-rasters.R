# Small on-disk GeoTIFFs to exercise the file-probing paths without network.
# EPSG:4326, 0.25-degree grid, single Int16 band, optional NoData.
make_tifs <- function(names,
                      dir = tempfile("vrtstack-tests"),
                      nx = 8L, ny = 6L, nodata = -999) {
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dir, names)
  for (i in seq_along(paths)) {
    gdalraster::create(format = "GTiff", dst_filename = paths[i],
                       xsize = nx, ysize = ny, nbands = 1L,
                       dataType = "Int16")
    ds <- methods::new(gdalraster::GDALRaster, paths[i], read_only = FALSE)
    ds$setGeoTransform(c(0, 0.25, 0, 90, 0, -0.25))
    ds$setProjection(gdalraster::epsg_to_wkt(4326))
    if (!is.na(nodata)) ds$setNoDataValue(1L, nodata)
    ds$write(band = 1L, 0L, 0L, nx, ny,
             matrix(as.integer(i * seq_len(nx * ny)), ny, nx))
    ds$close()
  }
  paths
}

# A minimal multidimensional-VRT recipe (time, y, x) with SourceArray sources,
# used to exercise mdim_template_extend() without touching GDAL.
template_xml <- function() {
  paste(
    '<VRTDataset>',
    '  <Group name="/">',
    '    <Dimension name="time" size="2"/>',
    '    <Dimension name="y" size="4"/>',
    '    <Dimension name="x" size="5"/>',
    '    <Array name="time">',
    '      <DataType>Float64</DataType>',
    '      <DimensionRef ref="time"/>',
    '      <InlineValues>0 1</InlineValues>',
    '    </Array>',
    '    <Array name="sst">',
    '      <DataType>Int16</DataType>',
    '      <DimensionRef ref="time"/>',
    '      <DimensionRef ref="y"/>',
    '      <DimensionRef ref="x"/>',
    '      <Source>',
    '        <SourceFilename>a.nc</SourceFilename>',
    '        <SourceArray>/sst</SourceArray>',
    '        <SourceSlab offset="0,0,0" count="1,4,5" step="1,1,1"/>',
    '        <DestSlab offset="0,0,0"/>',
    '      </Source>',
    '      <Source>',
    '        <SourceFilename>b.nc</SourceFilename>',
    '        <SourceArray>/sst</SourceArray>',
    '        <SourceSlab offset="0,0,0" count="1,4,5" step="1,1,1"/>',
    '        <DestSlab offset="1,0,0"/>',
    '      </Source>',
    '    </Array>',
    '  </Group>',
    '</VRTDataset>', sep = "\n")
}
