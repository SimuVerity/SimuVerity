function report = transform(sourceDir, destinationDir)
%F90_XROBO_08_TRANSFORM Public, non-destructive importer transform hook.
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
mainDir = fullfile(destinationDir, "main");
dataDir = fullfile(destinationDir, "data");
if ~isfolder(mainDir), mkdir(mainDir); end
if ~isfolder(dataDir), mkdir(dataDir); end
mainFiles = ["animatedPath.m", "calcMOI.m", "cor2SpringDamperParams.m", ...
    "kinova_params.m", "rlKinovaBallBalance.slx"];
for index = 1:numel(mainFiles)
    copyfile(fullfile(destinationDir, mainFiles(index)), ...
        fullfile(mainDir, mainFiles(index)));
end
copyfile(fullfile(destinationDir, "kinovaBallBalanceAgent.mat"), ...
    fullfile(dataDir, "kinovaBallBalanceAgent.mat"));
report = struct("task_id", "F90-XROBO-08", "status", ...
    "UNMODIFIED_OFFICIAL_COPY_COMPLETE", "core_source_modifications", 0, ...
    "public_layout_materialized", true);
end
