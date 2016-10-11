
 
********************************************************************************
*          SET UP ENVIRONMENT WITH NECESSARY SETTINGS AND LOCALS               *
********************************************************************************

* BOILERPLATE *
  clear all
  set maxvar 12000
  set more off
   
  if c(os) == "Unix" {
    local j "/home/j"
    set odbcmgr unixodbc
    }
  else if c(os) == "Windows" {
    local j "J:"
    }
	
  
  adopath + `j'/WORK/10_gbd/00_library/functions
  
  tempfile prev migration pop endemic usa nonusa subnats
 
  
  odbc load, exec("SELECT output_version_id FROM output_version WHERE is_best = 1") dsn(mortality) clear
  odbc load, exec("SELECT year_id, location_id, sex_id, age_group_id, mean_pop FROM output WHERE year_id>=1980 AND age_group_id >=2 AND age_group_id <= 22 AND output_version_id = `=output_version_id[1]'") dsn(mortality) clear
  generate destination_location_id = location_id
  save `pop'
 
 
* BUILD LIST OF ENDEMIC LOCATIONS * 
  get_location_metadata, location_set_id(8) clear
  generate endemic = (strmatch(lower(region_name), "*latin america*") | inlist(ihme_loc_id, "BLZ", "GUY", "SUR")) 
  keep location_id parent_id location_type ihme_loc_id endemic is_estimate
  keep if is_estimate==1 | location_type=="admin0"
  save `endemic'

  *levelsof location_id if endemic==1, local(endemicLocations) clean
  
 
 
* PULL IN CHAGAS MORTALITY ESTIMATES & SUM BY LOCATION *  
  get_outputs, topic("cause") location_id("all") year_id("all") cause_id(346) clear
  replace val = 0 if missing(val)
  fastcollapse val, by(location*) type(sum)
  rename val deaths


  merge 1:1 location_id using `endemic', assert(1 3) nogenerate
  
  gen countryIso = substr(ihme_loc_id, 1, 3)
  bysort countryIso: egen nonZero = max(deaths>0)
  
  levelsof location_id if nonZero==1 & endemic==0 & location_type=="admin0", local(nonzero) sep( | destination_location_id==) clean
  
  
* BRING IN MIGRATION DATA *
  use `j'/WORK/04_epi/02_models/01_code/06_custom/chagas/data/migrationData.dta, clear
 
  rename year year_id
  keep if (strmatch(lower(source_region_name), "*latin america*") | inlist(source_iso3, "BLZ", "GUY", "SUR")) & !(strmatch(lower(destination_region_name), "*latin america*") | inlist(destination_iso3, "BLZ", "GUY"))  
  keep year_id destination_iso3 destination_location_id destination_location_name source source_location_id source_location_name  source_region_name source_iso3 migrants
 
 
  
* DETERMINE WHICH COUNTRIES MEET ESTIMATION CRITERIA *
* (we estimate prevalence for countries that either have ic Chagas deaths or >=0.1% of population immigrants from endemic countries) *
 
  preserve
 
  fastcollapse migrants, by(year_id destination*) type(sum)
  generate age_group_id = 22
  generate sex_id = 3
  merge 1:1 destination_location_id year_id age_group_id sex_id using `pop', assert(2 3) keep(3) nogenerate
 
  drop if missing(migrants)
  gen prMigrant = migrants / mean_pop
  bysort destination_location_id: egen maxPr = max(prMigrant)
  
  levelsof destination_location_id if maxPr>=0.001 | destination_location_id==`nonzero', local(keep) sep( | destination_location_id==) clean
  
  restore
  
  keep if destination_location_id==`keep'
  
  
  
* BRING IN POPULATION AT RISK DATASET *  
  generate iso3 = source_iso3
  merge m:1 iso3 year_id using "J:\WORK\04_epi\02_models\01_code\06_custom\chagas\data\chagasPopulationAtRisk.dta", assert(2 3) keep(3) nogenerate
  drop iso3
  
  
  
 * EXTRAPOLATE MIGRANT AND PR AT RISK #s OUT TO COVER ALL GBD ESTIMATION YEARS *
  reshape wide migrants prAtRisk, i(destination* source*) j(year_id)
 
  forvalues year = 1990(5)2015 {

	if `year'< 2000 & !inlist(`year', 1990, 2000, 2010, 2013) {
	  local yearStart 1990
	  local yearEnd   2000
	  }
	else if `year'< 2010 & !inlist(`year', 1990, 2000, 2010, 2013) {
	  local yearStart 2000
	  local yearEnd   2010
	  }
	else if !inlist(`year', 1990, 2000, 2010, 2013) {
	  local yearStart 2010
	  local yearEnd   2013
	  }
	else {
	  continue
	  }

	di `year'
	
	foreach var in migrants prAtRisk {
  	  generate `var'`year' = `var'`yearStart' * (`var'`yearEnd'/`var'`yearStart')^((`year'-`yearStart') / (`yearEnd'-`yearStart'))
	  replace  `var'`year' = 0 if `var'`yearStart'==0 & missing(`var'`year')
	  }
	}

  drop *2013
 
  reshape long migrants prAtRisk, i(destination* source*) j(year_id) 
  
  
* BREAK OUT BY AGE AND SEX *  
  cross using J:\WORK\04_epi\02_models\01_code\06_custom\chagas\data\immigrantsByAgeSex.dta
  replace migrants = migrants * pctAgeSex
  drop pctAgeSex
  
 
 
* COMBINE PREVALENCE AND MIGRATION DATA AND CACULATE NUBMER OF CHAGAS INFECTED IMMIGRANTS * 
 merge m:1 source_location_id year_id sex_id age_group_id using J:/WORK/04_epi/02_models/01_code/06_custom/chagas/data/endemicPrevDraws.dta, assert(3) nogenerate

 
 forvalues i = 0 / 999 {
   quietly {
     generate chagasMigrants_`i' = rbinomial(migrants, prAtRisk) * (draw_`i'/prAtRisk)
     replace  chagasMigrants_`i' = 0 if missing(chagasMigrants_`i')
     }	 
   di "." _continue
   }
  

 

 
* BREAK DOWN US NUMBERS BY STATE *
 preserve
 drop if destination_location_id==102 
 fastcollapse chagasMigrants_*, by(year_id destination* age_group_id sex_id) type(sum)
 
 rename destination_iso3  ihme_loc_id
 rename destination_location_id location_id
 rename destination_location_name location_name
 
 save `nonusa'
 restore
 
 
 
 keep if destination_location_id==102  
 save `usa'
 
 get_location_metadata, location_set_id(8) clear
 keep location_id region_name
 rename * source_*
 
 merge 1:m source_location_id using `usa', assert(1 3) keep(3) nogenerate
 
 generate mergeRegion = "Caribbean" if source_region_name == "Caribbean"
 replace  mergeRegion = "CentralAmerica" if source_region_name == "Central Latin America"
 replace  mergeRegion = "Mexico" if source=="Mexico" 
 replace  mergeRegion = "SouthAmerica" if missing(mergeRegion)
 
 fastcollapse chagasMigrants_* , by(age_group_id year_id sex_id mergeRegion) type(sum)
 
 joinby mergeRegion using J:/WORK/04_epi/02_models/01_code/06_custom/chagas/data/immigrantsByState.dta
 

 forvalues i = 0 / 999 {
   quietly replace chagasMigrants_`i' = chagasMigrants_`i' * pct
   if mod(`=`i'+1', 100)==0 di `=`i'+1' _continue
   else di "." _continue
   }


fastcollapse chagasMigrants_*, by(year_id location_id location_name ihme_loc_id age_group_id sex_id) type(sum)


  
 append using `nonusa'
 
 
 merge 1:1 location_id age_group_id sex_id year_id using `pop', assert(2 3) keep(3) nogenerate
 
 
 forvalues i = 0 / 999 {
   quietly generate draw_`i' = chagasMigrants_`i' / mean_pop
   if mod(`=`i'+1', 100)==0 di `=`i'+1' _continue
   else di "." _continue
   } 
   
keep location_id age_group_id sex_id year_id draw_* 


local sub67 35424 35425 35426 35427 35428 35429 35430 35431 35432 35433 35434 35435 35436 35437 35438 35439 35440 35441 35442 35443 35444 35445 35446 35447 35448 35449 35450 35451 35452 35453 35454 35455 35456 35457 35458 35459 35460 35461 35462 35463 35464 35465 35466 35467 35468 35469 35470
local sub93 4940 4944
local sub95 433 434 4636 4749

foreach parent in 67 93 95 {
  foreach sub of local sub`parent' {
    expand 2 if location_id==`parent', gen(newObs)
	replace location_id = `sub' if newObs==1
	drop newObs
	}
  }

drop if inlist(location_id, 67, 93, 95)   
  
save J:/WORK/04_epi/02_models/01_code/06_custom/chagas/data/latinAmericanMigrants.dta, replace




