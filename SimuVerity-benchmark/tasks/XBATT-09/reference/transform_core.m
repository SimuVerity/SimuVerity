function report = transform_core(sourceDir, destinationDir)
%F90_XBATT_09_TRANSFORM_CORE Build the official example and normalize only
% observed generator timestamps and model-editor identity state.
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
% The official example inputs are exactly the three files listed in
% importer_recipe.json.  A materialized output directory can also contain
% generated libraries with these names; copying those back into a new
% materialization causes buildBattery to collide with its own library.
officialInputs = ["DisconnectedCellDetectionExample.mlx", ...
    "DischargeCycle.mat", "createDischargeHarnessModel.m"];
for index = 1:numel(officialInputs)
    sourcePath = fullfile(sourceDir, officialInputs(index));
    assert(isfile(sourcePath), "SimuVerity:Importer:MissingSource", ...
        "Official example input is missing: %s", sourcePath);
    copyfile(sourcePath, destinationDir);
end
originalFolder = string(pwd);
folderCleanup = onCleanup(@() cd(originalFolder)); %#ok<NASGU>
cd(destinationDir);

cylindricalCell = batteryCell(batteryCylindricalGeometry);
cylindricalCell.CellModelOptions.CellModelBlockPath = ...
    "batt_lib/Cells/Battery Equivalent Circuit";
parallelAssembly = batteryParallelAssembly(cylindricalCell, 30, Rows=3);
module = batteryModule(parallelAssembly, 15, ModelResolution="Grouped", ...
    SeriesGrouping=[1,14], ParallelGrouping=[30,1], StackingAxis="X");
libraryName = "moduleLibrary";
buildBattery(module, "MaskParameters", "VariableNamesByType", ...
    "LibraryName", libraryName, "Verbose", "off");

modelName = "disconnectedCellDetection";
moduleLibraryPath = libraryName + "_lib/" + module.Name;
createDischargeHarnessModel(moduleLibraryPath, modelName);
run("moduleLibrary_param.m");
profiles = load("DischargeCycle.mat", "batteryCurrent");
assignin("base", "batteryCurrent", profiles.batteryCurrent);
set_param(modelName + "/Current", "VariableName", "batteryCurrent");
set_param(modelName, "StopTime", "100");
save_system(modelName);

batteryPath = modelName + "/Battery";
faultPath = batteryPath + "/Cell1(1)/Additional resistance";
fault = Simulink.fault.addFault(faultPath);
faultModel = modelName + "_FaultModel";
addBehavior(fault, faultModel);
fault.TriggerType = "Timed";
fault.StartTime = 30;

probeBlockPath = modelName + "/Probe";
add_block("nesl_utility/Probe", probeBlockPath, position=[450,125,510,175]);
simscape.probe.setBoundBlock(probeBlockPath, batteryPath);
simscape.probe.setVariables(probeBlockPath, "vParallelAssembly");
probePorts = get_param(probeBlockPath, "PortHandles");
monitorPath = modelName + "/Battery Cell Contact Monitoring";
add_block("batt_sl_lib/Protection/Battery Cell Contact Monitoring", ...
    monitorPath, position=[625,110,785,190]);
monitorPorts = get_param(monitorPath, "PortHandles");
set_param(monitorPorts.Outport(1), "DataLogging", "on");
set_param(monitorPorts.Outport(2), "DataLogging", "on");
add_line(modelName, probePorts.Outport, monitorPorts.Inport);
lineNames = ["CellConnectionError", "CellConnectionSymptom"];
for index = 1:2
    terminator = modelName + "/Terminator" + string(index);
    add_block("simulink/Sinks/Terminator", terminator, ...
        position=[900,80 + 40 * index,920,100 + 40 * index]);
    terminatorPorts = get_param(terminator, "PortHandles");
    line = add_line(modelName, monitorPorts.Outport(index), terminatorPorts.Inport);
    set_param(line, "Name", lineNames(index));
end
set_param(modelName, "ZoomFactor", "FitSystem");
save_system(modelName);
if bdIsLoaded(faultModel), save_system(faultModel); end
localCloseGeneratedModels([faultModel, modelName]);
if bdIsLoaded(libraryName + "_lib"), close_system(libraryName + "_lib", 0); end

localCanonicalizeGeneratedSsc(destinationDir);
localCanonicalizeSlx(fullfile(destinationDir, modelName + ".slx"));
localCanonicalizeSlx(fullfile(destinationDir, faultModel + ".slx"));
localCanonicalizeSlx(fullfile(destinationDir, libraryName + "_lib.slx"), true);
localCanonicalizeFaultInfo(fullfile(destinationDir, modelName + "_faultInfo.xml"));
localCanonicalizeMatHeaders(destinationDir);
report = struct("task_id", "F90-XBATT-09", ...
    "status", "OFFICIAL_EXAMPLE_GENERATION_COMPLETE_DETERMINISTIC", ...
    "core_source_modifications", 0, ...
    "generation_source", "R2025a DisconnectedCellDetectionExample", ...
    "identity_normalization", ["Simscape code generated on:", ...
    "coreProperties timestamps", "ModelUUID", "BDUuid", ...
    "ScheduleCore.xml", "ScheduleEditor.xml", ...
    "empty library dictionary UUIDs", "fault metadata UUIDs/order/time", ...
    "embedded generated-on text", "generated library-browser UI omitted"]);
end

function localCanonicalizeGeneratedSsc(destinationDir)
files = localFindFiles(destinationDir, ".ssc");
for index = 1:numel(files)
    pathValue = fullfile(files(index).folder, files(index).name);
    text = fileread(pathValue);
    text = regexprep(text, '(?m)^\s*%\s+Simscape code generated on:[^\r\n]*', ...
        "    %    Simscape code generated on: 2014-10-02 17:27:43");
    fid = fopen(pathValue, "w", "n", "UTF-8");
    assert(fid >= 0, "SimuVerity:Importer:CanonicalSsc", ...
        "Cannot rewrite generated component: %s", pathValue);
    fwrite(fid, text, "char");
    fclose(fid);
end
end

function localCanonicalizeMatHeaders(destinationDir)
files = localFindFiles(destinationDir, ".mat");
for index = 1:numel(files)
    pathValue = fullfile(files(index).folder, files(index).name);
    fid = fopen(pathValue, "r+");
    assert(fid >= 0, "SimuVerity:Importer:CanonicalMat", ...
        "Cannot open generated MAT file: %s", pathValue);
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    header = char(fread(fid, 116, "*char").');
    updated = regexprep(header, "Created on: [A-Za-z]{3} [A-Za-z]{3} [ 0-9]{2} [0-9:]{8} [0-9]{4}", ...
        "Created on: Thu Oct 02 17:27:43 2014");
    assert(~strcmp(header, updated) && numel(updated) == 116, ...
        "SimuVerity:Importer:CanonicalMat", ...
        "Expected generated MAT timestamp is missing: %s", pathValue);
    fseek(fid, 0, "bof"); fwrite(fid, updated, "char");
end
end

function localCanonicalizeFaultInfo(pathValue)
assert(isfile(pathValue), "SimuVerity:Importer:CanonicalFaultInfo", ...
    "Generated fault metadata is missing: %s", pathValue);
text = fileread(pathValue);
rules = {
    '(<faultinfo\.FaultContainerSet[^>]* uuid=")[^"]+(")', ...
        '$18d8fbcdb-7d5f-42fb-9eca-405462b5d8a3$2';
    '(<conditionals[^>]* uuid=")[^"]+(")', ...
        '$1577da61b-a77a-4503-8b46-9e6529edc4ff$2';
    '(<symbols[^>]* uuid=")[^"]+(")', ...
        '$1b343eff0-9b28-45ae-bbb5-0aca091cf06d$2';
    '(<faultContainers[^>]* uuid=")[^"]+(")', ...
        '$1bea05b60-8277-4f88-bbc9-e5c85ba48211$2';
    '(<(?:activeFault|faults|associatedFaults)[^>]* uuid=")[^"]+(")', ...
        '$1f54b7152-3640-46f4-8f45-cf86ba875895$2';
    '(<triggerOn[^>]* uuid=")[^"]+(")', ...
        '$1d2f5a119-d741-4e01-b3ee-2c6f641a88d3$2';
    '(<faultinfo\.FailureModeContainer[^>]* uuid=")[^"]+(")', ...
        '$1e12acd60-a988-4e03-aed1-56e516ae105b$2';
    '(<failureModes[^>]* uuid=")[^"]+(")', ...
        '$1047ef940-d08a-4412-ba48-aaff4bd82224$2';
    '(?s)(<faults[^>]*>.*?<checksum>)[^<]*(</checksum>)', ...
        '$1735e5b72-386b-4ad1-8273-1f95a8925320$2';
    '(<lastUpdatedAt>)[^<]*(</lastUpdatedAt>)', ...
        '$12014-10-02T17:27:43$2';
    '(<modelUUID>)[^<]*(</modelUUID>)', ...
        '$1a7b9a257-e96a-451e-a9ea-2d5cedc466aa$2';
    '(<faultModelUUID>)[^<]*(</faultModelUUID>)', ...
        '$1a7b9a257-e96a-451e-a9ea-2d5cedc466aa$2'
    };
for index = 1:size(rules, 1)
    assert(~isempty(regexp(text, rules{index, 1}, "once")), ...
        "SimuVerity:Importer:CanonicalFaultInfo", ...
        "Expected volatile fault metadata is missing: %s", pathValue);
    text = regexprep(text, rules{index, 1}, rules{index, 2});
end
faultContainer = regexp(text, ...
    '(?s)<faultinfo\.FaultContainerSet[^>]*>.*?</faultinfo\.FaultContainerSet>', ...
    "match", "once");
failureMode = regexp(text, ...
    '(?s)<faultinfo\.FailureModeContainer[^>]*>.*?</faultinfo\.FailureModeContainer>', ...
    "match", "once");
prefix = regexp(text, '(?s)^.*?<MF0[^>]*>', "match", "once");
assert(~isempty(faultContainer) && ~isempty(failureMode) && ~isempty(prefix), ...
    "SimuVerity:Importer:CanonicalFaultInfo", ...
    "Expected fault metadata containers are missing: %s", pathValue);
text = sprintf('%s\n  %s\n  %s\n</MF0>', ...
    prefix, strtrim(faultContainer), strtrim(failureMode));
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:Importer:CanonicalFaultInfo", ...
    "Cannot rewrite generated fault metadata: %s", pathValue);
fwrite(fid, text, "char");
fclose(fid);
end

function files = localFindFiles(root, extension)
entries = dir(root); files = entries([]);
for index = 1:numel(entries)
    name = string(entries(index).name);
    if entries(index).isdir
        if name ~= "." && name ~= ".."
            children = localFindFiles(fullfile(root, name), extension);
            files = [files; children]; %#ok<AGROW>
        end
    elseif endsWith(name, extension, IgnoreCase=true)
        entries(index).folder = root;
        files = [files; entries(index)]; %#ok<AGROW>
    end
end
end

function localCanonicalizeSlx(modelPath, normalizeLibraryIdentity)
arguments
    modelPath
    normalizeLibraryIdentity (1,1) logical = false
end
assert(isfile(modelPath), "SimuVerity:Importer:CanonicalSlx", ...
    "Generated reference model is missing: %s", modelPath);
staging = string(tempname); mkdir(staging);
cleanup = onCleanup(@() localRemoveTree(staging)); %#ok<NASGU>
unzip(modelPath, staging);
localRewriteXml(fullfile(staging, "metadata", "coreProperties.xml"), ...
    "<dcterms:created[^>]*>[^<]*</dcterms:created>", ...
    "<dcterms:created xsi:type=""dcterms:W3CDTF"">2014-10-02T17:27:43Z</dcterms:created>");
localRewriteXml(fullfile(staging, "metadata", "coreProperties.xml"), ...
    "<dcterms:modified[^>]*>[^<]*</dcterms:modified>", ...
    "<dcterms:modified xsi:type=""dcterms:W3CDTF"">2014-10-02T17:27:43Z</dcterms:modified>");
localRewriteXml(fullfile(staging, "simulink", "blockdiagram.xml"), ...
    "(?s)(<P Name=""ModelUUID""[^>]*>)[^<]*(</P>)", ...
    "$1a7b9a257-e96a-451e-a9ea-2d5cedc466aa$2");
localRewriteXmlIfPresent(fullfile(staging, "simulink", "blockdiagram.xml"), ...
    "(?s)(<Field Name=""UUID"" Class=""char"">)[^<]*(</Field>)", ...
    "$1b3f8a40d-ca0c-4114-af13-8a1b6172d9f7$2");
localRewriteXmlIfPresent(fullfile(staging, "simulink", "windowsInfo.xml"), ...
    "(?s)(<P Name=""BDUuid""[^>]*>)[^<]*(</P>)", ...
    "$1b3f8a40d-ca0c-4114-af13-8a1b6172d9f7$2");
if normalizeLibraryIdentity
    localRewriteXml(fullfile(staging, "metadata", "mwcorePropertiesExtension.xml"), ...
        "(?s)(<uuid>)[^<]*(</uuid>)", ...
        "$1efff74ee-cb53-4cf4-8e80-243275e121ab$2");
    localRewriteXml(fullfile(staging, "simulink", "modelDictionary.xml"), ...
        '(?s)(<System[^>]* uuid=")[^"]+(")', ...
        "$1f0f8ac73-7834-405a-9476-1cab3d2416e8$2");
    localRewriteXml(fullfile(staging, "simulink", "modelDictionary.xml"), ...
        '(?s)(<Interface[^>]* uuid=")[^"]+(")', ...
        "$18ecbe3a3-1c8b-4400-90b2-b24b05c718b0$2");
    localCanonicalizeEmbeddedGeneratedTimes(staging);
    localRemoveLibraryBrowserMetadata(staging);
end
% ScheduleCore.xml and ScheduleEditor.xml contain only generated editor
% UUID/UI layout; omitting them preserves executable model semantics.
for name = ["ScheduleCore.xml", "ScheduleEditor.xml"]
    pathValue = fullfile(staging, "simulink", name);
    if isfile(pathValue), delete(pathValue); end
end
files = dir(fullfile(staging, "**", "*")); files = files(~[files.isdir]);
relative = string(fullfile({files.folder}, {files.name}));
relative = erase(relative, staging + filesep); relative = sort(relative);
temporaryZip = string(tempname) + ".zip";
stream = javaObject("java.util.zip.ZipOutputStream", ...
    javaObject("java.io.FileOutputStream", char(temporaryZip)));
stream.setLevel(9); streamCleanup = onCleanup(@() localCloseZip(stream)); %#ok<NASGU>
for index = 1:numel(relative)
    entry = javaObject("java.util.zip.ZipEntry", char(replace(relative(index), "\", "/")));
    entry.setTime(0); stream.putNextEntry(entry);
    fid = fopen(fullfile(staging, relative(index)), "r");
    assert(fid >= 0, "SimuVerity:Importer:CanonicalSlx", "Cannot read %s", relative(index));
    bytes = fread(fid, Inf, "*uint8"); fclose(fid);
    stream.write(typecast(bytes, "int8"), 0, numel(bytes)); stream.closeEntry();
end
stream.close(); movefile(temporaryZip, modelPath, "f");
end

function localCanonicalizeEmbeddedGeneratedTimes(staging)
files = localFindFiles(staging, ".xml");
changed = 0;
for index = 1:numel(files)
    pathValue = fullfile(files(index).folder, files(index).name);
    text = fileread(pathValue);
    updated = regexprep(text, ...
        'Simscape code generated on: [^<\r\n]*', ...
        'Simscape code generated on: 02-Oct-2014 17:27:43');
    if strcmp(text, updated), continue; end
    fid = fopen(pathValue, "w", "n", "UTF-8");
    assert(fid >= 0, "SimuVerity:Importer:CanonicalSlx", ...
        "Cannot rewrite embedded generated-on metadata: %s", pathValue);
    fwrite(fid, updated, "char");
    fclose(fid);
    changed = changed + 1;
end
assert(changed >= 2, "SimuVerity:Importer:CanonicalSlx", ...
    "Expected embedded generated-on metadata is missing: %s", staging);
end

function localRemoveLibraryBrowserMetadata(staging)
browserRoot = fullfile(staging, "simulink", "libraryBrowser");
assert(isfolder(browserRoot), "SimuVerity:Importer:CanonicalSlx", ...
    "Expected generated library-browser metadata is missing: %s", browserRoot);
rmdir(browserRoot, "s");
localRewriteXml(fullfile(staging, "[Content_Types].xml"), ...
    '(?m)^\s*<Override[^>]*PartName="/simulink/libraryBrowser/slLibraryBrowser\.xml"[^>]*/>\r?\n?', ...
    '');
localRewriteXml(fullfile(staging, "simulink", "_rels", "blockdiagram.xml.rels"), ...
    '(?m)^\s*<Relationship[^>]*Id="slLibraryBrowser"[^>]*/>\r?\n?', ...
    '');
end

function localRewriteXml(pathValue, pattern, replacement)
assert(isfile(pathValue), "SimuVerity:Importer:CanonicalSlx", "Missing member: %s", pathValue);
text = fileread(pathValue); updated = regexprep(text, pattern, replacement);
assert(~strcmp(text, updated), "SimuVerity:Importer:CanonicalSlx", "Expected volatile field missing: %s", pathValue);
fid = fopen(pathValue, "w", "n", "UTF-8"); assert(fid >= 0, "SimuVerity:Importer:CanonicalSlx", "Cannot rewrite %s", pathValue);
fwrite(fid, updated, "char"); fclose(fid);
end

function localRewriteXmlIfPresent(pathValue, pattern, replacement)
assert(isfile(pathValue), "SimuVerity:Importer:CanonicalSlx", "Missing member: %s", pathValue);
text = fileread(pathValue); updated = regexprep(text, pattern, replacement);
if strcmp(text, updated), return; end
fid = fopen(pathValue, "w", "n", "UTF-8"); assert(fid >= 0, "SimuVerity:Importer:CanonicalSlx", "Cannot rewrite %s", pathValue);
fwrite(fid, updated, "char"); fclose(fid);
end

function localRemoveTree(pathValue)
if isfolder(pathValue), try, rmdir(pathValue, "s"); catch, end, end
end

function localCloseZip(stream)
try, stream.close(); catch, end
end

function localCloseGeneratedModels(modelNames)
% The generated harness and library live only in this isolated importer
% session.  Close each one without saving so MATLAB -batch can terminate
% after the canonical output has been written.
for index = 1:numel(modelNames)
    modelName = string(modelNames(index));
    if bdIsLoaded(modelName), close_system(modelName, 0); end
end
end
