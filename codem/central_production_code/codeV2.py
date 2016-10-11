'''
This is the CODEm master script.
My idea is that this will just implement the functions written in the actual
module files.
'''

from codem.Ensemble import Ensemble
import sys
import pandas as pd
import warnings
import numexpr as ne
import dill
warnings.filterwarnings("ignore", 'Mean of empty slice.')
pd.set_option('chained', None)
ne.set_num_threads(30)


model_version_id = sys.argv[1]

# Initiate a codem model and pull the necessary data from the database as well as other sources
codem_model = Ensemble(model_version_id, log_results=True)

# log missingness where data was expected or is of an unacceptable value ie pop <= 0 cf <= 0 etc
codem_model.log_data_errors()

# move the run location to the appropriate position
codem_model.move_run_location()

# adjust the input data to account for missingness
codem_model.adjust_input_data()

# run covariate selection
codem_model.covariate_selection()

# calculate the knockouts
codem_model.run_knockouts()

# run the linear model builds
codem_model.run_linear_model_builds()

# read in the space time models
codem_model.read_spacetime_models()

# apply spacetime smoothing
codem_model.apply_spacetime_smoothing()

# apply gaussian process smoothing
codem_model.apply_gp_smoothing()

# read in the linear models
codem_model.read_linear_models()

# calculate submodel predictive validity
codem_model.submodel_pv()

# calculate the optimal ensemble psi value
codem_model.optimal_psi()

# calculate the new ensemble pv
codem_model.ensemble_pv()

# generate draws from both model types
codem_model.linear_draws()
codem_model.gpr_draws()

# use the newly generated draws to calculate coverage in and out of sample
codem_model.calculate_coverage()

# write the results to their appropriate locations
codem_model.write_results()

# finish up with cleaning the code source and saving model object
codem_model.delete_data()
codem_model.cleanup_code_base()
dill.dump(codem_model, file("codem_model.p", "wb"))
