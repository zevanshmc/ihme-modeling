// Date:February 17, 2016 
// Purpose: Looking for SHS variable in DHS (currently just using couples module to determine whether spouse smokes, but want to get a sense of how many DHS' use the frequency of household smokers inside the home question, which would likely be much more accurate)

***********************************************************************************
** SET UP
***********************************************************************************

// Set application preferences
	clear all
	set more off
	cap restore, not
	set maxvar 32700

// change directory
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	cd "$prefix/WORK/04_epi/01_database/01_code/02_central/survey_juicer"

// import functions
	run "./svy_extract_admin/populate_codebooks.ado"
	run "./svy_extract_admin/make_mirror.ado"
	run "./svy_search/svy_search_assign.ado"
	run "./svy_extract/svy_extract_assign.ado"
	run "./svy_extract/svy_encode_apply.ado"
	run "./tabulations/svy_svyset.ado"
	run "./tabulations/svy_subpop.ado"
	run "./tabulations/svy_group_ages.ado"
	

// Set up locals 
	local data_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/dhs"
	local out_dir "$prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/prepped"

// Use get_location_metadata 
	run "$prefix/WORK/10_gbd/00_library/functions/get_location_metadata.ado"

	get_location_metadata, location_set_id(9) clear
	keep if inlist(level, 3, 4)
	keep if is_estimate == 1 
	keep location_id location_ascii_name ihme_loc_id

	tempfile countrycodes 
	save `countrycodes', replace


/*
	
***********************************************************************************
** RUN SEARCH
***********************************************************************************


	svy_search_assign , /// 
	job_name(shs_revised_dhs_search_vars) /// 																					This is what your final file will be named
	output_dir($prefix/WORK/05_risk/risks/smoking_shs/data/exp/01_tabulate/raw/dhs) /// 							This is where your final file will be saved
	svy_dir($prefix/DATA/MACRO_DHS) ///																				This is the directory of the data you want to search through
	lookat("hv252" "frequency household members smoke inside the house" "inside the house") /// 	These are the variable names you want to search for
	recur ///																										This tells the program to look in all sub directories
	variables /// 
	descriptions ///	
	val_labels ///																									This tells the program to at variable names
	
*/
***********************************************************************************
** BRING IN FILE AND SET UP CODEBOOKS
***********************************************************************************

	use "`data_dir'/shs_revised_dhs_search_vars.dta", clear 
	keep if regexm(description, "smoke inside the house") 
	keep if regexm(filename, "_HH_") 

	split filename, p("_") 
	rename filename1 iso3 
	rename filename3 year 
	drop filename2 filename4 filename5 filename6 filename7
	drop if regexm(filename, "SP") // DOM 2013 has duplicated files, one of which is the "SP" version

	replace file = subinstr(file, "/HOME/J/", "J:/", .)

	duplicates drop file, force

	levelsof file, local(files) 

	local counter = 1 

	tempfile all 
	save `all', replace 


***********************************************************************************
** LOOP THROUGH HOUSEHOLD MODULES
***********************************************************************************

	foreach file of local files { 

		di "`file'"
		use "`file'", clear 
		renvars, lower 

			// The Peruvian DHS' have different variable names for second-hand smoke exposure in the household modules

			if regexm("`file'", "PER_DHS6_2011") { 
				keep hhid hv001 hv002 hv003 hv005 hv012 hv014 hv021 hv022 sxh89 
			}

			else if regexm("`file'", "PER_DHS5_2003") { 
				keep hhid hv001 hv002 hv003 hv005 hv012 hv014 hv021 hv022 sh30 sh3001 sh3002
			}

			else if regexm("`file'", "PER_DHS6_2012") { 
				keep hhid hv001 hv002 hv003 hv005 hv012 hv014 hv021 hv022 sxh89
			}

			else if regexm("`file'", "PER_DHS6_2009") { 
				keep hhid hv001 hv002 hv003 hv005 hv012 hv014 hv021 hv022 sh78 sh79 sh80
			}

			else if regexm("`file'", "PER_DHS6_2010") { 
				keep hhid hv001 hv002 hv003 hv005 hv012 hv014 hv021 hv022 sh87 sh88 sh89
			}
			
			else {
				keep hhid hv001 hv002 hv003 hv005 hv012 hv014 hv021 hv022 hv252 
			}

		gen file = "`file'"
		
		tempfile data`counter'
		save `data`counter'', replace
		local counter = `counter' + 1
		di "`counter'"

	}

// Append data from each country to make a compiled master dataset 
	use `data1', clear
	local max = `counter' -1
	forvalues x = 2/`max' {
		append using `data`x''
	}

	tempfile household 
	save `household', replace

***********************************************************************************
** LOOP THROUGH WOMEN MODULES
***********************************************************************************	

	use `all', clear 

	// Bring in female modules 
	replace file = subinstr(file, "_HH_", "_WN_", .)

	levelsof file, local(files)

	local counter = 1 

	foreach file of local files { 

		di "`file'"
		use "`file'", clear 
		renvars, lower 

		keep caseid v001 v002 v003 v005 v012 v021 v022 v463* // just bring in identifier variables & smoking status 

		gen file = "`file'"
		
		tempfile data_women_`counter'
		save `data_women_`counter'', replace
		local counter = `counter' + 1
		di "`counter'"
	}

	use `data_women_1', clear
	local max = `counter' -1
	forvalues x = 2/`max' {
		append using `data_women_`x''
	}

		// split file path 
		split file, p("/") 
		gen filepath = file1 + "/" + file2 + "/" + file3 + "/" + file4 + "/" + file5
		drop file1 file2 file3 file4 file5 file6 

	tempfile women 
	save `women', replace 



***********************************************************************************
** LOOP THROUGH MALE MODULES
***********************************************************************************
	
	use `all', clear 

	// Bring in male modules 
	replace file = subinstr(file, "_HH_", "_MN_", .)
	replace filename = subinstr(filename, "_HH_", "_MN_", .)

	levelsof file, local(files)

	local counter = 1 

	foreach file of local files { 

		di "`file'"
		cap confirm file "`file'" 
		di _rc 

		if _rc == 0 { 

			use "`file'", clear 
			renvars, lower 

			keep mv001 mv002 mv003 mv005 mv012 mv021 mv022 mv463* // just bring in identifier variables & smoking status 

			gen file = "`file'"
			
			tempfile data_men_`counter'
			save `data_men_`counter'', replace
			local counter = `counter' + 1
			di "`counter'"

			}

		else { 
			di in red "file does not exist"
		}
		
	}

	use `data_men_1', clear
	local max = `counter' -1
	forvalues x = 2/`max' {
		append using `data_men_`x''
	}


		// split file path 
		split file, p("/") 
		gen filepath = file1 + "/" + file2 + "/" + file3 + "/" + file4 + "/" + file5
		drop file1 file2 file3 file4 file5 file6 

	tempfile men 
	save `men', replace 

	// NOTE: All Peruvian DHS', PHL 2013, SEN 2012-2013, TJK 2012, YEM 2013 don't have male files


***********************************************************************************
** APPEND ALL MODULES
***********************************************************************************

// Idea here is that we have information in the household module about frequency within that household of being exposed to second-hand smoke and then we have male and female smoking status in the gender-specific modules so we're merging the male and female modules onto the household module in order to calculate prevalence 


	// First merge women's modules 

		// Base file should be women's file and should merge onto household module 
		use `household', clear 
		rename hv001 v001
		rename hv002 v002
		rename hv003 v003
		save `household', replace

		// split file path 
		split file, p("/") 
		gen filepath = file1 + "/" + file2 + "/" + file3 + "/" + file4 + "/" + file5
		drop file1 file2 file3 file4 file5 file6 

		save `household', replace

		levelsof filepath, local(filepaths)

		local counter = 1 

		foreach filepath of local filepaths { 

			if regexm("`filepath'", "PER/2012") { 
				use `household', clear 
				di "merging women and household module for file `filepath'" 
				keep if filepath == "`filepath'" 
				 _strip_labels _all 
				tostring v003, replace
				gen caseid = hhid + " 0" + v003

				di `counter'
				tempfile hh`counter'
				save "`hh`counter''", replace

				use `women', clear 
				keep if filepath == "`filepath'"

				merge m:1 caseid using "`hh`counter''", keep(3) nogen force
			}

			else { 
				use `household', clear 
				di "merging women and household module for file `filepath'" 
				keep if filepath == "`filepath'"
				di `counter'
				tempfile hh`counter'
				save "`hh`counter''", replace

				use `women', clear 
				keep if filepath == "`filepath'"

				merge m:1 v001 v002 using "`hh`counter''", keep(3) nogen
			}

			tempfile data_wn_merge_`counter'
			save `data_wn_merge_`counter'', replace
			local counter = `counter' + 1
			di "`counter'"

		} 

		// Append all together
		use `data_wn_merge_1', clear
			
			local max = `counter' -1
			forvalues x = 2/`max' {
				append using `data_wn_merge_`x''
			}

		tempfile women_appended
		save `women_appended', replace


// Second, merge men's modules 

	use `household', clear 
	rename v001 mv001 
	rename v002 mv002
	rename v003 mv003 

	tempfile household_male 
	save `household_male', replace 

	levelsof filepath, local(filepaths)

		local counter = 1 

		foreach filepath of local filepaths { 
			/*
			if regexm("`filepath'", "PER/2012") { 
				use `household_male', clear 
				di "merging men and household module for file `filepath'" 
				keep if filepath == "`filepath'" 
				 _strip_labels _all 
				tostring mv003, replace
				gen caseid = hhid + " 0" + mv003

				di `counter'
				tempfile hh`counter'
				save "`hh`counter''", replace

				use `men', clear 
				keep if filepath == "`filepath'"

				merge m:1 caseid using "`hh`counter''", keep(3) nogen force
			}
		*/
				use `household_male', clear 
				di "merging men and household module for file `filepath'" 
				keep if filepath == "`filepath'"
				di `counter'
				tempfile hh`counter'
				save "`hh`counter''", replace

				use `men', clear 
				keep if filepath == "`filepath'"

				cap merge m:1 mv001 mv002 using "`hh`counter''", keep(3) nogen
			

			tempfile data_mn_merge_`counter'
			save `data_mn_merge_`counter'', replace
			local counter = `counter' + 1
			di "`counter'"

		} 

		// Append all together
		use `data_mn_merge_1', clear
			
			local max = `counter' -1
			forvalues x = 2/`max' {
				append using `data_mn_merge_`x''
			}

		tempfile men_appended
		save `men_appended', replace




***********************************************************************************
** GENERATE RELEVANT EXPOSURE VARIABLES FOR FEMALE SHS CALCULATION
***********************************************************************************
	
// v463a     smokes cigarettes
// v463b     smokes pipe
// v463c	 uses chewing tobacco
// v463d	 uses snuff
// v463e     smokes cigars
// v463f     smokes water pipe/ nargile
// v463g     na - smokes country specific
// v463x     smokes other
// v463z     does not use tobacco
	
	use `women_appended', clear 
	recode v463a v463b v463e v463f v463g v463x (9 = .) // only want to include those that use smoked substances; not chewing tobacco or snuff 

	gen smoker = 1 if inlist(v463a, 1) | inlist(v463b, 1) | inlist(v463e, 1) | inlist(v463f, 1) | inlist(v463g, 1) | inlist(v463x, 1) 
	replace smoker = 0 if smoker != 1 & (inlist(v463a, 0) | inlist(v463b, 0) | inlist(v463e, 0) | inlist(v463f, 0) | inlist(v463g, 0) | inlist(v463x, 0))
	replace smoker = 0 if smoker == . & v463z == 1 

	// drop smokers because they are not considered susceptible to SHS 
	drop if smoker == 1 

	// replace main hv252 variable with the Peruvian-specific DHS variables that relate to second-hand smoke 

		//replace hv252 = sxh89 if sxh89 != . // Peru 2011 --> all missing
		//replace hv252 = sxh89 if sxh89 != . // Peru 2012 --> all missing

	// create SHS indicator based on frequency of smoking in the household question 
		// Quesion in most DHS' is hv252 (frequency at which household smokers smoke inside the house): 0 = never; 1 = daily; 2 = weekly; 3 = monthly; 4 = less than monthly; 9 = missing 

		recode hv252 (2 = 1) (3 = 0) (4 = 0) (9 = .) // daily (hv252 ==1) and weekly (hv252 ==2) exposure is considered "REGULAR" exposure to second-hand smoke 


		// PER 2003-2008
			replace hv252 = 1 if sh30 == 1 & sh3001 == 1  // smoker in the home and smoker smokes inside the house 
			replace hv252 = 0 if sh30 == 0 // no smoker in the home 
			replace hv252 = 0 if sh30 == 1 & sh3001 == 0 // smoker in the home but doesn't smoke in the house 

		// PER 2012 
			replace hv252 = 1 if sh78 == 1 & sh79 == 1 // smoker in the home and smoker smokes inside the home 
			replace hv252 = 0 if sh78 == 0 // no household members smoke 
			replace hv252 = 0 if sh78 == 1 & sh79 == 0 // smoker in the home but doesn't smoke in the house 

		// PER 2010 
			replace hv252 = 1 if sh87 == 1 & sh88 == 1 // smoker in the home and smoker smokes inside the home 
			replace hv252 = 0 if sh87 == 0 // no household members smoke 
			replace hv252 = 0 if sh87 == 1 & sh88 == 0 // smoker in the home but doesn't smoke in the house 

		rename hv252 shs 

// Set age groups
	rename v012 age
	egen age_start = cut(age), at(10(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
		
// Set survey weights
	rename v005 pweight 
	rename v021 psu 
	rename v022 strata 

	// replace strata 
	replace strata = 1 if strata == . 
	drop if pweight == 0 

	svyset psu [pweight=pweight], strata(strata)	

	tempfile allwomen
	save `allwomen', replace 

// Create empty matrix for storing calculation results
	mata 
		file = J(1,1,"todrop") 
		age_start = J(1,1,999)
		sample_size = J(1,1,999)
		mean_shs = J(1,1,999)
		se_shs = J(1,1,999)
	end	
	
// Loop through countries, sexes and ages and calculate secondhand smoke prevalence among nonsmokers using survey weights
		levelsof file, local(files)

		foreach file of local files {
			use `allwomen', clear
			keep if file == "`file'"
			
				foreach age of local ages {
				
					di in red  "file: `file' age `age'"
					count if file == "`file'" & age_start == `age' & shs != . 

					if `r(N)' > 0 { 

					svy linearized, subpop(if age_start == `age' & shs != .): mean shs
				
				** Extract exposure at home
						mata: age_start = age_start \ `age'
						mata: file = file \ "`file'" 
						mata: sample_size = sample_size \ `e(N_sub)'
						
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_shs = mean_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_shs = se_shs \ `se_scalar'
					}
				}
			}
			
	// Get stored prevalence calculations from matrix
		clear

		getmata file sample_size mean_shs se_shs age_start
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results

		recode se_shs (0 = .)  // Standard error should not be 0 so we will use sample size to estimate error instead

		tempfile mata_calculations_wn 
		save `mata_calculations_wn', replace

	// Fix naming of variables
		gen sex = 2 
		rename se_shs standard_error
		rename mean_shs mean
		gen source = "MACRO_DHS"

		split file, p("/")
		rename file4 ihme_loc_id 
		split file5, p("_") 
		rename file51 year_start 
		rename file52 year_end 
		replace year_end = year_start if year_end == "" 

		drop file1 file2 file3 file5 
		rename file6 filename

		tempfile women 
		save `women', replace 




***********************************************************************************
** GENERATE RELEVANT EXPOSURE VARIABLES FOR MALE SHS CALCULATION
***********************************************************************************

	use `men_appended', clear 
	recode mv463a mv463b mv463e mv463f mv463g mv463x (9 = .) // only want to include those that use smoked substances; not chewing tobacco or snuff 

	gen smoker = 1 if inlist(mv463a, 1) | inlist(mv463b, 1) | inlist(mv463e, 1) | inlist(mv463f, 1) | inlist(mv463g, 1) | inlist(mv463x, 1) 
	replace smoker = 0 if smoker != 1 & (inlist(mv463a, 0) | inlist(mv463b, 0) | inlist(mv463e, 0) | inlist(mv463f, 0) | inlist(mv463g, 0) | inlist(mv463x, 0))
	replace smoker = 0 if smoker == . & mv463z == 1 

	// drop smokers because they are not considered susceptible to SHS 
	drop if smoker == 1 

	// replace main hv252 variable with the Peruvian-specific DHS variables that relate to second-hand smoke 

		//replace hv252 = sxh89 if sxh89 != . // Peru 2011 --> all missing
		//replace hv252 = sxh89 if sxh89 != . // Peru 2012 --> all missing

	// create SHS indicator based on frequency of smoking in the household question 
		// Quesion in most DHS' is hv252 (frequency at which household smokers smoke inside the house): 0 = never; 1 = daily; 2 = weekly; 3 = monthly; 4 = less than monthly; 9 = missing 

		recode hv252 (2 = 1) (3 = 0) (4 = 0) (9 = .) // daily (hv252 ==1) and weekly (hv252 ==2) exposure is considered "REGULAR" exposure to second-hand smoke 

		rename hv252 shs 

// Set age groups
	rename mv012 age
	egen age_start = cut(age), at(10(5)120)
	replace age_start = 80 if age_start > 80 & age_start != .
	levelsof age_start, local(ages)
	drop age
		
// Set survey weights
	rename mv005 pweight 
	rename mv021 psu 
	rename mv022 strata 

	// replace strata 
	replace strata = 1 if strata == . 
	drop if pweight == 0 

	svyset psu [pweight=pweight], strata(strata)	

	tempfile allmen
	save `allmen', replace 

// Create empty matrix for storing calculation results
	mata 
		file = J(1,1,"todrop") 
		age_start = J(1,1,999)
		sample_size = J(1,1,999)
		mean_shs = J(1,1,999)
		se_shs = J(1,1,999)
	end	
	
// Loop through countries, sexes and ages and calculate secondhand smoke prevalence among nonsmokers using survey weights
		levelsof file, local(files)

		foreach file of local files {
			use `allmen', clear
			keep if file == "`file'"
			
				foreach age of local ages {
				
					di in red  "file: `file' age `age'"
					count if file == "`file'" & age_start == `age' & shs != . 

					if `r(N)' > 0 { 

					svy linearized, subpop(if age_start == `age' & shs != .): mean shs
				
				** Extract exposure at home
						mata: age_start = age_start \ `age'
						mata: file = file \ "`file'" 
						mata: sample_size = sample_size \ `e(N_sub)'
						
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_shs = mean_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_shs = se_shs \ `se_scalar'
					}
				}
			}
			
	// Get stored prevalence calculations from matrix
		clear

		getmata file sample_size mean_shs se_shs age_start
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results

		recode se_shs (0 = .)  // Standard error should not be 0 so we will use sample size to estimate error instead

		tempfile mata_calculations_mn 
		save `mata_calculations_mn', replace

	// Fix naming of variables
		gen sex = 1 
		rename se_shs standard_error
		rename mean_shs mean
		gen source = "MACRO_DHS"

		split file, p("/")
		rename file4 ihme_loc_id 
		split file5, p("_") 
		rename file51 year_start 
		rename file52 year_end 
		replace year_end = year_start if year_end == "" 

		drop file1 file2 file3 file5 
		rename file6 filename

		tempfile men 
		save `men', replace 


***********************************************************************************
** GENERATE RELEVANT EXPOSURE VARIABLES FOR CHILD UNDER 5 SHS CALCULATION
***********************************************************************************
	
	use `household', clear 

	// expand estimates based on the number of children 
	rename hv014 under_5 
	drop if under_5 == 0 // no children under 5 in the house 

	expand under_5, gen(child)

	recode hv252 (2 = 1) (3 = 0) (4 = 0) (9 = .) // daily (hv252 ==1) and weekly (hv252 ==2) exposure is considered "REGULAR" exposure to second-hand smoke 

	// A few weird anomalies

		// PER 2003-2008
			replace hv252 = 1 if sh30 == 1 & sh3001 == 1  // smoker in the home and smoker smokes inside the house 
			replace hv252 = 0 if sh30 == 0 // no smoker in the home 
			replace hv252 = 0 if sh30 == 1 & sh3001 == 0 // smoker in the home but doesn't smoke in the house 

		// PER 2012 
			replace hv252 = 1 if sh78 == 1 & sh79 == 1 // smoker in the home and smoker smokes inside the home 
			replace hv252 = 0 if sh78 == 0 // no household members smoke 
			replace hv252 = 0 if sh78 == 1 & sh79 == 0 // smoker in the home but doesn't smoke in the house 

		// PER 2010 
			replace hv252 = 1 if sh87 == 1 & sh88 == 1 // smoker in the home and smoker smokes inside the home 
			replace hv252 = 0 if sh87 == 0 // no household members smoke 
			replace hv252 = 0 if sh87 == 1 & sh88 == 0 // smoker in the home but doesn't smoke in the house 

	rename hv252 shs

	// Set survey design (just use those from the household?) 
	rename hv005 pweight 
	rename hv021 psu 
	rename hv022 strata 

	// replace strata 
	replace strata = 1 if strata == . 
	drop if pweight == 0 

	svyset psu [pweight=pweight], strata(strata)	


	tempfile child_appended 
	save `child_appended', replace


	// Create empty matrix for storing calculation results
	mata 
		file = J(1,1,"todrop") 
		sample_size = J(1,1,999)
		mean_shs = J(1,1,999)
		se_shs = J(1,1,999)
	end	

	// Loop through countries, sexes and ages and calculate secondhand smoke prevalence among nonsmokers using survey weights
		levelsof file, local(files)

		foreach file of local files {
			use `child_appended', clear
			keep if file == "`file'"
							
			di in red  "file: `file'"
			count if file == "`file'" & shs != . 

				if `r(N)' > 0 { 

				svy linearized, subpop(if file == "`file'" & shs != .): mean shs
				
				** Extract exposure at home
						mata: file = file \ "`file'" 
						mata: sample_size = sample_size \ `e(N_sub)'
						
						matrix mean_matrix = e(b)
						local mean_scalar = mean_matrix[1,1]
						mata: mean_shs = mean_shs \ `mean_scalar'
						
						matrix variance_matrix = e(V)
						local se_scalar = sqrt(variance_matrix[1,1])
						mata: se_shs = se_shs \ `se_scalar'
					}
				}
			
			
	// Get stored prevalence calculations from matrix
		clear

		getmata file sample_size mean_shs se_shs 
		drop if _n == 1 // drop top row which was a placeholder for the matrix created to store results
		recode se_shs (0 = .) // can't have a standard error of 0 so want to use ESS instead using sample size 
		rename mean_shs mean 
		rename se_shs standard_error

		gen age_start = 0 
		gen age_end = 5 
		gen sex = 3 

		split file, p("/")
		rename file4 ihme_loc_id 
		split file5, p("_") 
		rename file51 year_start 
		rename file52 year_end 
		replace year_end = year_start if year_end == "" 

		drop file1 file2 file3 file5 
		rename file6 filename


		tempfile children 
		save `children', replace 


// Append female and male observations 
	
	// 37 female DHS and 30 male DHS 
	append using `men' `women' 
	replace age_end = age_start + 4 if age_end == . 

	tempfile all 
	save `all', replace

// Merge on location ids 
	
	merge m:1 ihme_loc_id using `countrycodes', keep(3) nogen

// Save file 
	sort file sex age_start
	save "`out_dir'/dhs_prepped.dta", replace 



// KENYA DHS 2014
