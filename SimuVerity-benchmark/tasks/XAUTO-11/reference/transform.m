function report = transform(sourceDir, destinationDir)
%F90_XAUTO_11_TRANSFORM Controller transform with canonical SLX identity.
arguments
    sourceDir (1,1) string
    destinationDir (1,1) string
end
assert(isfolder(sourceDir), "SimuVerity:Importer:MissingSource", ...
    "R2025a source directory was not found: %s", sourceDir);
assert(~strcmpi(char(sourceDir), char(destinationDir)), ...
    "SimuVerity:Importer:InPlaceForbidden", ...
    "Importer must write to a separate cache directory.");
if ~isfolder(destinationDir), mkdir(destinationDir); end
copyfile(fullfile(sourceDir, "*"), destinationDir);
matches = dir(fullfile(destinationDir, "**", "rct_suspension.slx"));
assert(numel(matches) == 1, "SimuVerity:Importer:SourceModel", ...
    "Expected exactly one R2025a rct_suspension.slx source model.");
sourceModel = string(fullfile(matches(1).folder, matches(1).name));
targetModel = fullfile(destinationDir, "rct_suspension_reference.slx");
[~, model] = fileparts(sourceModel);
originalFolder = string(pwd);
originalPath = path;
folderCleanup = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
pathCleanup = onCleanup(@() path(originalPath)); %#ok<NASGU>
cd(destinationDir);
pathEntries = split(string(path), pathsep);
if any(strcmpi(pathEntries, sourceDir)), rmpath(sourceDir); end
addpath(destinationDir, "-begin");
if bdIsLoaded(model), close_system(model, 0); end
load_system(sourceModel);
cleanup = onCleanup(@() close_system(model, 0)); %#ok<NASGU>
A = [-1.2102451957047733, 1.2045416168330449; ...
     -0.29570970291250126, 0.16375785991202008];
B = [-0.054934275342627958, 0.30070212015280839; ...
     -0.072998827854071829, -0.71662032443891632];
C = [1.0256181172894574, 0.59742371819241624];
D = [-2.133639393587508, -0.0050474716838548169];
controllerBlock = model + "/Controller";
assert(getSimulinkBlockHandle(controllerBlock) > 0, ...
    "SimuVerity:Importer:ControllerBlock", ...
    "The official second-order Controller block was not found.");
set_param(controllerBlock, "A", mat2str(A), "B", mat2str(B), ...
    "C", mat2str(C), "D", mat2str(D));
save_system(model, targetModel);
localCanonicalizeIdentity(targetModel);
report = struct("task_id", "F90-XAUTO-11", ...
    "status", "TASK_SPECIFIC_CONTROLLER_TRANSFORM_COMPLETE", ...
    "physical_topology_modifications", 0, "controller_order_modifications", 0, ...
    "identity_normalization", ["dcterms:modified", "ModelUUID", "BDUuid"], ...
    "controller_A", A, "controller_B", B, "controller_C", C, "controller_D", D);
end

function localCanonicalizeIdentity(modelPath)
% Only fields observed to vary across independent R2025a materializations.
staging = string(tempname);
mkdir(staging);
cleanup = onCleanup(@() localRemoveTree(staging)); %#ok<NASGU>
unzip(modelPath, staging);
localRewriteXml(fullfile(staging, "metadata", "coreProperties.xml"), ...
    "dcterms:modified", "2014-10-02T17:27:43Z");
localRewriteXml(fullfile(staging, "simulink", "blockdiagram.xml"), ...
    "ModelUUID", "7b9a257a-e96a-451e-a9ea-2d5cedc466aa");
localRewriteXml(fullfile(staging, "simulink", "windowsInfo.xml"), ...
    "BDUuid", "3f8a40d7-ca0c-4114-af13-8a1b6172d9f7");
files = dir(fullfile(staging, "**", "*"));
files = files(~[files.isdir]);
relative = string(fullfile({files.folder}, {files.name}));
relative = erase(relative, staging + filesep);
[relative, order] = sort(relative);
for index = 1:numel(order)
    java.io.File(char(fullfile(staging, relative(index)))).setLastModified(0);
end
temporaryZip = string(tempname) + ".zip";
stream = javaObject("java.util.zip.ZipOutputStream", ...
    javaObject("java.io.FileOutputStream", char(temporaryZip)));
stream.setLevel(9);
streamCleanup = onCleanup(@() localCloseZip(stream)); %#ok<NASGU>
for index = 1:numel(relative)
    entry = javaObject("java.util.zip.ZipEntry", char(replace(relative(index), "\", "/")));
    entry.setTime(0);
    stream.putNextEntry(entry);
    input = fopen(fullfile(staging, relative(index)), "r");
    assert(input >= 0, "SimuVerity:Importer:CanonicalMetadata", ...
        "Cannot read SLX member: %s", relative(index));
    bytes = fread(input, Inf, "*uint8");
    stream.write(typecast(bytes, "int8"), 0, numel(bytes));
    fclose(input);
    stream.closeEntry();
end
stream.close();
movefile(temporaryZip, modelPath, "f");
end

function localRewriteXml(pathValue, fieldName, replacement)
assert(isfile(pathValue), "SimuVerity:Importer:CanonicalMetadata", ...
    "Expected SLX metadata member is missing: %s", pathValue);
text = fileread(pathValue);
if fieldName == "dcterms:modified"
    pattern = "<dcterms:modified[^>]*>[^<]*</dcterms:modified>";
    value = "<dcterms:modified xsi:type=""dcterms:W3CDTF"">" + replacement + ...
        "</dcterms:modified>";
else
    pattern = "(<P Name=""" + fieldName + """[^>]*>)[^<]*(</P>)";
    match = regexp(text, pattern, "match", "once");
    assert(~isempty(match), "SimuVerity:Importer:CanonicalMetadata", ...
        "Expected SLX identity field is missing: %s", fieldName);
    value = regexp(match, "^[^>]*>", "match", "once") + replacement + "</P>";
end
match = regexp(text, pattern, "match", "once");
assert(~isempty(match), "SimuVerity:Importer:CanonicalMetadata", ...
    "Expected SLX identity field is missing: %s", fieldName);
text = strrep(text, match, value);
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:Importer:CanonicalMetadata", ...
    "Cannot rewrite SLX metadata member: %s", pathValue);
fwrite(fid, text, "char");
fclose(fid);
end

function localRemoveTree(pathValue)
if isfolder(pathValue), try, rmdir(pathValue, "s"); catch, end, end
end

function localCloseZip(stream)
try, stream.close(); catch, end
end
