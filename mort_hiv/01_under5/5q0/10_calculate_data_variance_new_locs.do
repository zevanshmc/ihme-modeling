** Date:             Commented and updated on 4/19/2012, updated for vr-bias code relocation on 10/29/2012

** Purpose:        This code produces gpr_5q0_input.txt which is the fundamental input dataset for the 5q0 GPR process and prediction  models
**                    This file contains the raw data estimates for 5q0 as well as the standard errors (calculated here) and a dummy for VR

** set up stata
	clear
	capture cleartmp
	capture restore, not
	capture log close
	macro drop all 
	set more off
	set memory 1000m

** test system type
	if (c(os)=="Unix"){
		global j ""
		global code_dir ""
		global rnum = 1
		global hivsims = 0
		set odbcmgr unixodbc                                          
	}
	else{ 
		global j ""
		global code_dir ""
		global rnum = 1
		global hivsims = 0
	}
	
di $rnum
di $hivsims

di "$rnum"
di "$hivsims"

** prep file for data variance in summary birth histories
	insheet using "SBH_method_pv.csv", clear
	keep if type == "out" & (method =="MAC" | method =="combined")
	drop if model == "ever-married"
	drop if reftime == "Overall"
	keep reftimecat method sd_res_mean
	gen loweryear = substr(reftime,1,2)
	destring loweryear, replace
	expand 2
	sort method loweryear
	bys method reftime: replace loweryear = loweryear + 1 if _n == 2
	drop reftime
	rename loweryear reftime
	replace sd_res_mean = sd_res_mean/1000
	rename sd_res_mean sdq5_sbh
	
	** for merge later on...
	gen type = "indirect" if method == "combined"
	replace type = "indirect, MAC only" if method == "MAC"
	
	tempfile indirect_sd
	save `indirect_sd', replace

** prep under-5 population from the standard mortality group population file
	use "population_gbd2015.dta", clear 
	keep if age_group_id <= 5 & age_group_id >=2 & sex == "both"
	collapse (sum) pop, by(ihme_loc_id year)
	rename pop pop0to4
	keep ihme_loc_id year pop0to4
	sort ihme_loc_id year
	tempfile u5pop
	save `u5pop', replace

** bring in 5q0 database (vr data has already been adjusted for completeness)
	if ($hivsims) insheet using "prediction_model_results_all_stages_$rnum.txt", clear 
	else insheet using "prediction_model_results_all_stages.txt", clear

** Assure that only years past 1950 are included in the model
	assert year >= 1950

** format CBH standard error variable
	destring vr, replace force
	destring log10sdq5, replace force
	rename  log10sdq5 log10sdq5_cbh

** merge in under-5 population
	gen tempyear = year
	replace year = floor(year)
	replace sourceyr = string(year) if sourceyr == ""
	merge m:1 ihme_loc_id year using `u5pop'
	drop if _merge == 2 
	drop _merge

** Population Adjustments
** IND SRS: .006 from "Adult Mortality: Time for a Reappraisal"
	replace pop0to4 = pop0to4*.006 if (substr(ihme_loc_id,1,3) == "IND") & (source == "SRS" | source == "India SRS")
** BGD SRS: .003 from UN documentation (1990) 
	replace pop0to4 = pop0to4*.003 if ihme_loc_id == "BGD" & regexm(source, "SRS") != 0
** PAK SRS
	replace pop0to4 = pop0to4*.01 if ihme_loc_id == "PAK" & regexm(source, "SRS") != 0 
** CHN DSP: correct population
	preserve 
	insheet using "pop_covered_survey.csv", clear 
	cap rename iso3 ihme_loc_id
	keep if ihme_loc_id == "CHN"
	replace ihme_loc_id = "CHN_44533" if ihme == "CHN"
	keep year prop sourcename ihme_loc_id 
	rename sourcename source 
	tempfile dsp_pop
	save `dsp_pop', replace
	restore
	replace source = "DSP" if strpos(source,"DSP") != 0 & ihme_loc_id == "CHN_44533"
	merge m:1 year source ihme_loc_id using `dsp_pop'
	drop if _m == 2
	drop _m
	replace pop0to4 = pop0to4*prop if ihme_loc_id == "CHN_44533" & strpos(source,"DSP") != 0 & prop != .
	drop prop
** CHN Fertility Survey
	replace pop0to4 = pop0to4*.001 if ihme_loc_id == "CHN_44533" & source == "1 per 1000 Survey on Fertility and Birth Control"
** CHN Population Change Survey
	replace pop0to4 = pop0to4*.001 if ihme_loc_id == "CHN_44533" & source == "1 per 1000 Survey on Pop Change"
** CHN 1% Intra-Census Survey 
	replace pop0to4 = pop0to4*.01 if ihme_loc_id == "CHN_44533" & source == "1% Intra-Census Survey"
** China province DSP population
	** bring in dataset 
	preserve
	use "DSP_prov_u5pop.dta", clear
	keep year u5pop iso3
	gen source = "China DSP"
	tempfile dsp_prov_pop
	save `dsp_prov_pop', replace
	qui do "get_locations.ado" 
	get_locations
	rename local_id_2013 iso3
	keep iso3 ihme_loc_id
	drop if iso3 == ""
	merge 1:m iso3 using `dsp_prov_pop'
	drop if _m == 1 
	drop _m
	drop iso3
	save `dsp_prov_pop', replace
	restore
	merge m:1 year ihme_loc_id using `dsp_prov_pop'
	replace pop0to4 = u5pop if strpos(source, "DSP") & ihme_loc_id != "CHN_44533"
	drop if _m == 2
	drop _m u5pop
	
	** go back to half years
	drop year
	rename tempyear year

	** merge the indirect data variance information in preparation for stderr calcs below
	** first need to calculation reftime for the individual datapoints
	destring sourceyr, replace force
	gen reftime = sourceyr - year
	replace reftime = 0 if reftime <1
	replace reftime = round(reftime)
	replace reftime = 25 if reftime > 25 & type == "indirect"
	replace reftime = 21 if reftime > 21 & type == "indirect, MAC only"

	
	** now merging in the indirect std errors
	merge m:1 type reftime using `indirect_sd'
	drop _m
	drop if ihme_loc_id == ""
	
** for countries with 1 data point (only PRK as of now) duplicate the point 25% above and below to create plausible confidence intervals 
	expand 3 if ihme_loc_id == "PRK"
	destring mort, replace force
	bysort ihme_loc_id mort: replace mort = mort*1.25 if _n == 2 & ihme_loc_id == "PRK"
	bysort ihme_loc_id: replace mort = mort*0.75 if _n == 3 & ihme_loc_id == "PRK"

** need countries with 0 as 5q0 estimate to be non-zero for the log transformation
	replace mort = .0001 if mort <= 0

*************************
** calculate standard errors
*************************
** first need to convert 5q0 data into Mx space (Binomial distribution)
** the conversion eqn is 5q0 = 1 - e^(-5*5m0) -- solve for 5m0 to get conversion below
	gen m5 = (log(-mort+1))/(-5)

** calculate data variance for 5m0
	gen variance = (m5*(1-m5))/pop0to4 if strpos(cat,"vr") != 0 | cat == "census"
	
	** convert back to qx space using the delta method
	** here the equation is 5q0' = 5*(exp(-5*5m0))^2
	** need to multiply converted qx*var(mx) to get var(qx)
	replace variance = variance *((5*exp(-5*m5))^2)
	
	** add in variance for the indirects
	replace variance = sdq5_sbh^2 if sdq5_sbh != .
	
	** add in log10 standard errors from CBH
	gen log10_var = log10sdq5_cbh^2
	
	** delta method - convert from log10(q5) variance to q5 variance
	replace variance = log10_var*(mort*log(10))^2 if log10_var != .
	
	replace variance = . if strpos(source, "RapidMortality")
	
** *************************************************************************************
** add in variance from complete birth histories to summary birth histories according to the following
** 1. CBH variance from the same survey
** 2. Average CBH variance from the same survey series within a country
** 3. Average CBH variance from the same series within (A) region, (B) super-region, (C) global
** 4. For one-off surveys: Average CBH variance from the same souce-type within (A) region, (B) super-region, (C) global
** 5. Average CBH variance of everything else

preserve

quietly do "/SBH_variance_addition.do"
tempfile sbh_all
save `sbh_all', replace

restore

merge m:m ihme_loc_id sourcetype super_region_name region_name source sourceyr graphingsource using `sbh_all'
replace variance = var_tot if var_tot != . & regexm(sourcetype, "SBH")
drop var_tot _m add_var

	
**************************************************************************************************
	** for China national and provinces, use birth numbers and the binomial distribution to calculate the variance in qx space
	preserve
	
	levelsof source if ihme_loc_id == "CHN_44533" & regexm(source,"Maternal"), local (chnsource)
	
	levelsof source if ihme_loc_id == "CHN_491" & regexm(source, "MCHS"), local (sub_chnsource)
	
	use "/NATIONAL_MATERNAL_AND_CHILD_HEALTH_SURVEILLANCE_SYSTEM/CHN_MCHS_1996_2012_BIRTHS_DEATHS_Y2013M10D08.DTA", clear
	keep year birth_total code2010
	gen prov = floor(code2010/10000) 
	tempfile mchs_births
	save `mchs_births', replace
	
	** get codebook to go from province number to iso3 
	insheet using "prov_map.csv", clear
	keep prov iso3
	merge 1:m prov using `mchs_births'
	drop _m
	
	** get total birth numbers by province
	collapse (sum) birth_total, by(year iso3)
	keep year iso3 birth_total
	gen source = `sub_chnsource'
	save `mchs_births', replace
	
	** get total birth numbers for China national
	collapse (sum) birth_total, by(year)
	gen iso3 = "CHN"
	gen source = `chnsource'
	append using `mchs_births'
	
	replace year = year+0.5
	save `mchs_births', replace
	
	qui do "get_locations.ado" 
	get_locations
	rename local_id_2013 iso3
	keep iso3 ihme_loc_id
	drop if iso3 == ""
	merge 1:m iso3 using `mchs_births'
	drop if _m == 1 
	drop _m
	drop iso3
	replace ihme_loc_id = "CHN_44533" if ihme == "CHN"
	save `mchs_births', replace
	
	** merge birth numbers into whole dataset
	restore
	merge m:1 year ihme_loc_id source using `mchs_births'
	drop if _m == 2
	drop _m 
	
	** and now generate variance
	replace variance = (mort*(1-mort))/birth_total if source == `chnsource' | source == `sub_chnsource'
	
	** replace variance in those years with 1997 variance
	** some of this will change when Haidong gets data
	levelsof variance if ihme_loc_id == "CHN_44533" & year == 1997.5 & source == `chnsource', local (chn_v97)
	replace variance = `chn_v97' if source == `chnsource' & year < 1996.5 & birth_total == .
	
	** if still missing birth numbers for years after 2011, use that year's data variance
	levelsof variance if ihme_loc_id == "CHN_44533" & year == 2011.5 & source == `chnsource', local (chn_v11)
	replace variance = `chn_v11' if source == `chnsource' & year >2012 & birth_total == .
	
*******************************************************************************************************************	
	
	** generate stderrs for next part
	gen stderr = sqrt(variance)
	
****************************
** fill in missing standard errors
****************************
	** track which of the below modifications are made using mod_stderror
	gen mod_stderror = "0. stderror directly calculated using births/ cbh or sbh systems" if stderr != . & category != "other"

	** take max stderror from the non-VR points and use this as the standard error for data points missing a stderror (by country)
	bysort location_name: egen maxstderr = max(stderr) if vr == 0
	
	** the purpose of this is to generate this max standard error replacement for ZAF VR where we don't have pop/deaths because it's from a report
	** it doesn't actually change anything (because VR SE is small), but it get's around a STATA thing where it doesn't give you a maxstderr value for places where vr == 1
	** (above, we only really need to get the max where vr == 0, not only generate the maxstderr variable where vr == 0)
	bysort location_name: egen maxstderr1 = max(maxstderr)
	replace maxstderr = maxstderr1 if maxstderr == .
	drop maxstderr1
	
	gen changed = 1 if stderr == .
	replace stderr = maxstderr if stderr == .
	replace mod_stderror = "1. max by country non-VR" if stderr == maxstderr & changed == 1
	drop maxstderr changed

	** find the max stderror from the non-VR points in a region, use this as the standard error for all points in the other category that are still missing
	bysort region_name: egen maxstderr = max(stderr) if vr == 0
	gen changed = 1 if stderr == .
	replace stderr = maxstderr if stderr == .
	replace mod_stderror = "2. max by region non-VR" if stderr == maxstderr & changed == 1 
	drop maxstderr changed
	

*******************************
** Add variance to biased VR data -- only additive in variance space
*******************************
   destring biasvar, force replace
   ** also convert biasvar to q5 instead of log10(q5) space
   replace biasvar = biasvar*(mort*log(10))^2 
   
   replace variance = variance + biasvar if corr_code_bias == "TRUE"
   ** replace the stderrors for these points which are now including vr bias variance
   replace stderr = sqrt(variance) if corr_code_bias == "TRUE"
   
   sort ihme_loc_id source1 year
   
****************************
** Add variance from all survey RE standard deviation by source.type
****************************
	replace variance = stderr ^2

**  add in variance by source.type in qx not log10qx space
	destring varstqx, replace force
	replace variance = variance + varstqx if (category != "vr_unbiased") 

	replace variance = variance + varstqx if strpos(source, "RapidMortality") 
	replace variance = 0.5*variance if strpos(source, "RapidMortality")
	
 
	cap assert variance != . if data == 1
	if (_rc) {
		replace variance = .000005 if variance == . & data == 1
	}
	replace stderr = sqrt(variance)
	
****************************
** Formatting
****************************

** consolidate the 2 dhs categories (dhs direct and dhs indirect) into a single source category
	replace cat = "dhs" if strpos(cat,"dhs") != 0

** add in papfam in as a source
	replace category = "papfam" if regexm(source, "PAPFAM") | regexm(source, "PAPCHILD")

** assert that no observations are missing a mortality estimate
	assert mort != . if data == 1
	sort ihme_loc_id category year

** final formatting
	gen filler = "NA"
	order ihme_loc_id location_name year mort stderr category region_name filler ptid
	
	** standard logit
	gen logit_mort = log(mort/(1-mort))
	gen logit_var = variance * (1/(mort*(1-mort)))^2 
	
	assert logit_var != . if data == 1

** verify that we only include the desired locations
	tempfile final
	save `final', replace
	get_locations	
	keep if level_all == 1
	keep ihme level_all
	tempfile loc_verify
	save `loc_verify', replace
	merge 1:m ihme_loc_id using `final'
	assert _m == 3
	drop _m level_all
	
** save final prepped file for GPR process
	if ($hivsims) outsheet super_region_name region_name ihme_loc_id year ldi_id maternal_educ hiv data category vr mort mort2 logit_mort mse pred1b resid pred2resid pred2final ptid source1 reference log10sdq5 biasvar logit_var using "gpr_5q0_input_$rnum.txt", comma replace 
	else outsheet super_region_name region_name ihme_loc_id year ldi_id maternal_educ hiv data category vr mort mort2 logit_mort mse pred1b resid pred2resid pred2final ptid source1 reference log10sdq5 biasvar logit_var using "gpr_5q0_input.txt", comma replace

	** save an archived version for reference
	if (!$hivsims) outsheet super_region_name region_name ihme_loc_id year ldi_id maternal_educ hiv data category vr mort mort2 logit_mort mse pred1b resid pred2resid pred2final ptid source1 reference log10sdq5 biasvar logit_var using "gpr_5q0_input_`c(current_date)'.txt", comma replace 

** close log
	capture log close