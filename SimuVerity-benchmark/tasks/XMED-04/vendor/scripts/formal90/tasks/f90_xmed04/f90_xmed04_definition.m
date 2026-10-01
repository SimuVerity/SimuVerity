function def = f90_xmed04_definition
%F90_XMED04_DEFINITION Artificial-pancreas evaluation contract.
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
publicPath = fullfile(taskRoot, "public_spec.json");
scenarioPath = simuverity_official_scenarios_path();
public = jsondecode(fileread(publicPath));
scenarioContract = jsondecode(fileread(scenarioPath));
def = struct;
def.id = "XMED04";
def.formal_id = "F90-XMED-04";
def.target_model_file = "artificialPancreasWithFISTreeControl.slx";
def.reference_root = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
def.reference_model = string(getenv("SIMUVERITY_REFERENCE_MODEL_PATH"));
def.public_spec = publicPath;
def.official_scenarios = scenarioPath;
def.prompt = string(public.prompt);
def.scenarios = scenarioContract.scenarios;
def.weights = scenarioContract.weights;
def.required_outputs = [ ...
    "TrueGlucose_mg_dL", "ObservedGlucose_mg_dL", ...
    "InsulinInfusion_mU_min", "MealCarbohydrateRate_g_s", ...
    "AbsorbedGlucoseRate_mmol_s"];
def.runner = struct( ...
    "reference_model", def.reference_model, ...
    "public_spec", publicPath, ...
    "official_scenarios", scenarioPath);
end
