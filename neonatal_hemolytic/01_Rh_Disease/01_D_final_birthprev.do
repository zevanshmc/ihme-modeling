
 /* **************************************************************************
NEONATAL HEMOLYTIC MODELING
PART 1: RH DISEASE
Part D: Final birth prevalence calculations
6.9.14

The hemolytic modeling process is described in detail in the README in the 
hemolytic code folder.  This script completes the fourth and final step of modeling 
kernicterus due to Rh Disease: combining the results of prior steps to get a final 
birth prevalence of kernicterus. 

Copied from the README:
	4. Birth Prevalence and Kernicterus Calculation
		a. We multiply the rhogam adjusted births from part 2 by the notfirst birth order proportions from part 3 to give the 	number of children with Rh compatibility who did not receive Rhogam and who were not firstborn-- this is the true 	  population at risk of Rh disease:

			rh_disease_count = rhogam_adjusted_births * notfirst_birth_prop

			NOTE: dividing this number by births gives rh_birth_prev, which is used in part D.

		b. Zipursky et al. found that only 15% (13.3, 19.1%) of children at risk of EHB actually advance to that stage.  We make that 		adjustment:

			rh_ehb_count = rh_disease_count * 0.15

		c. We then divide this birth count number by births to get birth prevalence:

			rh_ehb_prev = rh_ehb_count / births

		d. Kernicterus calculation: The proportion of children with EHB who go on to have kernicterus is 0.0725 (0.038, 0.112)	 (Mollison, Walker). We multiply EHB birth prevalence by this proportion to get the birth prevalence of kernicterus 	due to rh disease.

			rh_kern_prev = rh_ehb_prev * 0.0725 

		This concludes the Rh disease portion of hemolytic modeling. 
	
******************************************************************************/

clear all
set more off
set graphics off
set maxvar 32000


/*  //////////////////////////////////////////////
		WORKING DIRECTORY
////////////////////////////////////////////// */ 

// priming the working environment 
	if c(os) == "Windows" {
		local j "J:"
		// Load the PDF appending application
		quietly do "`j'/Usable/Tools/ADO/pdfmaker_acrobat11.do"
	}
	if c(os) == "Unix" {
		local j "/home/j"
		ssc install estout, replace 
		ssc install metan, replace
	} 
	
// functions
run "J:\WORK\10_gbd\00_library\functions\fastpctile.ado"
run "J:\WORK\10_gbd\00_library\functions\get_location_metadata.ado"

// directories 	
	local working_dir = "`j'/WORK/04_epi/02_models/01_code/06_custom/neonatal/data/02_analysis/neonatal_hemolytic/01_rh_disease"
	local incom_pregs_dir = "`working_dir'/01_B_rhogam_adjustment/rhogam_adjusted_pregnancies_all_draws.dta"
	local notfirst_prev_dir = "`working_dir'/01_C_birth_order/notfirst_birth_prev_all_draws.dta"
	local log_dir = "`j'/temp/User/neonatal/logs/neonatal_hemolytic"
	local out_dir "`working_dir'/01_D_final_birthprev"
	capture mkdir "`out_dir'"
	capture mkdir "$log_dir"
	
	local plot_dir "`out_dir'/time_series"
	capture mkdir "`plot_dir'"
	
// Create timestamp for logs
    local c_date = c(current_date)
    local c_time = c(current_time)
    local c_time_date = "`c_date'"+"_" +"`c_time'"
    display "`c_time_date'"
    local time_string = subinstr("`c_time_date'", ":", "_", .)
    local timestamp = subinstr("`time_string'", " ", "_", .)
    display "`timestamp'"

	
	//log
	capture log close
	log using "`log_dir'/01_D_final_birthprev_`timestamp'.smcl", replace
	
/* ///////////////////////////////////////////////////////////
// RH DISEASE BIRTH PREVALENCE CALCULATIONS, PART IV: FINAL CALCS
// Multiply Rhogam-adjusted births from part B by the porportion 
// of children who aren't firstborn from part C, then multiply 
// by .15 for a final result.
// Also: Multiply by 0.0725 (0.038, 0.112) to get modsev impairment prop
///////////////////////////////////////////////////////////// */

local plot_births = 1

//1. Rhogam- Adjusted Pregnancies 
	di in red "importing rhogam-adjusted incompatible pregnancy data"
	use "`incom_pregs_dir'", clear
	rename draw* incompatible_draw*

//2. Merge on notfirst birth order prevalence 
	di in red "importing not-firstborn birth prevalence"
	merge m:1 location_id year using "`notfirst_prev_dir'", keep(3) nogen // NOTE - two location_ids are in notfirst_prev_dir and NOT incom_pregs_dir (6 and 4749)
	rename draw* birth_order_draw*

//3. Define scalars
// we need to multiply these draws by two scalars(with uncertainty):
// the proportion of rh isoimmunized who will develop EHB: 
// 0.15 ( 0.133, 0.191)
// and the proportion of EHB babies who will go on to develop kernicterus:
// 0.0725 (0.038, 0.112)
// To get proper uncertainty bounds for both of these, we define the parameters
// of a beta distribution for them, and draw from that beta distribution to get 
// the scalar of use when looping through draws.

	di in red "calculating scalar parameters"
	local ehb_scalars 0.15 0.133 0.191
	local kern_scalars 0.0725 0.038 0.112

	foreach scalar_type in ehb kern{
		di in red "finding scalar parameters for `scalar_type'"
		local scalar_mean : word 1 of ``scalar_type'_scalars'
		local scalar_lower : word 2 of ``scalar_type'_scalars'
		local scalar_upper : word 3 of ``scalar_type'_scalars'
		local scalar_se = (`scalar_upper' - `scalar_lower')/(2*1.96)
		local count_n = (`scalar_mean' * (1-`scalar_mean') ) / `scalar_se'^2
		local `scalar_type'_alpha = `count_n' * `scalar_mean'
		local `scalar_type'_beta = `count_n' * (1-`scalar_mean')
		di in red "for `scalar_type', scalar_se is `scalar_se', count is `count_n', alpha is ``scalar_type'_alpha', beta is ``scalar_type'_beta'"
	}

	
// 4. Run calculations:
// 		Multiply adjusted pregnancies by birth order proportions, then by scalars
	forvalues i=0/999{

		if mod(`i', 100)==0{
							di in red "working on number `i'"
						}
	
		//find scalars
		local ehb_scalar = rbeta(`ehb_alpha', `ehb_beta')
		local kern_scalar = rbeta(`kern_alpha', `kern_beta')

		//multiply by scalars, divide by births to get ehb and kernicterus prevalence  
		gen ehb_draw_`i' = (incompatible_draw_`i' * birth_order_draw_`i' * `ehb_scalar') / births
		gen kernicterus_draw_`i' =  ehb_draw_`i' * `kern_scalar'
		drop incompatible_draw_`i' birth_order_draw_`i'
		
	}
	
//5. Save ehb and kern, get summary stats

	foreach disease_type in ehb kernicterus{
		//all draws
		preserve
			keep ihme_loc_id year sex location_id `disease_type'_draw*
			rename `disease_type'_draw* draw*
			save "`out_dir'/rh_disease_`disease_type'_all_draws.dta", replace	
			export delimited using "`out_dir'/rh_disease_`disease_type'_all_draws.csv", replace
		
		//summary stats	
			
			egen mean = rowmean(draw*)
			fastpctile draw*, pct(2.5 97.5) names(lower upper)
			drop draw*

			sort location_id year sex 
			save "`out_dir'/rh_disease_`disease_type'_summary_stats.dta", replace
			export delimited using "`out_dir'/rh_disease_`disease_type'_summary_stats.csv", replace
		restore
		
	}

//PLOTTING
if `plot_births'==1{

	// get location metadata 
	get_location_metadata, location_set_id(9) clear
	tempfile location_data
	save `location_data'

	use "`out_dir'/rh_disease_kernicterus_summary_stats.dta", clear
	merge m:1 location_id using `location_data', keep(3) nogen

	tostring sex, replace
	replace sex = "Males" if sex == "1"
	replace sex = "Females" if sex == "2"
	
		//for ylabeling 
		qui sum mean
		local max_val = r(max)

		pdfstart using "`plot_dir'/rh_disease_kernicterus_time_series.pdf"
		drop if sex == "3"
		replace location_name = subinstr(location_name,"'","",.)
		levelsof location_name, local(location_name_list)
		
		foreach location_name of local location_name_list {			
			di in red "plotting for `location_name'"
					
			twoway (line mean year if location_name == "`location_name'", lcolor(purple) lwidth(*1.75)  ) (line lower year if location_name == "`location_name'", lcolor(purple) lpattern(dash) lwidth(*1.75)  ) (line upper year if location_name == "`location_name'", lcolor(purple) lpattern(dash) lwidth(*1.75)  ), by(sex) title("Kernicterus Bprev, `location_name'") legend(order(1 2) label(1 "Kernicterus Birth Prevalence") label(2 "95%CI")) xlabel(1990(10)2015)
			pdfappend
			}
				
		pdffinish, view
}
	
	
	

	
	

	
	
	
	
	
