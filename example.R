files <- arrow::read_parquet("https://data.source.coop/ausantarctic/ghrsst-mur-v2/ghrsst-mur-v2.parquet")
st <- vrt_time_stack(sprintf("/vsicurl/%s", files$assets$analysed_sst$href[1:2]), array_name = "analysed_sst")
cat(st)

## now do the whole set
st <- vrt_time_stack(sprintf("/vsicurl/%s", files$assets$analysed_sst$href), array_name = "analysed_sst")

library(reticulate)
use_python("/usr/bin/python3")
gdal <- import("osgeo.gdal")
gdal$UseExceptions()
ds <- gdal$OpenEx(st, gdal$OF_MULTIDIM_RASTER)
rg <- ds$GetRootGroup()
arr <- rg$OpenMDArray("analysed_sst")
nd <- arr$GetDimensionCount()
for (i in seq_len(nd)) {
  dm <- arr$GetDimensions()[[i]]
  print(dm$GetFullName())
  print(dm$GetSize())

}

# [1] "/time"
# [1] 8717
# [1] "/y"
# [1] 17999
# [1] "/x"
# [1] 36000


print(ivar <- dm$GetIndexingVariable())
#<osgeo.gdal.MDArray; proxy of <Swig Object of type 'GDALMDArrayHS *' at 0x73c8bebca0d0> >

spec <- "[0:2,8000:8100,0:200]"
arr$AdviseRead(c(0L, 8000L, 0L), c(2L, 100L, 200L))
v <- arr$GetView(spec)
m <- v$ReadAsArray()
dim(m)
#[1]   2 100 200

ximage::ximage(m[1,,])
