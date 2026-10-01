function result = simuverity_prepare_importer(recipePath, transformPath, transformEntrypoint, destinationDir, receiptPath)
%SIMUVERITY_PREPARE_IMPORTER Materialize an installed R2025a example.
% MathWorks source bytes are read from the user's installation and are never
% part of this repository.
arguments
    recipePath (1,:) char
    transformPath (1,:) char
    transformEntrypoint (1,:) char
    destinationDir (1,:) char
    receiptPath (1,:) char
end

recipe = jsondecode(fileread(recipePath));
assert(string(recipe.schema) == ...
    "simuverity.matlab-local-importer-recipe.v1", ...
    "SimuVerity:Importer:RecipeSchema", "Unsupported importer recipe.");
actualRelease = upper(strtrim(string(version("-release"))));
requiredRelease = upper(strtrim(string(recipe.matlab_release)));
if startsWith(requiredRelease, "R")
    requiredRelease = extractAfter(requiredRelease, 1);
end
assert(actualRelease == "2025A" && requiredRelease == "2025A", ...
    "SimuVerity:Importer:MatlabRelease", ...
    "Importer requires MATLAB %s, found %s.", ...
    string(recipe.matlab_release), string(version("-release")));
outputRows = recipe.discovery.expected_files;
outputPathBound = isfield(outputRows, "path");
if outputPathBound
    outputExpected = string({outputRows.path}).';
else
    outputExpected = string(recipe.discovery.expected_source_filenames(:));
end
sourceRows = outputRows;
if isfield(recipe.discovery, "source_files")
    sourceRows = recipe.discovery.source_files;
end
sourcePathBound = isfield(sourceRows, "path");
if sourcePathBound
    sourceExpected = string({sourceRows.path}).';
else
    sourceExpected = string({sourceRows.name}).';
end
assert(~isempty(sourceExpected) && ~isempty(outputExpected), ...
    "SimuVerity:Importer:ExpectedFiles", ...
    "Importer recipe declares no source or output files.");

officialAssetRoot = localOfficialAssetRoot(recipe);
exampleWorkspace = "";
exampleWorkspaceRoot = "";
originalFolder = string(pwd);
exampleIds = strings(0,1);
if isfield(recipe.discovery, "example_id")
    exampleIds = localNormalizeExampleIds(recipe.discovery.example_id);
end
if strlength(officialAssetRoot) == 0 && ~isempty(exampleIds)
    failures = strings(numel(exampleIds),1);
    for exampleIndex = 1:numel(exampleIds)
        candidateWorkspaceRoot = string(tempname);
        candidateWorkspace = fullfile(candidateWorkspaceRoot, "example");
        mkdir(candidateWorkspace);
        try
            openExample(exampleIds(exampleIndex), ...
                "workDir", candidateWorkspace);
            exampleWorkspace = candidateWorkspace;
            exampleWorkspaceRoot = candidateWorkspaceRoot;
            break
        catch exception
            failures(exampleIndex) = exampleIds(exampleIndex) + ": " + ...
                string(exception.message);
            localReleaseExampleWorkspace(candidateWorkspaceRoot, originalFolder);
        end
    end
    assert(strlength(exampleWorkspace) > 0, ...
        "SimuVerity:Importer:ExampleDiscovery", ...
        "Unable to materialize any declared R2025a example: %s", ...
        join(failures(strlength(failures) > 0), " | "));
    workspaceCleanup = onCleanup(@() ...
        localReleaseExampleWorkspace(exampleWorkspaceRoot, originalFolder)); %#ok<NASGU>
end

if sourcePathBound
    assert(isfield(recipe.discovery, "source_root") && ...
        isfield(recipe.discovery.source_root, "anchor_path"), ...
        "SimuVerity:Importer:SourceRootBinding", ...
        "Path-bound importer recipe has no source-root anchor.");
    anchorPath = string(recipe.discovery.source_root.anchor_path);
    [~, anchorName, anchorExtension] = fileparts(anchorPath);
    anchorFilename = anchorName + anchorExtension;
    candidates = strings(0,1);
    if strlength(officialAssetRoot) > 0
        materialized = dir(fullfile(officialAssetRoot, "**", anchorFilename));
        materialized = materialized(~[materialized.isdir]);
        candidates = string(fullfile({materialized.folder}, {materialized.name}));
    end
    if strlength(exampleWorkspace) > 0
        materialized = dir(fullfile(exampleWorkspace, "**", anchorFilename));
        materialized = materialized(~[materialized.isdir]);
        candidates = [candidates; string(fullfile({materialized.folder}, {materialized.name}))]; %#ok<AGROW>
    end
    candidates = unique(candidates(isfile(candidates)), "stable");
    keep = arrayfun(@(candidate) localEndsWithRelativePath(candidate, anchorPath), candidates);
    candidates = candidates(keep);
    if strlength(officialAssetRoot) > 0 && ...
            isfield(recipe.discovery.official_asset_root, "anchor_path")
        officialAnchorPath = string(recipe.discovery.official_asset_root.anchor_path);
        [~, officialAnchorName, officialAnchorExtension] = fileparts(officialAnchorPath);
        materialized = dir(fullfile(officialAssetRoot, "**", ...
            officialAnchorName + officialAnchorExtension));
        materialized = materialized(~[materialized.isdir]);
        officialCandidates = string(fullfile({materialized.folder}, {materialized.name}));
        officialCandidates = officialCandidates(arrayfun(@(candidate) ...
            localEndsWithRelativePath(candidate, officialAnchorPath), officialCandidates));
        assert(numel(officialCandidates) == 1, ...
            "SimuVerity:Importer:OfficialAssetRootAnchor", ...
            "Expected exactly one official asset-root anchor for %s, found %d.", ...
            officialAnchorPath, numel(officialCandidates));
        sourceDirectory = localOfficialSourceDirectory(recipe, officialAssetRoot);
        sourceDir = sourceDirectory;
    else
        assert(numel(candidates) == 1, "SimuVerity:Importer:SourceRootAmbiguous", ...
            "Expected exactly one installed source anchor for %s, found %d.", ...
            anchorPath, numel(candidates));
        sourceDir = localStripRelativePath(candidates(1), anchorPath);
    end
else
    found = strings(size(sourceExpected));
    for index = 1:numel(sourceExpected)
        candidates = strings(0,1);
        if strlength(officialAssetRoot) > 0
            materialized = dir(fullfile(officialAssetRoot, "**", sourceExpected(index)));
            materialized = materialized(~[materialized.isdir]);
            candidates = string(fullfile({materialized.folder}, {materialized.name}));
        end
        if strlength(exampleWorkspace) > 0
            materialized = dir(fullfile(exampleWorkspace, "**", sourceExpected(index)));
            materialized = materialized(~[materialized.isdir]);
            candidates = [candidates; string(fullfile({materialized.folder}, {materialized.name}))]; %#ok<AGROW>
        end
        candidates = [candidates(:); string(which(sourceExpected(index), "-all"))]; %#ok<AGROW>
        candidates = candidates(isfile(candidates));
        if isempty(candidates)
            recursive = dir(fullfile(matlabroot, "**", sourceExpected(index)));
            recursive = recursive(~[recursive.isdir]);
            candidates = string(fullfile({recursive.folder}, {recursive.name}));
        end
        assert(~isempty(candidates), "SimuVerity:Importer:SourceMissing", ...
            "Installed R2025a source file was not found: %s", sourceExpected(index));
        found(index) = candidates(1);
    end
    sourceDir = localCommonDirectory(found);
end
assert(isfolder(sourceDir), "SimuVerity:Importer:CommonSource", ...
    "Cannot resolve an installed example source root.");
if sourcePathBound && strlength(officialAssetRoot) == 0
    for index = 1:numel(sourceExpected)
        assert(isfile(fullfile(sourceDir, replace(sourceExpected(index), "/", filesep))), ...
            "SimuVerity:Importer:SourceMissing", ...
            "Installed R2025a source path was not found: %s", sourceExpected(index));
    end
end
assert(~isfile(destinationDir), "SimuVerity:Importer:DestinationReuse", ...
    "Importer destination resolves to a file: %s", destinationDir);
if isfolder(destinationDir)
    existing = dir(destinationDir);
    existing = existing(~ismember({existing.name}, {'.','..'}));
    assert(isempty(existing), "SimuVerity:Importer:DestinationReuse", ...
        "Importer destination must be empty: %s", destinationDir);
else
    mkdir(destinationDir);
end

oldPath = path;
cleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(fileparts(transformPath), "-begin");
transformReport = feval(transformEntrypoint, string(sourceDir), ...
    string(destinationDir));
for index = 1:numel(outputExpected)
    if outputPathBound
        present = isfile(fullfile(destinationDir, replace(outputExpected(index), "/", filesep)));
    else
        present = ~isempty(dir(fullfile(destinationDir, "**", outputExpected(index))));
    end
    assert(present, "SimuVerity:Importer:OutputMissing", ...
        "Transformed asset omits required output path: %s", outputExpected(index));
end

result = struct( ...
    "schema", "simuverity.matlab-local-import-receipt.v1", ...
    "status", "MATERIALIZED_PENDING_REFERENCE_REGRESSION", ...
    "task_id", string(recipe.task_id), ...
    "matlab_release", string(version("-release")), ...
    "source_mode", localSourceMode(officialAssetRoot), ...
    "expected_source_filenames", sourceExpected, ...
    "path_bound_source", sourcePathBound, ...
    "transform_entrypoint", string(transformEntrypoint), ...
    "transform_report", transformReport, ...
    "reference_regression_complete", false);
localWriteJson(receiptPath, result);
end

function root = localOfficialAssetRoot(recipe)
root = "";
if ~isfield(recipe.discovery, "official_asset_root")
    return
end
sourceRoot = recipe.discovery.official_asset_root;
assert(isstruct(sourceRoot) && isfield(sourceRoot, "env"), ...
    "SimuVerity:Importer:OfficialAssetRootVariable", ...
    "official_asset_root must declare env.");
variable = string(sourceRoot.env);
assert(isscalar(variable) && ~isempty(regexp(variable, ...
    "^[A-Za-z_][A-Za-z0-9_]*$", "once")), ...
    "SimuVerity:Importer:OfficialAssetRootVariable", ...
        "official_asset_root.env must be a valid environment-variable name.");
root = string(getenv(variable));
if strlength(root) == 0
    required = isfield(sourceRoot, "required") && logical(sourceRoot.required);
    assert(~required, "SimuVerity:Importer:OfficialAssetRootMissing", ...
        "Set %s to the root of the installed official asset before import.", variable);
    return
end
assert(isfolder(root), "SimuVerity:Importer:OfficialAssetRootMissing", ...
    "Configured official asset root does not exist: %s", root);
root = string(java.io.File(char(root)).getCanonicalPath());
end

function directory = localOfficialSourceDirectory(recipe, officialAssetRoot)
config = recipe.discovery.official_asset_root;
relative = ".";
if isfield(config, "source_directory")
    relative = string(config.source_directory);
end
assert(isscalar(relative) && ~startsWith(relative, ["/", "\\"]) && ...
    ~contains(relative, ".."), "SimuVerity:Importer:OfficialAssetRootDirectory", ...
    "official_asset_root.source_directory must be a safe relative path.");
directory = string(fullfile(officialAssetRoot, relative));
assert(isfolder(directory), "SimuVerity:Importer:OfficialAssetRootDirectory", ...
    "Configured official source directory does not exist: %s", directory);
end

function mode = localSourceMode(officialAssetRoot)
if strlength(officialAssetRoot) > 0
    mode = "official_asset_root_env";
else
    mode = "open_example_or_installation_search";
end
end

function tf = localEndsWithRelativePath(pathValue, relativeValue)
pathText = replace(string(pathValue), "\", "/");
relativeText = replace(string(relativeValue), "\", "/");
tf = strcmpi(pathText, relativeText) || endsWith(pathText, "/" + relativeText, ...
    "IgnoreCase", true);
end

function root = localStripRelativePath(pathValue, relativeValue)
root = string(pathValue);
parts = split(replace(string(relativeValue), "\", "/"), "/");
parts = parts(strlength(parts) > 0);
for index = 1:numel(parts)
    root = string(fileparts(root));
end
end

function root = localCommonDirectory(paths)
parts = split(string(fileparts(paths(1))), filesep);
for index = 2:numel(paths)
    candidate = split(string(fileparts(paths(index))), filesep);
    count = min(numel(parts), numel(candidate));
    keep = 0;
    for partIndex = 1:count
        if strcmpi(parts(partIndex), candidate(partIndex))
            keep = partIndex;
        else
            break;
        end
    end
    parts = parts(1:keep);
end
assert(~isempty(parts), "SimuVerity:Importer:CommonSource", ...
    "Installed source files have no common directory.");
root = join(parts, filesep);
if startsWith(paths(1), filesep), root = filesep + root; end
end

function values = localNormalizeExampleIds(value)
if isempty(value)
    values = strings(0,1);
    return
end
if ischar(value)
    values = string(value);
elseif isstring(value) || iscell(value)
    try
        values = strip(string(value(:)));
    catch exception
        error("SimuVerity:Importer:ExampleId", ...
            "Importer example_id must contain text values: %s", ...
            string(exception.message));
    end
else
    error("SimuVerity:Importer:ExampleId", ...
        "Importer example_id must be text, a text array, or empty.");
end
values = unique(values(strlength(values) > 0), "stable");
end

function localReleaseExampleWorkspace(pathValue, originalFolder)
try
    project = matlab.project.rootProject;
    if ~isempty(project) && localIsWithin(string(project.RootFolder), pathValue)
        close(project);
    end
catch
end
try
    cd(originalFolder);
catch
    cd(tempdir);
end
localRemoveTree(pathValue);
end

function tf = localIsWithin(candidate, root)
candidate = strip(replace(string(candidate), "\", "/"), "right", "/");
root = strip(replace(string(root), "\", "/"), "right", "/");
tf = strcmpi(candidate, root) || startsWith(candidate, root + "/", ...
    "IgnoreCase", true);
end

function localRemoveTree(pathValue)
if strlength(string(pathValue)) > 0 && isfolder(pathValue)
    try, rmdir(pathValue, 's'); catch, end
end
end

function localWriteJson(pathValue, value)
parent = fileparts(pathValue);
if ~isempty(parent) && ~isfolder(parent), mkdir(parent); end
temporary = string(pathValue) + ".tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:Importer:ReceiptWrite", ...
    "Cannot write importer receipt: %s", pathValue);
try
    fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
    fclose(fid);
catch exception
    fclose(fid);
    rethrow(exception);
end
movefile(temporary, pathValue, "f");
end
