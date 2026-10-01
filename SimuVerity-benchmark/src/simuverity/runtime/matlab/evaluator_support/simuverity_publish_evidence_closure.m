function manifest = simuverity_publish_evidence_closure(sourceDir, evidencePath)
%SIMUVERITY_PUBLISH_EVIDENCE_CLOSURE Publish one extractor closure.
% Evidence-producing task code writes into a fresh evaluator-owned temporary
% directory.  This helper preserves every ancillary file (waveforms, MAT
% rows, pack manifests, and similar score inputs) at the same path relative
% to evidence.json, then publishes evidence.json last.  It never interprets
% or modifies score data.
arguments
    sourceDir (1,1) string
    evidencePath (1,1) string
end
sourceDir = localCanonical(sourceDir);
evidencePath = localCanonical(evidencePath);
assert(isfolder(sourceDir), ...
    "SimuVerity:EvidenceClosure:SourceMissing", ...
    "Extractor evidence directory is missing: %s", sourceDir);
producedEvidence = fullfile(sourceDir, "evidence.json");
assert(isfile(producedEvidence), ...
    "SimuVerity:EvidenceClosure:EvidenceMissing", ...
    "Extractor did not produce evidence.json.");
targetParent = string(fileparts(evidencePath));
if strlength(targetParent) == 0, targetParent = localCanonical(pwd); end
if ~isfolder(targetParent), mkdir(targetParent); end
targetParent = localCanonical(targetParent);
assert(sourceDir ~= targetParent, ...
    "SimuVerity:EvidenceClosure:AliasedRoots", ...
    "Extractor temporary output and published output must differ.");

entries = dir(fullfile(sourceDir, "**", "*"));
entries = entries(~[entries.isdir]);
relativePaths = strings(0,1);
sourcePaths = strings(0,1);
for index = 1:numel(entries)
    source = localCanonical(fullfile(entries(index).folder, entries(index).name));
    relative = localRelative(sourceDir, source);
    if relative == "evidence.json", continue, end
    % A producer-owned self-declaration is neither score evidence nor an
    % authority to assemble the final evidence bundle. Never publish it
    % under the evaluator's reserved manifest name.
    if relative == "evidence_manifest.json", continue, end
    % The shared extractor's writable runtime model is execution state, not
    % score evidence.  Never duplicate a candidate model into an evidence
    % evidence bundle or a results tree.
    if startsWith(relative, "candidate_runtime/"), continue, end
    % MATLAB cache and code-generation trees are transient execution state.
    % They may disappear while MATLAB shuts down and are never score inputs.
    generatedParts = split(lower(replace(relative, "\", "/")), "/");
    if any(ismember(generatedParts, ...
            ["runtime_scratch", "cache", "codegen", "slprj"])), continue, end
    if any(endsWith(lower(relative), [".slxc", ".mexw64", ".pyc"])), continue, end
    assert(relative ~= "evidence_closure_manifest.json", ...
        "SimuVerity:EvidenceClosure:ReservedName", ...
        "Extractor output uses the reserved closure-manifest name.");
    relativePaths(end+1,1) = relative; %#ok<AGROW>
    sourcePaths(end+1,1) = source; %#ok<AGROW>
end
[relativePaths, order] = sort(relativePaths);
sourcePaths = sourcePaths(order);
assert(numel(unique(relativePaths)) == numel(relativePaths), ...
    "SimuVerity:EvidenceClosure:DuplicatePath", ...
    "Extractor evidence closure contains duplicate paths.");

rows = repmat(struct("path","","size_bytes",uint64(0)), ...
    numel(relativePaths), 1);
for index = 1:numel(relativePaths)
    relative = relativePaths(index);
    source = sourcePaths(index);
    target = localCanonical(fullfile(targetParent, ...
        strrep(relative, "/", filesep)));
    localAssertChild(targetParent, target);
    assert(~isfile(target) && ~isfolder(target), ...
        "SimuVerity:EvidenceClosure:OutputReuse", ...
        "Refusing to overwrite published evidence artifact: %s", relative);
    parent = string(fileparts(target));
    if ~isfolder(parent), mkdir(parent); end
    staged = target + ".staging-" + string(java.util.UUID.randomUUID);
    copied = copyfile(source, staged, "f");
    assert(copied && movefile(staged, target), ...
        "SimuVerity:EvidenceClosure:ArtifactPublish", ...
        "Could not publish evidence artifact: %s", relative);
    info = dir(target);
    rows(index) = struct("path",replace(relative,"\\","/"), ...
        "size_bytes",uint64(info.bytes));
end

stagedEvidence = evidencePath + ".staging-" + string(java.util.UUID.randomUUID);
assert(copyfile(producedEvidence, stagedEvidence, "f") && ...
    movefile(stagedEvidence, evidencePath), ...
    "SimuVerity:EvidenceClosure:EvidencePublish", ...
    "Could not atomically publish evidence.json.");
manifest = struct( ...
    "schema", "simuverity.evidence-closure-manifest.v1", ...
    "task_id", string(getenv("SIMUVERITY_TASK_ID")), ...
    "evidence_file", "evidence.json");
% A MATLAB scalar struct encodes as a JSON object.  Store rows in a cell so
% the closure contract remains a JSON array for zero, one, or many files.
manifest.files = num2cell(rows);
manifestPath = fullfile(targetParent, "evidence_closure_manifest.json");
localWriteJsonExclusive(manifestPath, manifest);
end

function relative = localRelative(root, child)
root = char(root); child = char(child);
prefix = [root filesep];
if ispc
    assert(startsWith(lower(child), lower(prefix)), ...
        "SimuVerity:EvidenceClosure:PathEscape", ...
        "Evidence artifact escaped its temporary root.");
else
    assert(startsWith(child, prefix), ...
        "SimuVerity:EvidenceClosure:PathEscape", ...
        "Evidence artifact escaped its temporary root.");
end
relative = string(strrep(child(numel(prefix)+1:end), filesep, "/"));
assert(strlength(relative)>0 && ~startsWith(relative,"/") && ...
    ~contains(relative,"../") && relative ~= "..", ...
    "SimuVerity:EvidenceClosure:UnsafeRelativePath", ...
    "Evidence artifact has an unsafe relative path.");
end

function localAssertChild(root, child)
prefix = [char(root) filesep];
if ispc, pass = startsWith(lower(char(child)), lower(prefix));
else, pass = startsWith(char(child), prefix); end
assert(pass, "SimuVerity:EvidenceClosure:PathEscape", ...
    "Published evidence artifact escaped its output root.");
end

function value = localCanonical(pathIn)
value = string(java.io.File(char(pathIn)).getCanonicalPath());
end

function localWriteJsonExclusive(pathOut, value)
assert(~isfile(pathOut) && ~isfolder(pathOut), ...
    "SimuVerity:EvidenceClosure:ManifestReuse", ...
    "Refusing to overwrite evidence closure manifest.");
temporary = string(pathOut) + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:EvidenceClosure:ManifestCreate", ...
    "Cannot create evidence closure manifest.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char"); clear cleanup
assert(movefile(temporary, pathOut), ...
    "SimuVerity:EvidenceClosure:ManifestPublish", ...
    "Could not publish evidence closure manifest.");
end
