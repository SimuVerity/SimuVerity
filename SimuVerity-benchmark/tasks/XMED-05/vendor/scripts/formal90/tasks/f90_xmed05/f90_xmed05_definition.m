function def = f90_xmed05_definition
%F90_XMED05_DEFINITION Direct-golden PACER contract.
root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
publicPath = fullfile(taskRoot, "public_spec.json");
officialPath = simuverity_official_scenarios_path();
public = jsondecode(fileread(publicPath));
official = jsondecode(fileread(officialPath));
def = struct;
def.id = "XMED05";
def.formal_id = "F90-XMED-05";
def.target_model_file = "F90_XMED_05.slx";
def.reference_root = fullfile(string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE")), ...
    "PACER.2.0");
def.reference_model = fullfile(def.reference_root, "models", "CLSfixed.slx");
def.reference_library = fullfile(def.reference_root, "Lib", "Libs.slx");
def.reference_file_presence = lower(string("present"));
def.library_file_presence = "present";
def.public_spec = publicPath;
def.official_scenarios = officialPath;
def.prompt = string(public.prompt);
def.scenarios = official.scenarios;
if iscell(def.scenarios), def.scenarios = [def.scenarios{:}]; end
def.weights = official.weights;
def.required_outputs = ["CardiacEGM", "PacingEvents"];
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
