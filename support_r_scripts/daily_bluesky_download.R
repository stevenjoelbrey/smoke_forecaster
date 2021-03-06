# ------------------------------------------------------------------------------
# Title: Daily BlueSky forecast download and data management
# Author: Ryan Gan
# Date Created: 6/19/2017
# Created under R Version: 3.3.3
# ------------------------------------------------------------------------------

# Note: Code directly from mazamascience to download their bluesky runs
# http://mazamascience.com/Classes/PWFSL_2014/Lesson_07_BlueSky_FirstSteps.
# html#downloadbsoutput\

# libraries needed
library(ncdf4) # netcdf files
library(stringr)
library(raster) # easier to manipulate than netcdf file
library(rgdal)

# set up working directory
setwd("/srv/www/rgan/smoke_forecaster")
# define path to repository for the server for writing files
home_path <- paste0("/srv/www/rgan/smoke_forecaster")

# working directory from laptop
# home_path <- paste0(".")
# download bluesky daily output -----------------------------------------------

# date is needed for download; taking out "-" separator; adding 00 to get first
# run of the day (just in case there are two)
todays_date <- paste0(gsub("-","", Sys.Date()), "00")

# download fire locations from bluesky runs ----
# note right now I download only the location file, but I may work in
# fire information in the future. looks like it's contained in the json file
# Note: changed "forecast" to "combined" estimate on Sept 5 2017
fire_url_path <- paste0("https://smoke.airfire.org/bluesky-daily/output/standard/",
  "GFS-0.15deg/", todays_date, "/combined/data/fire_locations.csv")

# check if file url exists
if(RCurl::url.exists(fire_url_path == T)){
  print(paste0("Fire location data exists today: ", todays_date))
  download.file(url = file_url_path, 
    destfile = paste0(home_path, "/data/fire_locations.csv"), mode = "wb")
  } else { # if no url, print warning message and download yesterday's data
    # print warning message
    print(paste0("No fire location data today: ", todays_date, 
                 "; pulling yesterday's fire locations."))
    # pull yesterday's date
    yesterdays_date <- paste0(str_sub(todays_date, start = 1, end =6),
      formatC(as.numeric(str_sub(todays_date, start = 7, end = 8))-1,width = 2, 
              flag = "0"), "00")
    # new fire_url_path
    download.file(url = paste0("https://smoke.airfire.org/bluesky-daily/output/",
      "standard/GFS-0.15deg/",yesterdays_date,"/combined/data/fire_locations.csv"), 
      destfile = paste0(home_path, "/data/fire_locations.csv"), mode = "wb")
  }


# download smoke dispersion output ----
# define URL path for smoke dispersion
url_path <- paste0("https://smoke.airfire.org/bluesky-daily/output/standard/",
  "GFS-0.15deg/", todays_date, "/combined/data/smoke_dispersion.nc")

# download a netcdf file to work with
# check if url exists
if(RCurl::url.exists(url_path == T)){
  print(paste0("Smoke dispersion data exists today: ", todays_date))
  download.file(url = url_path, destfile = paste0(home_path,
    "/data/smoke_dispersion.nc"), mode = "wb")
} else { # if no url, print warning message and download yesterday's data
  # print warning message
  print(paste0("No smoke dispersion data today: ", todays_date, 
               "; pulling yesterday's data."))
  # pull yesterday's date
  yesterdays_date <- paste0(str_sub(todays_date, start = 1, end =6),
    formatC(as.numeric(str_sub(todays_date, start = 7, end = 8))-1,width = 2, 
                                    flag = "0"), "00")
  # new fire_url_path
  download.file(url = paste0("https://smoke.airfire.org/bluesky-daily/output/",
    "standard/GFS-0.15deg/",yesterdays_date,"/combined/data/smoke_dispersion.nc"), 
    destfile = paste0(home_path, "/data/smoke_dispersion.nc"), mode = "wb")
}

fileName <- paste0(home_path,"/data/smoke_dispersion.nc")

# netcdf file manipulaton ------------------------------------------------------
nc <- nc_open(fileName)

bs2v2 <- function(fileName) {

  # open nc file
  old_nc <- nc_open(fileName)
  
# Create latitude and longitude axes ----

  # Current (index) values
  row <- old_nc$dim$ROW$vals
  col <- old_nc$dim$COL$vals
  
  # Useful information is found in the global attributes
  globalAttributes <- ncatt_get(old_nc, varid=0) # varid=0 means 'global'
  
  # Use names(globalAttributes) to see the names of the elements contained in this list
  
  # NOTE:  globalAttributes is of class 'list'
  # NOTE:  Access list elements with either 'listName[[objectName]]' or 'listName$objectName' notation
  
  XORIG <- globalAttributes[["XORIG"]] # x origin
  YORIG <- globalAttributes[["YORIG"]] # y origin
  XCENT <- globalAttributes[["XCENT"]] # x center
  YCENT <- globalAttributes[["YCENT"]] # y center
  
  # Now we have enough information about the domain to figure out the n, e, s, w corners
  w <- XORIG
  e <- XORIG + 2 * abs(XCENT - XORIG)
  s <- YORIG
  n <- YORIG + 2 * (YCENT - YORIG)  
  
  # Knowing the grid dimensions and the true corners we can define legitimate lat/lon dimensions
  lat <- seq(s, n, length.out=length(row))
  lon <- seq(w, e, length.out=length(col))
  
  # Create time axis ----
  
  # Temporal information is stored in the 'TFLAG' variable
  tflag <- ncvar_get(old_nc, "TFLAG")
  
  # NOTE:  'TFLAG' is a matrix object with two rows, one containing the year and Julian day, 
  # NOTE:  the other containing time in HHMMSS format. We will paste matrix elements together
  # NOTE:  with 'paste()'.  The 'sprintf()' function is useful for C-style string formatting.
  # NOTE:  Here we use it to add leading 0s to create a string that is six characters long.
  time_str <- paste0(tflag[1,], sprintf(fmt="%06d", tflag[2,]))
  
  # We use 'strptime()' to convert our character index to a "POSIXct" value.
  time <- strptime(x=time_str, format="%Y%j%H%M%S", tz="GMT")
  
  # Create new ncdf4 object ----
  
  # Get PM25 values
  # NOTE:  The degenerate 'LAY' dimension disppears so that 'pm25' is now 3D, not 4D. 
  pm25 <- ncvar_get(old_nc, "PM25")
  
  # Convert time to numeric value for storing purposes
  numericTime <- as.numeric(time)
  
  # Define dimensions
  latDim <- ncdim_def("lat", "Degrees North", lat) 
  lonDim <- ncdim_def("lon", "Degrees East", lon)  
  timeDim <- ncdim_def("time", "seconds from 1970-1-1", numericTime)  
  
  # Define variables
  pm25Var <- ncvar_def(name="PM25", units="ug/m^3", 
                       dim=list(lonDim, latDim, timeDim), missval=-1e30)
  
  # Create a new netcdf file 
  fileName_v2 <- str_replace(fileName, ".nc", "_v2.nc")
  new_nc <- nc_create(fileName_v2, pm25Var)
  
  # Put data into the newly defined variable 
  ncvar_put(new_nc, pm25Var, pm25)
  
  # Close the file
  nc_close(new_nc)
  
}

# close original nc connection
nc_close(nc)
rm(nc)

# Now run this function on the file we just downloaded
bs2v2(fileName)
list.files(pattern='*.nc')

# working with the raster brick of the nc file
nc_path <- paste0(home_path, "/data/smoke_dispersion_v2.nc")
# brick or stack 
smk_brick <- brick(nc_path)

# Calculate daily average smoke concentration ----------------------------------

# create raster layer of same day mean value
# note Sept 13: changing to handle carry over smoke
same_day_smk <- smk_brick[[1:31]]
# create raster layer of mean value
same_day_mean_smk <- mean(same_day_smk)
# extract the date without timestamp (taking element date 29 frome 1:29)
same_day_date  <- as.numeric(substring(smk_brick@data@names, 2))[15]
# assign date time stamp in a format of month_day_year to bind with name
same_day_date <- format(as.POSIXct(same_day_date, origin="1970-1-1", tz="GMT"),
                    format = "%b %d %Y")

# calculate next day daily average 
# subset raster brick to the 32th to 56th layer (next day MST)
next_day_smk <- smk_brick[[32:56]]
# create raster layer of daily mean value
next_day_mean_smk <- mean(next_day_smk)
# extract next day's date
next_day_date  <- as.numeric(substring(smk_brick@data@names, 2))[44]
# assign date time stamp in a format of month_day_year to bind with name
next_day_date <- format(as.POSIXct(next_day_date, origin="1970-1-1", tz="GMT"),
                        format = "%b %d %Y")

# creating a vector of the character dates and saving to use in shiny labels
# note I think it's easier to save as a seperate file than label the layers of 
# the shape layers; I suspect less bugs with generic names in the shapefile than
# a changing date
date_labels <- c(same_day_date, next_day_date)
# saving character string of dates
save(date_labels, file = paste0(home_path,"/data/date_label.RData"))

# create raster brick and create spatial polygon ----
# make raster brick of same_day and next_day mean smoke
smoke_stack <- brick(same_day_mean_smk, next_day_mean_smk)

# create pm matrix of same-day and next-day values -----
# this will be used later for population-weighting
pm_mat <- as.matrix(cbind(same_day_mean_smk@data@values, 
                          next_day_mean_smk@data@values))

# convert smoke_stack to polygon/shape
smk_poly <- rasterToPolygons(smoke_stack)

# saving bluesky grid shapefile ----
# this will be commented out once it's done
# #subsetting just the grid so I can calculate spatial overlays
# smk_grid <- smk_poly[, 1]
# # write smoke grid that doesn't have values
# writeOGR(obj = smk_grid, dsn = "./data/bluesky_grid", layer = "bluesky_grid",
#          driver = "ESRI Shapefile")

# subsetting smk_polygon to only those with values > 5 
# to make polygon file smaller and easier to project
smk_poly <- smk_poly[smk_poly$layer.1 > 5 | smk_poly$layer.2 > 5, ]

# remove raster files to save space
rm(smk_brick, same_day_smk, same_day_mean_smk, next_day_smk,
   next_day_mean_smk, smoke_stack)

# Write gridded smoke polygon --------------------------------------------------
writeOGR(obj = smk_poly, dsn = paste0(home_path,"/data/smk_poly"), 
         layer = "smk_poly", driver = "ESRI Shapefile", overwrite_layer = T)

# remove smk poly to save room
rm(smk_poly)

# Calculate population-weighted county smk pm2.5 values ------------------------
# Read in proportion-intersect matrix between grid and county shapes
grid_county_pi <- data.table::fread("./data/bluesky_county_prop_intersect.csv")

# convert to matrix
pi_mat <- as.matrix(grid_county_pi[,2:3109])
# remove grid_county_pi to save space
rm(grid_county_pi)

# population density value vector
# read 2015 bluesky population density
population_grid <- data.table::fread("./data/2015-bluesky_grid_population.csv")
# create vector of population density
popden <- population_grid$popden 

# multiply population vector by pm vector
pm_pop_mat <- popden * pm_mat

# matrix multiply prop int matrix by population vector for daily summed pm
county_grid_pm_mat <- t(pi_mat) %*% pm_pop_mat

# matrix multiply prop int matrix by popden vector for popden per county
popden_county <- t(pi_mat) %*% popden

# calculate the inverse of popden_county matrix
popden_county_inverse <- 1/popden_county

# multiply county_grid_pm_mat by inverse population vector to estimate 
# county population-weighted estimate 
county_pop_wt_smk <- county_grid_pm_mat * as.vector(popden_county_inverse)

# save as dataframe
pm_county_wt <- as.data.frame(county_pop_wt_smk)
# name variables
colnames(pm_county_wt) <- c("same_day_pm", "next_day_pm")
# create FIPS variable
pm_county_wt$FIPS <- as.character(str_sub(rownames(pm_county_wt), start=6L))

# remove matrices to save space
rm(county_grid_pm_mat, county_pop_wt_smk, pi_mat, pm_mat, popden,
   pm_pop_mat, popden_county, popden_county_inverse, population_grid)

# Calculate health impact of given smoke concentration ------------------------- 

# read county populations
county_pop <- data.table::fread(paste0("./data/us_census_county_population/",
  "PEP_2015_PEPANNRES_with_ann.csv"))[-1, c(2,11)]

# assign names: FIPS and pop_2015
colnames(county_pop) <- c("FIPS", "pop_2015")
# assign pop_2015 as numeric
county_pop$pop_2015 <- as.numeric(county_pop$pop_2015)
# subset counties in smoke values
county_pop <- county_pop[county_pop$FIPS %in% pm_county_wt$FIPS, ]

# merge population with smk pm values
hia_est <- merge(county_pop, pm_county_wt, by = "FIPS")
# add in base_rate; this will be changed but i need to calculate this
hia_est$base_resp_rate <- 1.285/10000 
# add beta based on our work
hia_est$resp_beta <- log(1.052)
# calculate expected respiratory ED visits
hia_est$same_day_resp_ed <- round((hia_est$base_resp_rate * 
  (1-exp(-(hia_est$resp_beta) * hia_est$same_day_pm)) * hia_est$pop_2015),0)
# next day
hia_est$next_day_resp_ed <- round((hia_est$base_resp_rate * 
  (1-exp(-(hia_est$resp_beta) * hia_est$next_day_pm)) * hia_est$pop_2015),0)

# Notes on HIA: 2017-12-29
# need to rename hia_estimate column names to avoid truncation when saving polygon
# considering a monte-carlo; not sure it's worth it now

# Create hia shapefile for smoke_forecaster app --------------------------------

# read in shapefile
# county path
poly_path <- "./data/us_county"
poly_layer <- "us_county"

# read county polygon
us_shape <- readOGR(dsn = poly_path, layer = poly_layer)
# add fips variable to join
us_shape$FIPS <- us_shape$GEOID

# join popwt pm and hia estimates to shapefile
us_shape <- sp::merge(us_shape, hia_est, by = "FIPS")

# subset to counties with hia estimates of at least 1
us_shape <- us_shape[us_shape$same_day_resp_ed > 1 | 
                       us_shape$next_day_resp_ed > 1, ]

# rename truncated variable names; renamed hia estimates to layer_1 and layer_2
# to match gridded bluesky forecasts of smoke labels
c_names <- colnames(us_shape@data)
c_names[11:17] <- c("Pop", "Day1Pm", "Day2Pm", "RespRt", 
                    "RespB", "layer_1", "layer_2")

colnames(us_shape@data) <- c_names

# save shape with hia estimates
writeOGR(obj = us_shape, dsn = paste0(home_path,"/data/hia_poly"), 
         layer = "hia_poly", driver = "ESRI Shapefile", overwrite_layer = T)
