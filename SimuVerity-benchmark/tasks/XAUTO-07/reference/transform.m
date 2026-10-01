function report = transform(sourceDir, destinationDir)
%TRANSFORM Materialize a public-I/O wrapper around the official EV example.
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

sourceModel = fullfile(destinationDir, "IPMSMAxleDriveEV.slx");
assert(isfile(sourceModel), "SimuVerity:Importer:SourceModel", ...
    "The verified R2025a IPMSMAxleDriveEV.slx file is missing.");
targetModel = fullfile(destinationDir, ...
    "IPMSMAxleDriveEV_SimuVerityReference.slx");
copyfile(sourceModel, targetModel);
model = "IPMSMAxleDriveEV_SimuVerityReference";

oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(destinationDir, "-begin");
if bdIsLoaded(model), close_system(model, 0); end
load_system(targetModel);
modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>

localVerifyOfficialTapSources(model);
localInstallPublicInput(model);
localInstallPublicOutputs(model);
set_param(model, ...
    "ReturnWorkspaceOutputs", "on", ...
    "SignalLogging", "on", ...
    "StopTime", "5", ...
    "LimitDataPoints", "off");
save_system(model);
localNormalizeSlx(targetModel, sourceModel);

report = struct( ...
    "task_id", "F90-XAUTO-07", ...
    "status", "PUBLIC_IO_REFERENCE_WRAPPER_COMPLETE", ...
    "source_entrypoint", "IPMSMAxleDriveEV.slx", ...
    "entrypoint", "IPMSMAxleDriveEV_SimuVerityReference.slx", ...
    "core_source_modifications", 0, ...
    "official_source_preserved", true, ...
    "public_input_bindings", 2, ...
    "public_input_binding_method", "task-facing gain blocks", ...
    "unchanged_official_input_channels", [3 4], ...
    "measurement_outputs", ["driver_input", "motor_torque", ...
        "phase_currents", "vehicle_speed"]);
end

function localVerifyOfficialTapSources(model)
paths = [ ...
    model + "/Inputs", ...
    model + "/Scopes/Mux", ...
    model + "/Scopes/From2", ...
    model + "/Scopes/Rate Transition2", ...
    model + "/Scopes/From3", ...
    model + "/Scopes/From10", ...
    model + "/Scopes/Rate Transition1", ...
    model + "/Scopes/From12"];
for index = 1:numel(paths)
    assert(getSimulinkBlockHandle(paths(index)) > 0, ...
        "SimuVerity:Importer:BlockLookup", ...
        "A required official signal source is missing: %s", paths(index));
end
assert(string(get_param(model + "/Inputs", "FileName")) == ...
    "IPMSMAxleDriveEVInputs.mat", ...
    "SimuVerity:Importer:OfficialInputBinding", ...
    "The official Signal Editor input file binding changed.");
assert(string(get_param(model + "/Inputs", "ActiveScenario")) == ...
    "StartStop", "SimuVerity:Importer:OfficialInputBinding", ...
    "The official StartStop scenario binding changed.");
assert(string(get_param(model + "/Scopes/From2", "GotoTag")) == "Tq_ref");
assert(string(get_param(model + "/Scopes/From3", "GotoTag")) == "Tq_estim");
assert(string(get_param(model + "/Scopes/From10", "GotoTag")) == "Tq_lim");
assert(string(get_param(model + "/Scopes/From12", "GotoTag")) == "v");
end

function localInstallPublicInput(model)
inputs = model + "/Inputs";
vehicleController = model + "/Vehicle Controller";
brakeGoto = model + "/Goto4";
accelerationGain = model + "/SimuVerity Acceleration Scale";
brakeGain = model + "/SimuVerity Brake Scale";

localInsertScale(model, inputs, 1, accelerationGain, ...
    "ev_drive_input.acceleration_scale", [255 20 285 45], ...
    vehicleController, 1);
localInsertScale(model, inputs, 2, brakeGain, ...
    "ev_drive_input.brake_scale", [255 115 285 140], ...
    [vehicleController; brakeGoto], [2; 1]);
end

function localInsertScale(parent, source, sourcePortIndex, gainBlock, ...
        gainExpression, position, destinations, destinationPortIndices)
sourcePorts = get_param(source, "PortHandles");
assert(numel(sourcePorts.Outport) >= sourcePortIndex, ...
    "SimuVerity:Importer:PublicInputPort", ...
    "The official Signal Editor output contract changed.");
sourcePort = sourcePorts.Outport(sourcePortIndex);
oldLine = get_param(sourcePort, "Line");
assert(oldLine > 0, "SimuVerity:Importer:PublicInputLine", ...
    "An official public-input line is missing.");
oldDestinations = sort(double(reshape(get_param(oldLine, ...
    "DstPortHandle"), [], 1)));
expectedDestinations = zeros(numel(destinations), 1);
for index = 1:numel(destinations)
    ports = get_param(destinations(index), "PortHandles");
    expectedDestinations(index) = ports.Inport(destinationPortIndices(index));
end
assert(isequal(oldDestinations, sort(expectedDestinations)), ...
    "SimuVerity:Importer:PublicInputTopology", ...
    "The official public-input destination topology changed.");
delete_line(oldLine);

add_block("simulink/Math Operations/Gain", gainBlock, ...
    "Gain", gainExpression, ...
    "Multiplication", "Element-wise(K.*u)", ...
    "Position", position);
gainPorts = get_param(gainBlock, "PortHandles");
add_line(parent, sourcePort, gainPorts.Inport(1), "autorouting", "on");
for index = 1:numel(expectedDestinations)
    add_line(parent, gainPorts.Outport(1), expectedDestinations(index), ...
        "autorouting", "on");
end
end

function localInstallPublicOutputs(model)
parent = model + "/Scopes";
torqueMux = parent + "/SimuVerity Motor Torque";
driverSink = parent + "/SimuVerity driver_input";
torqueSink = parent + "/SimuVerity motor_torque";
currentSink = parent + "/SimuVerity phase_currents";
speedSink = parent + "/SimuVerity vehicle_speed";

add_block("simulink/Signal Routing/Mux", torqueMux, ...
    "Inputs", "4", "Position", [665 15 670 105]);
localAddWorkspaceSink(driverSink, "driver_input", [665 135 805 165]);
localAddWorkspaceSink(torqueSink, "motor_torque", [720 45 860 75]);
localAddWorkspaceSink(currentSink, "phase_currents", [665 180 805 210]);
localAddWorkspaceSink(speedSink, "vehicle_speed", [665 225 805 255]);

localConnect(parent, model + "/Scopes/Mux", 1, driverSink, 1);
localConnect(parent, model + "/Scopes/From2", 1, torqueMux, 1);
localConnect(parent, model + "/Scopes/Rate Transition2", 1, torqueMux, 2);
localConnect(parent, model + "/Scopes/From3", 1, torqueMux, 3);
localConnect(parent, model + "/Scopes/From10", 1, torqueMux, 4);
localConnect(parent, torqueMux, 1, torqueSink, 1);
localConnect(parent, model + "/Scopes/Rate Transition1", 1, currentSink, 1);
localConnect(parent, model + "/Scopes/From12", 1, speedSink, 1);
end

function localAddWorkspaceSink(block, variable, position)
add_block("simulink/Sinks/To Workspace", block, ...
    "VariableName", variable, ...
    "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", ...
    "Position", position);
end

function localConnect(parent, source, outputIndex, destination, inputIndex)
sourcePorts = get_param(source, "PortHandles");
destinationPorts = get_param(destination, "PortHandles");
assert(numel(sourcePorts.Outport) >= outputIndex && ...
    numel(destinationPorts.Inport) >= inputIndex, ...
    "SimuVerity:Importer:PortLookup", ...
    "A required task-facing instrumentation port is missing.");
add_line(parent, sourcePorts.Outport(outputIndex), ...
    destinationPorts.Inport(inputIndex), "autorouting", "on");
end

function localCloseModel(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function localNormalizeSlx(modelPath, sourceModelPath)
% Normalize save-as-only metadata and ZIP timestamps for a stable archive.
temporary = string(modelPath) + ".normalizing";
assert(~isfile(temporary), "SimuVerity:Importer:NormalizeReuse", ...
    "SLX normalization output already exists: %s", temporary);
input = java.util.zip.ZipInputStream(java.io.BufferedInputStream( ...
    java.io.FileInputStream(char(modelPath))));
output = java.util.zip.ZipOutputStream(java.io.BufferedOutputStream( ...
    java.io.FileOutputStream(char(temporary))));
streamCleanup = onCleanup(@() localCloseZipStreams(input, output)); %#ok<NASGU>
fixedTimeMilliseconds = int64(946684800000); % 2000-01-01T00:00:00Z
sourceThumbnail = localReadZipEntry(sourceModelPath, ...
    "metadata/thumbnail.png");
sourceSignalEditorData = localReadZipEntry(sourceModelPath, ...
    "simulink/bdmxdata/UserData_2032.mxarray");
while true
    sourceEntry = input.getNextEntry();
    if isempty(sourceEntry), break; end
    name = string(sourceEntry.getName());
    payload = javaMethod("toByteArray", ...
        "org.apache.commons.io.IOUtils", input);
    if name == "metadata/thumbnail.png"
        payload = sourceThumbnail;
    elseif name == "simulink/bdmxdata/UserData_2032.mxarray"
        % Instrumentation never changes the official Signal Editor data.
        % Preserve the verified source payload so save_system cannot embed
        % the importer staging directory in the generated model.
        payload = sourceSignalEditorData;
    elseif name == "metadata/coreProperties.xml"
        raw = reshape(typecast(payload, "uint8"), 1, []);
        value = string(native2unicode(raw, "UTF-8"));
        value = regexprep(value, ...
            '<dcterms:modified xsi:type="dcterms:W3CDTF">[^<]+</dcterms:modified>', ...
            '<dcterms:modified xsi:type="dcterms:W3CDTF">2000-01-01T00:00:00Z</dcterms:modified>');
        payload = typecast(unicode2native(char(value), "UTF-8"), "int8");
    elseif name == "simulink/blockdiagram.xml"
        raw = reshape(typecast(payload, "uint8"), 1, []);
        value = string(native2unicode(raw, "UTF-8"));
        value = regexprep(value, '<P Name="ModelUUID">[^<]+</P>', ...
            '<P Name="ModelUUID">5f900023-0000-4000-8000-000000000023</P>');
        value = replace(value, ...
            '<P Name="model_" Class="char">IPMSMAxleDriveEV_SimuVerityReference</P>', ...
            '<P Name="model_" Class="char">$bdroot</P>');
        value = replace(value, ...
            '<Cell Class="char">IPMSMAxleDriveEV_SimuVerityReference</Cell>', ...
            '<Cell Class="char">$bdroot</Cell>');
        payload = typecast(unicode2native(char(value), "UTF-8"), "int8");
    elseif name == "simulink/hdlParams.xml"
        raw = reshape(typecast(payload, "uint8"), 1, []);
        value = string(native2unicode(raw, "UTF-8"));
        value = replace(value, ...
            '<Cell Class="char">IPMSMAxleDriveEV_SimuVerityReference</Cell>', ...
            '<Cell Class="char">$bdroot</Cell>');
        payload = typecast(unicode2native(char(value), "UTF-8"), "int8");
    elseif name == "simulink/windowsInfo.xml"
        raw = reshape(typecast(payload, "uint8"), 1, []);
        value = string(native2unicode(raw, "UTF-8"));
        value = regexprep(value, ...
            '<P Name="BDUuid" Class="char">[^<]+</P>', ...
            '<P Name="BDUuid" Class="char">5f900023-0000-4000-8000-000000000023</P>');
        payload = typecast(unicode2native(char(value), "UTF-8"), "int8");
    end
    targetEntry = java.util.zip.ZipEntry(char(name));
    targetEntry.setTime(fixedTimeMilliseconds);
    output.putNextEntry(targetEntry);
    if numel(payload) > 0, output.write(payload, 0, numel(payload)); end
    output.closeEntry();
    input.closeEntry();
end
output.finish();
output.close();
input.close();
movefile(temporary, modelPath, "f");
end

function payload = localReadZipEntry(archivePath, expectedName)
input = java.util.zip.ZipInputStream(java.io.BufferedInputStream( ...
    java.io.FileInputStream(char(archivePath))));
inputCleanup = onCleanup(@() input.close()); %#ok<NASGU>
payload = [];
while true
    entry = input.getNextEntry();
    if isempty(entry), break; end
    if string(entry.getName()) == string(expectedName)
        payload = javaMethod("toByteArray", ...
            "org.apache.commons.io.IOUtils", input);
        input.closeEntry();
        break
    end
    input.closeEntry();
end
assert(~isempty(payload), "SimuVerity:Importer:NormalizeSource", ...
    "Required source SLX entry is missing: %s", expectedName);
end

function localCloseZipStreams(input, output)
try, input.close(); catch, end
try, output.close(); catch, end
end
