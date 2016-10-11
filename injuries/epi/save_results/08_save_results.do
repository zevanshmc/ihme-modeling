// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************

// Description:	Submit jobs to run shared save_results function to upload final results to Epi database 

// *********************************************************************************************************************************************************************
// *********************************************************************************************************************************************************************
// LOAD SETTINGS FROM MASTER CODE (NO NEED TO EDIT THIS SECTION)

	// prep stata
	clear all
	set more off
	set mem 2g
	set maxvar 32000
	if c(os) == "Unix" {
		global prefix "/home/j"
		set odbcmgr unixodbc
	}
	else if c(os) == "Windows" {
		global prefix "J:"
	}
	if "`1'" == "" {
		local 1 /snfs1/WORK/04_epi/01_database/02_data/_inj/04_models/gbd2015
		local 2 /share/injuries
		local 3 2016_02_08
		local 4 "08"
		local 5 save_results

		local 8 "/share/code/injuries/ngraetz/inj/gbd2015"
	}
	// base directory on J 
	local root_j_dir `1'
	// base directory on clustertmp
	local root_tmp_dir `2'
	// timestamp of current run (i.e. 2014_01_17)
	local date `3'
	// step number of this step (i.e. 01a)
	local step_num `4'
	// name of current step (i.e. first_step_name)
	local step_name `5'
	// step numbers of immediately anterior parent step (i.e. for step 2: 01a 01b 01c)
	local hold_steps `6'
	// step numbers for final steps that you are running in the current run (i.e. 11a 11b 11c)
	local last_steps `7'
    // directory where the code lives
    local code_dir `8'
	// directory for external inputs
	local in_dir "`root_j_dir'/02_inputs"
	// directory for output on the J drive
	local out_dir "`root_j_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for output on clustertmp
	local tmp_dir "`root_tmp_dir'/03_steps/`date'/`step_num'_`step_name'"
	// directory for standard code files
	adopath + "$prefix/WORK/10_gbd/00_library/functions"
		
local save_longterm 1
local save_shortterm 0

// PARALLELIZE BY ncode/platform where we have long-term prevalence
if `save_longterm' == 1 {
	insheet using "`code_dir'/como_inj_me_to_ncode.csv", comma names clear
		keep if longterm == 1 
		tempfile map
		save `map', replace
		levelsof n_code, l(ncodes)
	local code "`step_name'/save_results_parallel.do"
	foreach ncode of local ncodes {
		use `map' if n_code == "`ncode'", clear
		levelsof inpatient, l(platforms)
		foreach platform of local platforms {
			! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries	-N _`step_num'_`ncode'_`platform' -pe multi_slot 20 -l mem_free=40 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `ncode' `platform'"
		}
	}
}

// PARALLELIZE short-term YLD uploads by ncode/plat and ecode/plat
if `save_shortterm' == 1 {
	insheet using "`code_dir'/como_st_yld_mes.csv", comma names clear
	local code "`step_name'/save_results_shortterm_parallel.do"
	levelsof e_code, l(ecodes)
	levelsof n_code, l(ncodes)
	foreach ecode of local ecodes {
		local code_type = "ecode"
		forvalues platform = 0/1 {
			! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries	-N _`step_num'_`ecode'_`platform' -pe multi_slot 20 -l mem_free=40 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `code_type' `ecode' `platform'"
		}
	}
	foreach ncode of local ncodes {
		local code_type = "ncode"
		forvalues platform = 0/1 {
			! qsub -e /share/temp/sgeoutput/ngraetz/errors -o /share/temp/sgeoutput/ngraetz/output -P proj_injuries	-N _`step_num'_`ncode'_`platform' -pe multi_slot 20 -l mem_free=40 "`code_dir'/stata_shell.sh" "`code_dir'/`code'" "`root_j_dir' `root_tmp_dir' `date' `step_num' `step_name' `code_dir' `code_type' `ncode' `platform'"
		}
	}
}

// END

