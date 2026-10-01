function definition = f90_xmech05_definition
%F90_XMECH05_DEFINITION Minimal shared-runner contract.
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0, evaluationSubject = "candidate"; end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XMECH05:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
referenceRoot = fullfile(taskRoot, "reference");
if evaluationSubject == "reference"
    referenceRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
    assert(isfolder(referenceRoot), "SimuVerity:F90:XMECH05:ReferenceAssetRoot", ...
        "Evaluator-owned reference asset root is missing.");
end
definition = struct;
definition.task_id = "F90-XMECH-05";
definition.model_name = "Forklift";
definition.target_model_file = "Forklift.slx";
definition.runner = struct( ...
    "reference_model", fullfile(referenceRoot, "Forklift.slx"), ...
    "public_spec", fullfile(taskRoot, "public_spec.json"), ...
    "official_scenarios", simuverity_official_scenarios_path());
end
