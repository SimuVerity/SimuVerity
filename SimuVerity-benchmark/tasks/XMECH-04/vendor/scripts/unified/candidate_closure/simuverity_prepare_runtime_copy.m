function loaded = simuverity_prepare_runtime_copy( ...
    dependencyManifestPath, submissionRoot, expectedPublicInputNames)
%simuverity_prepare_runtime_copy Load declared candidate dependencies.

arguments
    dependencyManifestPath (1,1) string
    submissionRoot (1,1) string
    expectedPublicInputNames string = strings(0,1)
end

dependencyManifestPath = localCanonical(dependencyManifestPath);
submissionRoot = localCanonical(submissionRoot);
assert(isfile(dependencyManifestPath) && isfolder(submissionRoot), ...
    "SimuVerity:CandidateClosure:LoadInputMissing", ...
    "The dependency manifest or submission root is missing.");
manifest = jsondecode(fileread(dependencyManifestPath));
assert(string(manifest.schema) == ...
    "simuverity.candidate-dependency-manifest.v1", ...
    "SimuVerity:CandidateClosure:ManifestInvalid", ...
    "The candidate dependency manifest is invalid.");

declaredPublic = unique(localNormalizeNames(manifest.public_input_names), "stable");
expectedPublic = unique(localNormalizeNames(expectedPublicInputNames), "stable");
declaredPublic(declaredPublic == "") = [];
expectedPublic(expectedPublic == "") = [];
assert(isequal(sort(declaredPublic), sort(expectedPublic)), ...
    "SimuVerity:CandidateClosure:PublicInputContractMismatch", ...
    "Public-input names do not match the dependency manifest.");
assert(~logical(manifest.public_inputs_serialized) && ...
    ~logical(manifest.entire_base_workspace_saved), ...
    "SimuVerity:CandidateClosure:UnsafeManifest", ...
    "The dependency manifest describes an unsafe workspace capture.");

dependencyRoot = localCanonical(fullfile(submissionRoot, ...
    string(manifest.dependency_package_relative_path)));
assert(localPathUnder(dependencyRoot, submissionRoot) && isfolder(dependencyRoot), ...
    "SimuVerity:CandidateClosure:DependencyPackageMissing", ...
    "The declared dependency package is missing.");

capturedFileRecords = manifest.captured_files;
dependencyDirectories = submissionRoot;
for k = 1:numel(capturedFileRecords)
    pathValue = localCanonical(fullfile(submissionRoot, ...
        string(capturedFileRecords(k).bundle_relative_path)));
    assert(localPathUnder(pathValue, submissionRoot) && isfile(pathValue), ...
        "SimuVerity:CandidateClosure:CapturedFileMissing", ...
        "A declared candidate dependency is missing.");
    dependencyDirectories(end + 1, 1) = string(fileparts(pathValue)); %#ok<AGROW>
end
dependencyDirectories = unique(dependencyDirectories, "stable");
for directory = reshape(dependencyDirectories, 1, [])
    addpath(directory, "-begin");
end

capturedNames = strings(0,1);
if ~isempty(manifest.captured_workspace_variables)
    capturedNames = string({manifest.captured_workspace_variables.name}).';
end
assert(isempty(intersect(capturedNames, declaredPublic)), ...
    "SimuVerity:CandidateClosure:PublicInputInManifest", ...
    "A public input was included in the dependency manifest.");

variableMatRelative = string(manifest.dependency_variable_mat_relative_path);
loadedNames = strings(0,1);
if variableMatRelative ~= ""
    variableMatPath = localCanonical(fullfile(submissionRoot, variableMatRelative));
    assert(localPathUnder(variableMatPath, dependencyRoot) && isfile(variableMatPath), ...
        "SimuVerity:CandidateClosure:VariablePackageInvalid", ...
        "The declared workspace-variable package is missing.");
    info = whos("-file", variableMatPath);
    loadedNames = string({info.name}).';
    assert(isequal(sort(loadedNames), sort(capturedNames)), ...
        "SimuVerity:CandidateClosure:VariablePackageMembershipMismatch", ...
        "The MAT package contents differ from the dependency manifest.");
    assert(isempty(intersect(loadedNames, declaredPublic)), ...
        "SimuVerity:CandidateClosure:PublicInputWasSerialized", ...
        "A public input was included in the dependency MAT package.");
    values = load(variableMatPath);
    for name = reshape(loadedNames, 1, [])
        assignin("base", name, values.(char(name)));
    end
else
    assert(isempty(capturedNames), ...
        "SimuVerity:CandidateClosure:VariablePackageMissing", ...
        "The manifest lists variables but no MAT package.");
end

loaded = struct( ...
    "schema", "simuverity.candidate-dependency-load.v1", ...
    "loaded_workspace_variables", loadedNames, ...
    "public_inputs_loaded", false, ...
    "dependency_directory_count", numel(dependencyDirectories));
end

function value = localNormalizeNames(raw)
if isempty(raw)
    value = strings(0,1);
elseif ischar(raw) || (isstring(raw) && isscalar(raw))
    value = string(raw);
elseif iscell(raw)
    value = string(raw(:));
else
    value = string(raw(:));
end
value = value(:);
end

function value = localCanonical(pathValue)
value = string(char(java.io.File(char(pathValue)).getCanonicalPath()));
end

function value = localPathUnder(pathValue, root)
pathValue = lower(localCanonical(pathValue));
root = lower(localCanonical(root));
value = pathValue == root || startsWith(pathValue, root + filesep);
end
