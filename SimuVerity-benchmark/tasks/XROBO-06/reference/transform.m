function report = transform(sourceDir, destinationDir)
%F90_XROBO_06_TRANSFORM Public, non-destructive importer transform hook.
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
report = struct("task_id", "F90-XROBO-06", "status", ...
    "UNMODIFIED_OFFICIAL_COPY_COMPLETE", "core_source_modifications", 0);
end
