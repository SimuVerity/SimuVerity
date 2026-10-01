function def = f90_xcomm04_definition
%F90_XCOMM04_DEFINITION Minimal task definition for the shared runner.

root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
officialSpec = jsondecode(fileread(simuverity_official_scenarios_path()));
evaluationSubject = localEvaluationSubject();
referenceRoot = fullfile(taskRoot, "reference");
if evaluationSubject == "reference"
    referenceRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
    assert(isfolder(referenceRoot), "SimuVerity:F90:XCOMM04:ReferenceAssetRoot", ...
        "Evaluator-owned reference asset root is missing.");
end

def = struct;
def.formal_id = "F90-XCOMM-04";
def.public_id = "XCOMM04";
def.submission_model = "F90_XCOMM_04.slx";
def.task_root = taskRoot;
def.reference_root = referenceRoot;
def.reference_model = fullfile(def.reference_root, ...
    "HDLDPDwithLMSCoeffExample.slx");
def.reference_file_presence = localReferencePresence();
def.support_file = fullfile(def.reference_root, "PAcoefficients.mat");
def.support_file_presence = ...
    "present";
def.official_scenarios = simuverity_official_scenarios_path();
def.scenarios = officialSpec.scenarios;
def.required_outputs = [ ...
    "TxBaseband", "PredistortedDrive", "PaOutput", ...
    "AdaptiveCoefficients", "AdaptationError"];
def.sample_rate_hz = double(officialSpec.simulation.nominal_sample_rate_hz);
def.policy_id = string(officialSpec.scoring_policy.policy_id);
end

function subject = localEvaluationSubject()
subject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XCOMM04:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function value = localReferencePresence()
value = lower(strtrim(string("present")));
assert(value == "present", "SimuVerity:F90:XCOMM04:ReferencePresence", ...
    "Task-bound reference file presence is missing or invalid.");
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
