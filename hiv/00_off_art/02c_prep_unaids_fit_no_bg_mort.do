
// Data comes from UNAIDS spreadsheet where background mortality is set to zero.  Data is predicted survival curve.  We want to graph that against our models, since our models are HIV relative survival.

clear all
set more off
cap restore, not

if c(os) == "Windows" {
	global prefix "J:"
}
if c(os) == "Unix" {
	global prefix "/home/j"
	set odbcmgr unixodbc
}

local extract_dir "$prefix/WORK/04_epi/01_database/02_data/hiv/extraction_2015/no_art"

*************************************************
*** FORMAT DATA
*************************************************
// UNAIDS compartmental model HIV-specific mortality
insheet using  "`extract_dir'/raw/unaids_hiv_specific_mort.csv", clear comma names
drop v4-v8
generate surv = 1-mort
tostring surv, replace force
destring surv, replace
keep if mod(yr_since_sc, 1) == 0

*************************************************
*** SAVE
*************************************************
outsheet using "`extract_dir'/prepped/all_unaids_hiv_specific_prepped.csv", replace comma names
