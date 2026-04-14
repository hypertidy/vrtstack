#' Stack Time Series Rasters into Multidimensional VRT
#'
#' A convenience wrapper for [gdal_mdim_stack()] tailored for time series data.
#' Extracts dates from filenames and encodes them as numeric offsets from an origin.
#'
#' @param files Character vector of file paths
#' @param pattern Regex pattern with one capturing group for the date portion.
#'   Default: `"(\\d{8})"` matches 8-digit dates like `20230115`.
#' @param format strptime format for parsing. Default: `"%Y%m%d"`
#' @param origin Time origin as `"YYYY-MM-DD"` string. Default: `"1970-01-01"`
#' @param unit Time unit: `"days"`, `"hours"`, `"minutes"`, `"seconds"`.
#'   Default: `"days"`
#' @param array_name Name for the data array
#' @param output Output VRT path
#'
#' @return Path to VRT file (invisibly), or XML string if `output` is NULL.
#'
#' @export
#'
#' @examples
#' \dontrun
#' # Daily temperature files: temp_20230101.tif, temp_20230102.tif, ...
#' vrt_time_stack(
#'   files = list.files(pattern = "temp_\\d{8}\\.tif$"),
#'   output = "temperature_timeseries.vrt"
#' )
#'
#' # Custom pattern for ISO dates: data_2023-01-15.tif
#' vrt_time_stack(
#'   files = my_files,
#'   pattern = "(\\d{4}-\\d{2}-\\d{2})",
#'   format = "%Y-%m-%d",
#'   output = "timeseries.vrt"
#' )
#' }
vrt_time_stack <- function(
    files,
    pattern = "(\\d{8})",
    format = "%Y%m%d",
    origin = "1970-01-01",
    unit = "days",
    array_name = NULL,
    output = NULL
) {
  gdal_mdim_stack(
    files = files,
    dim_name = "time",
    dim_values = pattern,
    parse_format = format,
    dim_type = "TEMPORAL",
    time_origin = origin,
    time_unit = unit,
    array_name = array_name,
    output = output
  )
}


#' Stack Rasters by Depth/Level into Multidimensional VRT
#'
#' A convenience wrapper for [gdal_mdim_stack()] for vertical profile data
#' (soil layers, atmospheric levels, ocean depths, etc.)
#'
#' @param files Character vector of file paths
#' @param values Numeric vector of depth/level values, or regex pattern to extract
#' @param direction Vertical direction: `"DOWN"` (depth increases), `"UP"` (elevation).
#'   Default: `"DOWN"`
#' @param unit Unit string (e.g., `"m"`, `"cm"`, `"hPa"`)
#' @param dim_name Dimension name. Default: `"depth"` if direction is DOWN,
#'   `"level"` if UP.
#' @param array_name Name for the data array
#' @param output Output VRT path
#'
#' @return Path to VRT file (invisibly), or XML string if `output` is NULL.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Soil layers at specific depths
#' vrt_depth_stack(
#'   files = c("soil_0cm.tif", "soil_30cm.tif", "soil_100cm.tif"),
#'   values = c(0, 30, 100),
#'   unit = "cm",
#'   output = "soil_profile.vrt"
#' )
#'
#' # Extract depth from filename
#' vrt_depth_stack(
#'   files = list.files(pattern = "temp_\\d+m\\.tif$"),
#'   values = "(\\d+)m",  # extracts "50" from "temp_50m.tif"
#'   unit = "m",
#'   output = "ocean_profile.vrt"
#' )
#' }
vrt_depth_stack <- function(
    files,
    values,
    direction = "DOWN",
    unit = NULL,
    dim_name = NULL,
    array_name = NULL,
    output = NULL
) {
  if (is.null(dim_name)) {
    dim_name <- if (direction == "DOWN") "depth" else "level"
  }

  gdal_mdim_stack(
    files = files,
    dim_name = dim_name,
    dim_values = values,
    dim_type = "VERTICAL",
    dim_direction = direction,
    dim_unit = unit,
    array_name = array_name,
    output = output
  )
}


#' Stack Rasters with Regular Spacing
#'
#' A convenience wrapper for [gdal_mdim_stack()] when files represent regularly
#' spaced values (e.g., monthly data, hourly snapshots, uniform vertical levels).
#'
#' @param files Character vector of file paths, in order
#' @param dim_name Name for the new dimension
#' @param start Starting value
#' @param increment Spacing between values
#' @param unit Unit string
#' @param array_name Name for the data array
#' @param output Output VRT path
#'
#' @return Path to VRT file (invisibly), or XML string if `output` is NULL.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # 12 monthly files
#' vrt_regular_stack(
#'   files = sprintf("precip_%02d.tif", 1:12),
#'   dim_name = "month",
#'   start = 1,
#'   increment = 1,
#'   output = "monthly_precip.vrt"
#' )
#'
#' # Pressure levels at 50 hPa intervals
#' vrt_regular_stack(
#'   files = level_files,
#'   dim_name = "pressure",
#'   start = 1000,
#'   increment = -50,
#'   unit = "hPa",
#'   output = "pressure_levels.vrt"
#' )
#' }
vrt_regular_stack <- function(
    files,
    dim_name,
    start,
    increment,
    unit = NULL,
    array_name = NULL,
    output = NULL
) {
  gdal_mdim_stack(
    files = files,
    dim_name = dim_name,
    dim_start = start,
    dim_increment = increment,
    dim_unit = unit,
    array_name = array_name,
    output = output
  )
}
