function def = f90_xcomm03_definition
%F90_XCOMM03_DEFINITION Direct-golden pulsed-radar STAP contract.
root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
publicPath = fullfile(taskRoot, "public_spec.json");
officialPath = simuverity_official_scenarios_path();
assert(isfile(publicPath) && isfile(officialPath), ...
    "SimuVerity:F90:XCOMM03:DefinitionAssets", ...
    "XCOMM03 public or official specification is missing.");
public = jsondecode(fileread(publicPath));
official = jsondecode(fileread(officialPath));
evaluationSubject = localEvaluationSubject();
referenceRoot = fullfile(taskRoot, "reference");
if evaluationSubject == "reference"
    referenceRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
    assert(isfolder(referenceRoot), "SimuVerity:F90:XCOMM03:ReferenceAssetRoot", ...
        "Evaluator-owned reference asset root is missing.");
end
referencePresence = localReferencePresence();

def = struct;
def.id = "XCOMM03";
def.formal_id = "F90-XCOMM-03";
def.target_model_file = "slexSTAPExample.slx";
def.reference_model = fullfile(referenceRoot, def.target_model_file);
def.reference_root = referenceRoot;
def.reference_file_presence = referencePresence;
def.public_spec = publicPath;
def.official_scenarios = officialPath;
def.prompt = string(public.prompt);
def.scenarios = official.scenarios;
def.weights = official.weights;
def.required_outputs = [ ...
    "ReceivedRangeResponse", ...
    "SuppressedRangeResponse", ...
    "AdaptiveWeights"];
def.runner = struct( ...
    "reference_model", def.reference_model, ...
    "public_spec", publicPath, ...
    "official_scenarios", officialPath);
end

function subject = localEvaluationSubject()
subject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XCOMM03:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function value = localReferencePresence()
value = lower(strtrim(string("present")));
assert(value == "present", "SimuVerity:F90:XCOMM03:ReferencePresence", ...
    "Task-bound reference file presence is missing or invalid.");
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
