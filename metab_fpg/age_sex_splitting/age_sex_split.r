###########################################################
### Date: 2/4/16
### Project: Metabolics
### Purpose: Age Sex Split
### Notes: 
###
###     Code to age sex split continuous means to the standard
###     GBD 5-yr age groups/sex groups, done at the global level
###
###     Adapted from Age Sex Splitting code for BMI (http://www.thelancet.com/journals/lancet/article/PIIS0140-6736(14)60460-8/abstract)
###
###########################################################


###################
### Setting up ####
###################
rm(list=objects())
library(data.table)
library(dplyr)


## OS locals
os <- .Platform$OS.type
if (os == "windows") {
  jpath <- "J:/"
} else {
  jpath <- "/home/j/"
}

## Path locals
code_root <- paste0(unlist(strsplit(getwd(), "metabolics"))[1], "metabolics/code")
data_root <- gsub("/home/j/|J:/", jpath, fread(paste0(code_root, "/root.csv"))[, data_root])

## Resources
source(paste0(code_root, "/extraction/exp/resources/db_tools.r"))


#####################################################################
### Pull population estimates
#####################################################################

## Pull populations
dbname <- "shared"
host <- "modeling-mortality-db.ihme.washington.edu"
query <-  paste0("SELECT year_id, location_id, sex_id, pop_scaled, age_group_years_start AS age_start
                                 FROM mortality.output
                                 LEFT JOIN mortality.output_version using(output_version_id)
                                 LEFT JOIN shared.location_hierarchy_history using(location_id)
                                 LEFT JOIN shared.age_group using(age_group_id)
                                 WHERE location_hierarchy_history.location_set_version_id = 41
                                 AND output_version.is_best = 1
                                 AND year_id >= 1980
                                 AND age_group_id < 22
                                 AND sex_id IN(1,2)")
pops <- run_query(dbname, host, query)
pops <- pops[, age_start := round(age_start)]


#####################################################################
### Define function
#####################################################################

age_sex_split <- function(df, location_id, year_id, age_start, age_end, sex, estimate, sample_size) {

###############
## Setup 
###############

## Generate unique ID for easy merging
df[, split_id := 1:.N]

## Make sure age and sex are int
cols <- c(age_start, age_end, sex)
df[, (cols) := lapply(.SD, as.integer), .SDcols=cols]

## Save original values
orig <- c(age_start, age_end, sex, estimate, sample_size)
orig.cols <- paste0("orig.", orig)
df[, (orig.cols) := lapply(.SD, function(x) x), .SDcols=orig]

## Separate metadata from required variables
cols <- c(location_id, year_id, age_start, age_end, sex, estimate, sample_size)
meta.cols <- setdiff(names(df), cols)
metadata <- df[, meta.cols, with=F]
data <- df[, c("split_id", cols), with=F]

## Round age groups to the nearest 5-y boundary
data[, age_start := age_start - age_start %%5]
data <- data[age_start > 80, (age_start) := 80]
data[, age_end := age_end - age_end %%5 + 4]
data <- data[age_end > 80, age_end := 84]

## Split into training and split set
training <- data[(age_end - age_start) == 4 & sex_id %in% c(1,2)]
split <- data[(age_end - age_start) != 4 | sex_id == 3]


###################
## Age Sex Pattern
###################

# Determine relative age/sex pattern
asp <- aggregate(training[[estimate]],by=lapply(training[,c(age_start, sex), with=F],function(x)x),FUN=mean,na.rm=TRUE)
names(asp)[3] <- "rel_est"

# Fill NAs with values from adjacent age/sex groups
asp <- dcast(asp, formula(paste0(age_start," ~ ",sex)), value.var="rel_est")
asp[is.na(asp[[1]]), 1] <- asp[is.na(asp[[1]]),2]
asp[is.na(asp[[2]]), 2] <- asp[is.na(asp[[2]]),1]
asp <- melt(asp,id.var=c(age_start), variable.name=sex, value.name="rel_est")
asp[[sex]] <- as.integer(asp[[sex]])

##########################
## Expand rows for splits
##########################

split[, n.age := (age_end + 1 - age_start)/5]
split[, n.sex := ifelse(sex_id==3, 2, 1)]

## Expand for age 
split[, age_start_floor := age_start]
expanded <- rep(split$split_id, split$n.age) %>% data.table("split_id" = .)
split <- merge(expanded, split, by="split_id", all=T)
split[, age.rep := 1:.N - 1, by=.(split_id)]
split[, (age_start):= age_start + age.rep * 5 ]
split[, (age_end) :=  age_start + 4 ]

## Expand for sex
split[, sex_split_id := paste0(split_id, "_", age_start)]
expanded <- rep(split$sex_split_id, split$n.sex) %>% data.table("sex_split_id" = .)
split <- merge(expanded, split, by="sex_split_id", all=T)
split <- split[sex_id==3, (sex) := 1:.N, by=sex_split_id]

##########################
## Perform splits
##########################

## Merge on population and the asp, aggregate pops by split_id
split <- merge(split, pops, by=c("location_id", "year_id", "sex_id", "age_start"), all.x=T)
split <- merge(split, asp, by=c("sex_id", "age_start"))
split[, pop_group := sum(pop_scaled), by="split_id"]

## Calculate R, the single-group age/sex estimate in population space using the age pattern from asp
split[, R := rel_est * pop_scaled]

## Calculate R_group, the grouped age/sex estimate in population space
split[, R_group := sum(R), by="split_id"]

## Split 
split[, (estimate) := get(estimate) * (pop_group/pop_scaled) * (R/R_group) ]

## Split the sample size
split[, (sample_size) := sample_size * pop_scaled/pop_group]

## Mark as split
split[, cv_split := 1]

#############################################
## Append training, merge back metadata, clean
#############################################

## Append training, mark cv_split
out <- rbind(split, training, fill=T)
out <- out[is.na(cv_split), cv_split := 0]

## Append on metadata
out <- merge(out, metadata, by="split_id", all.x=T)

## Clean
out <- out[, c(meta.cols, cols, "cv_split"), with=F]
out[, split_id := NULL]
    
}

  
#####################################################################
### Run age sex splits
#####################################################################

df <- readRDS(paste0(data_root, "/extraction/output/processing/post_dc_cw.rds"))

## Get location id
if (!"location_id" %in% names(df)) {
  locs <- locs <- get_location_hierarchy(74)[, .(location_id, ihme_loc_id)]
  df <- merge(df, locs, by="ihme_loc_id", all.x=T)
}
df <- df[!is.na(location_id)]
## Drop anything without means
df <- df[!is.na(mean)]

## Split
split <- lapply(c("sbp", "fpg", "chl"), function(x) {
    age_sex_split(df=df[me_name==x], 
                  location_id = "location_id", 
                  year_id = "year_id", 
                  age_start = "age_start",
                  age_end = "age_end", 
                  sex = "sex_id",
                  estimate = "mean",
                  sample_size = "sample_size")
    }
    ) %>% rbindlist

#####################################################################
### Clean
#####################################################################

## Everything looks good, droppping orig. columns
split <- split[, !grep("orig.", names(split), value=T), with=F]

## Generate age_group_id
split <- split[, age_group_id := round(age_start/5) + 5]
split <- split[, c("age_start", "age_end") := NULL]

## Save
saveRDS(split, paste0(data_root, "/extraction/output/processing/split.rds"))

