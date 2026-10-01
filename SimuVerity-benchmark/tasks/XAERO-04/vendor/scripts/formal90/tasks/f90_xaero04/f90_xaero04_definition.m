function def = f90_xaero04_definition
%F90_XAERO04_DEFINITION Direct-golden VTOLApp tiltrotor contract.
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
assert(isfolder(taskRoot), "SimuVerity:F90:XAERO04:TaskRoot", ...
    "Public task root is missing.");
publicPath = fullfile(taskRoot, "public_spec.json");
taskPath = fullfile(taskRoot, "task.json");
recipePath = fullfile(taskRoot, "reference", "importer_recipe.json");
officialPath = simuverity_official_scenarios_path();
assert(isfile(publicPath) && isfile(taskPath) && isfile(recipePath) && ...
    isfile(officialPath), "SimuVerity:F90:XAERO04:PublicBinding", ...
    "A public XAERO-04 task, recipe, spec, or scenario binding is missing.");
public = jsondecode(fileread(publicPath));
task = jsondecode(fileread(taskPath));
recipe = jsondecode(fileread(recipePath));
official = jsondecode(fileread(officialPath));
assert(string(task.task_id) == "F90-XAERO-04" && ...
    string(recipe.task_id) == "F90-XAERO-04" && ...
    replace(string(task.reference.recipe), "\", "/") == ...
    "reference/importer_recipe.json", "SimuVerity:F90:XAERO04:PublicTaskIdentity", ...
    "The public task or importer recipe identity is missing or changed.");

modelRelative = replace(string(task.reference.entrypoint), "\", "/");
[modelRelative, modelPresence] = localRecipeBinding(recipe, modelRelative);
[controllerRelative, controllerPresence] = localRecipeBinding(recipe, ...
    "VTOLApp/models/VTOLAutopilotController.slx");
[plantRelative, plantPresence] = localRecipeBinding(recipe, ...
    "VTOLApp/models/VTOLDynamics.slx");
assert(replace(string(recipe.entrypoint), "\", "/") == modelRelative && ...
    replace(string(recipe.discovery.source_root.anchor_path), "\", "/") == ...
        modelRelative, ...
    "SimuVerity:F90:XAERO04:ReferenceRecipeIdentity", ...
    "The public task and importer recipe reference identities differ.");

evaluationSubject = localEvaluationSubject;
referenceBase = fullfile(taskRoot, "reference");
if evaluationSubject == "reference"
    referenceBase = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
    assert(isfolder(referenceBase), "SimuVerity:F90:XAERO04:ReferenceAssetRoot", ...
        "Evaluator-owned reference asset root is missing.");
end
projectRelative = string(fileparts(fileparts(modelRelative)));
assert(strlength(projectRelative) > 0, "SimuVerity:F90:XAERO04:ReferenceProject", ...
    "The public reference entrypoint has no project root.");

def = struct;
def.id = "XAERO04";
def.formal_id = "F90-XAERO-04";
def.target_model_file = "F90_XAERO_04.slx";
def.reference_root = fullfile(referenceBase, projectRelative);
def.reference_model = fullfile(referenceBase, modelRelative);
def.reference_controller = fullfile(referenceBase, controllerRelative);
def.reference_plant = fullfile(referenceBase, plantRelative);
def.reference_file_presence = modelPresence;
def.controller_file_presence = controllerPresence;
def.plant_file_presence = plantPresence;
def.public_spec = publicPath;
def.official_scenarios = officialPath;
def.prompt = string(public.prompt);
def.scenarios = official.scenarios;
def.weights = official.weights;
def.required_outputs = [ ...
    "PositionTracking", "TransitionState", ...
    "VehicleState", "ActuatorCommand"];
def.runner = struct( ...
    "reference_model", def.reference_model, ...
    "public_spec", publicPath, ...
    "official_scenarios", officialPath);
if evaluationSubject == "reference"
    localRequireBoundFile(def.reference_model, def.reference_file_presence, "model");
    localRequireBoundFile(def.reference_controller, def.controller_file_presence, ...
        "controller");
    localRequireBoundFile(def.reference_plant, def.plant_file_presence, "plant");
end
end

function subject = localEvaluationSubject
subject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XAERO04:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function [relativePath, presence] = localRecipeBinding(recipe, requiredPath)
rows = recipe.discovery.expected_files;
paths = replace(string({rows.path}), "\", "/");
requiredPath = replace(string(requiredPath), "\", "/");
matches = find(paths == requiredPath);
assert(numel(matches) == 1, "SimuVerity:F90:XAERO04:RecipeFileBinding", ...
    "The importer recipe must bind exactly one %s entry.", requiredPath);
relativePath = paths(matches);
presence = "present";
end

function localRequireBoundFile(pathValue, expectedPresence, role)
assert(isfile(pathValue), "SimuVerity:F90:XAERO04:ReferenceFileMissing", ...
    "The task-bound reference %s is missing: %s", role, pathValue);
assert(localFilePresence(pathValue) == expectedPresence, ...
    "SimuVerity:F90:XAERO04:ReferenceFileIdentity", ...
    "The task-bound reference %s is binding-mismatched.", role);
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end
