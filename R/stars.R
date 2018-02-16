#' read gdal raster file (not to be called by users, but to be used by stars::st_stars)
#'
#' @param x character vector, possibly of length larger than 1 when more than one raster is read
#' @param options character
#' @param driver character; when empty vector, driver is auto-detected.
#' @param read_data logical; if \code{FALSE}, only the imagery metadata is returned
#' @export
gdal_read = function(x, options = character(0), driver = character(0), read_data = TRUE)
	CPL_read_gdal(x, options, driver, read_data)

#' retrieve the inverse of a gdal geotransform
#' 
#' @param gt double vector of length 6
#' @export
gdal_inv_geotransform = function(gt) CPL_inv_geotransform(as.double(gt))

## @param x two-column matrix with columns and rows, as understood by GDAL; 0.5 refers to the first cell's center; 
## FIXME: this is now duplicate in sf and stars
xy_from_colrow = function(x, geotransform, inverse = FALSE) {
# http://www.gdal.org/classGDALDataset.html , search for geotransform:
# 0-based indices:
# Xp = geotransform[0] + P*geotransform[1] + L*geotransform[2];
# Yp = geotransform[3] + P*geotransform[4] + L*geotransform[5];
	if (inverse) {
		geotransform = gdal_inv_geotransform(geotransform)
		if (any(is.na(geotransform)))
			stop("geotransform not invertible")
	}
	stopifnot(ncol(x) == 2)
	matrix(geotransform[c(1, 4)], nrow(x), 2, byrow = TRUE) + 
		x %*% matrix(geotransform[c(2, 3, 5, 6)], nrow = 2, ncol = 2)
}

# convert x/y gdal dimensions into a list of points, or a list of square polygons
#' @export
st_as_sfc.dimensions = function(x, ..., as_points = NA, use_cpp = FALSE, which = seq_len(prod(dim(x)))) {

	stopifnot(identical(names(x), c("x", "y")))
	if (is.na(as_points))
		stop("as_points should be set to TRUE (`points') or FALSE (`polygons')")

	xy2sfc = function(cc, dm, as_points) { # form points or polygons from a matrix with corner points
		if (as_points)
			unlist(apply(cc, 1, function(x) list(sf::st_point(x))), recursive = FALSE)[which]
		else {
			stopifnot(prod(dm) == nrow(cc))
			lst = vector("list", length = prod(dm - 1))
			for (y in 1:(dm[2]-1)) {
				for (x in 1:(dm[1]-1)) {
					i1 = (y - 1) * dm[1] + x      # top-left
					i2 = (y - 1) * dm[1] + x + 1  # top-right
					i3 = (y - 0) * dm[1] + x + 1  # bottom-right
					i4 = (y - 0) * dm[1] + x      # bottlom-left
					lst[[ (y-1)*(dm[1]-1) + x ]] = sf::st_polygon(list(cc[c(i1,i2,i3,i4,i1),]))
				}
			}
			lst[which]
		}
	}

	y = x$y
	x = x$x
	stopifnot(identical(x$geotransform, y$geotransform))
	cc = if (!is.na(x$from) && !is.na(y$from)) {
		xy = if (as_points) # grid cell centres:
			expand.grid(x = seq(x$from, x$to) - 0.5, y = seq(y$from, y$to) - 0.5)
		else # grid corners: from 0 to n
			expand.grid(x = seq(x$from - 1, x$to), y = seq(y$from - 1, y$to))
		xy_from_colrow(as.matrix(xy), x$geotransform)
	} else {
		if (!as_points)
			stop("grid cell sizes not available")
		expand.grid(x = x$values, y = y$values)
	}
	dims = c(x$to, y$to) + 1
	if (use_cpp)
		structure(CPL_xy2sfc(cc, as.integer(dims), as_points, as.integer(which)), 
			crs = st_crs(x$refsys), n_empty = 0L)
	else
		st_sfc(xy2sfc(cc, dims, as_points), crs = x$refsys)
}

#' read coordinate reference system from GDAL data set
#' @param file character; file name
#' @param options character; raster layer read options
#' @return object of class \code{crs}, see \link[sf]{st_crs}.
#' @export
gdal_crs = function(file, options = character(0)) {
	ret = CPL_get_crs(file, options)
	ret$crs = sf::st_crs(wkt = ret$crs)
	ret
}

#' get metadata of a raster layer
#'
#' get metadata of a raster layer
#' @name gdal_metadata
#' @export
#' @param file file name
#' @param domain_item character vector of length 0, 1 (with domain), or 2 (with domain and item); use \code{""} for the default domain, use \code{NA_character_} to query the domain names.
#' @param options character; character vector with data open options
#' @param parse logical; should metadata be parsed into a named list (\code{TRUE}) or returned as character data?
#' @return named list with metadata items
#' @examples
#' #f = system.file("tif/L7_ETMs.tif", package="stars")
#' f = system.file("nc/avhrr-only-v2.19810901.nc", package = "stars")
#' gdal_metadata(f)
#' gdal_metadata(f, NA_character_)
#' # try(gdal_metadata(f, "wrongDomain"))
#' # gdal_metadata(f, c("", "AREA_OR_POINT"))
gdal_metadata = function(file, domain_item = character(0), options = character(0), parse = TRUE) {
	stopifnot(is.character(file))
	stopifnot(is.character(domain_item))
	stopifnot(length(domain_item) <= 2)
	stopifnot(is.character(options))
	if (length(domain_item) >= 1 && !is.na(domain_item[1]) &&
			!(domain_item[1] %in% CPL_get_metadata(file, NA_character_, options)))
		stop("domain_item[1] not found in available metadata domains")
	p = CPL_get_metadata(file, domain_item, options)
	if (!is.na(domain_item[1]) && parse)
		split_strings(p)
	else
		p
}

split_strings = function(md, split = "=") {
	splt = strsplit(md, split)
	lst = lapply(splt, function(x) if (length(x) <= 1) NA_character_ else x[[2]])
	structure(lst, names = sapply(splt, function(x) x[[1]]))
	structure(lst, class = "gdal_metadata")
}

#' @name gdal_metadata
#' @param name logical; retrieve name of subdataset? If \code{FALSE}, retrieve description
#' @export
#' @return \code{gdal_subdatasets} returns a zero-length list if \code{file} does not have subdatasets, and else a named list with subdatasets.
gdal_subdatasets = function(file, options = character(0), name = TRUE) {
	if (!("SUBDATASETS" %in% CPL_get_metadata(file, NA_character_, options)))
		list()
	else {
		md = gdal_metadata(file, "SUBDATASETS", options, TRUE)
		if (name)
			md[seq(1, length(md), by = 2)]
		else
			md[seq(2, length(md), by = 2)]
	}
}