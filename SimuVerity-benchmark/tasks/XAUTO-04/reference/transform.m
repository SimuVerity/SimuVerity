function report = transform(sourceDir, destinationDir)
%F90_XAUTO_04_TRANSFORM Public, non-destructive importer transform hook.
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
mainArchive = fullfile(sourceDir, "BrakingTest.zip");
assert(isfile(mainArchive), "SimuVerity:Importer:BrakingArchive", ...
    "The installed R2025a BrakingTest archive was not found: %s", mainArchive);
unzip(mainArchive, destinationDir);
siblingProjects = ["Common", "Driveline", "PassVeh14DOF", "PassVeh7DOF", ...
    "SI", "VehicleConfig"];
for sibling = siblingProjects
    archive = fullfile(sourceDir, sibling + ".zip");
    assert(isfile(archive), "SimuVerity:Importer:SiblingArchive", ...
        "The installed R2025a archive was not found: %s", archive);
    unzip(archive, fullfile(destinationDir, sibling));
end
testData = fullfile(sourceDir, "mldatx", "ISO15037_1_2006E.mldatx");
assert(isfile(testData), "SimuVerity:Importer:TestData", ...
    "The installed R2025a test data was not found.");
copyfile(testData, fullfile(destinationDir, "System", ...
    "ISO15037_1_2006E.mldatx"));
publicProject = fullfile(destinationDir, "BrakingTest");
if ~isfolder(publicProject), mkdir(publicProject); end
projectItems = ["resources", "Scripts", "System", "Work"];
for index = 1:numel(projectItems)
    sourceItem = fullfile(destinationDir, projectItems(index));
    targetItem = fullfile(publicProject, projectItems(index));
    if isfile(sourceItem) || isfolder(sourceItem)
        copyfile(sourceItem, targetItem);
    end
end
publicEntrypoint = fullfile(publicProject, "System", "BTReferenceApplication.slx");
assert(isfile(publicEntrypoint), "SimuVerity:Importer:BrakingEntrypoint", ...
    "The public BrakingTest entrypoint was not materialized.");
report = struct("task_id", "F90-XAUTO-04", "status", ...
    "UNMODIFIED_OFFICIAL_COPY_COMPLETE", "core_source_modifications", 0, ...
    "public_path_alias", "official project root -> BrakingTest");
end
