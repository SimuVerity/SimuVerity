function report = transform(sourceDir, destinationDir)
%F90_XROBO_10_TRANSFORM Public, non-destructive importer transform hook.
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
archivePath = fullfile(destinationDir, "smart4i_data.zip");
supportDir = fullfile(destinationDir, "smart4i_data");
if ~isfolder(supportDir), mkdir(supportDir); end
if ~isfile(archivePath)
    downloaded = matlab.internal.examples.downloadSupportFile( ...
        "R2023a/sl3d/examples/", "smart4i_data.zip");
    assert(isfile(downloaded), "SimuVerity:Importer:Smart4iSupport", ...
        "The official MathWorks support archive could not be downloaded.");
    copyfile(downloaded, archivePath);
end
unzip(archivePath, supportDir);
supportFiles = ["smart4i_coords.mat", "smart4i_robotRBT.mat", ...
    "smart4i_scene.mat"];
for index = 1:numel(supportFiles)
    sourceFile = fullfile(supportDir, supportFiles(index));
    rootFile = fullfile(destinationDir, supportFiles(index));
    if ~isfile(sourceFile) && isfile(rootFile)
        copyfile(rootFile, sourceFile);
    end
    assert(isfile(sourceFile), "SimuVerity:Importer:Smart4iSupport", ...
        "The official example omits %s.", supportFiles(index));
    if ~isfile(rootFile), copyfile(sourceFile, rootFile); end
end
report = struct("task_id", "F90-XROBO-10", "status", ...
    "UNMODIFIED_OFFICIAL_COPY_COMPLETE", "core_source_modifications", 0, ...
    "support_data_materialized", true);
end
