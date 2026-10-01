function modelPath = f90_xtherm05_materialize_reference(referenceFilesRoot, outDir)
%f90_xtherm05_materialize_reference Build the current benchmark reference.
%
% The pinned upstream model supplies the electro-thermal-fluid plant and its
% existing CC-CV controller.  This task-local transformation only binds the
% public scenario inputs, exposes physical measurements already present on
% that plant, and fixes evaluator runtime settings.  It does not replace the
% battery, cooling plate, coolant network, or controller implementation.
arguments
    referenceFilesRoot (1,1) string
    outDir (1,1) string = referenceFilesRoot
end

assert(string(version("-release")) == "2025a", ...
    "SimuVerity:XTHERM05:ReleaseMismatch", ...
    "F90-XTHERM-05 reference materialization requires MATLAB R2025a.");

sourceRoot = fullfile(referenceFilesRoot, "Battery-Cooling-Plate-Simscape");
sourceModel = fullfile(sourceRoot, "Model", ...
    "PouchBatteryPack96S3PWithCustomCoolingPlateForCharging.slx");
projectPath = fullfile(sourceRoot, "BatteryCoolingPlateSimscape.prj");
assert(isfile(sourceModel), "SimuVerity:XTHERM05:SourceMissing", ...
    "The public reference source model is missing.");
assert(isfile(projectPath), "SimuVerity:XTHERM05:ProjectMissing", ...
    "The public reference project is missing.");
if ~isfolder(outDir), mkdir(outDir); end
modelPath = fullfile(outDir, "XTHERM05_reference.slx");
if isfile(modelPath), delete(modelPath); end

old = pwd;
cleanupDir = onCleanup(@() cd(old)); %#ok<NASGU>
cd(sourceRoot);
project = openProject(projectPath);
cleanupProject = onCleanup(@() close_project(project)); %#ok<NASGU>

sourceName = "PouchBatteryPack96S3PWithCustomCoolingPlateForCharging";
load_system(sourceModel);
save_system(sourceName, modelPath);
close_system(sourceName, 0);
load_system(modelPath);
model = "XTHERM05_reference";
cleanupModel = onCleanup(@() close_if_loaded(model)); %#ok<NASGU>

def = f90_xtherm05_definition;
for index = 1:numel(def.public_inputs)
    assignin("base", def.public_inputs(index).name, ...
        def.public_inputs(index).nominal);
end

pack = model + "/BatteryPack96S3P";
plate = pack + "/Cooling Plate";
flowCommand = model + "/Flowrate";
inlet = model + "/Reservoir In";
outlet = model + "/Reservoir Out";
controller = model + "/Battery CC-CV";

set_param(flowCommand, "constant", "coolant_flow_lpm", "constant_unit", "lpm");
set_param(inlet, "reservoir_temperature", "coolant_inlet_temperature_K");
set_param(outlet, "reservoir_temperature", "coolant_inlet_temperature_K");
set_param(plate, "initTempPlate", "coolant_inlet_temperature_K");
set_param(controller, "MaxCellVoltage", "max_cell_voltage_V");
set_param(model + "/Charge On", "Value", "1");

% Bind the initial temperature at every generated module instance.  These
% are instance parameters on the pinned generated battery subsystem, not an
% evaluator-only post-processing override.
allBlocks = find_system(pack, "LookUnderMasks", "all", "FollowLinks", "on", ...
    "Type", "Block");
moduleCount = 0;
for index = 1:numel(allBlocks)
    parameters = get_param(allBlocks{index}, "ObjectParameters");
    if isfield(parameters, "batteryTemperature")
        try
            set_param(allBlocks{index}, ...
                "batteryTemperature", ...
                "[initial_battery_temperature_K initial_battery_temperature_K]", ...
                "batteryTemperature_unit", "K");
            moduleCount = moduleCount + 1;
        catch
        end
    end
end
assert(moduleCount >= 12, ...
    "F90_XTHERM05_MODULE_BINDING_INCOMPLETE:%d", moduleCount);

% Replace the fixed charging limit by the declared in-run limit change.
baseCurrent = model + "/Max Current";
oldPorts = get_param(baseCurrent, "PortHandles");
oldLine = get_param(oldPorts.Outport(1), "Line");
assert(oldLine > 0, "F90_XTHERM05_CURRENT_LIMIT_LINE_MISSING");
oldDestinations = get_param(oldLine, "DstPortHandle");
delete_line(oldLine);
set_param(baseCurrent, "Value", "charge_current_A");
step = model + "/Charge Current Limit Step";
sumBlock = model + "/Charge Current Limit Sum";
add_block("simulink/Sources/Step", step, ...
    "Time", "charge_step_time_s", ...
    "Before", "0", ...
    "After", "charge_current_A*charge_step_fraction", ...
    "Position", [340 250 375 285]);
add_block("simulink/Math Operations/Sum", sumBlock, ...
    "Inputs", "++", "Position", [410 218 435 267]);
add_line(model, "Max Current/1", "Charge Current Limit Sum/1", ...
    "autorouting", "on");
add_line(model, "Charge Current Limit Step/1", ...
    "Charge Current Limit Sum/2", "autorouting", "on");
sumPorts = get_param(sumBlock, "PortHandles");
for index = 1:numel(oldDestinations)
    add_line(model, sumPorts.Outport(1), oldDestinations(index), ...
        "autorouting", "on");
end

% The generated pack exposes the 24 plate and 24 battery temperatures as
% separate physical-model outputs.  Current is reduced to one
% cell-equivalent series-path measurement using the same 24-way averaging
% scale as the source voltage feedback.
add_log_from_port(model, pack, 1, "plate_temperature");
add_log_from_port(model, pack, 3, "battery_temperature");
currentSelector = model + "/Current Measurement Selector";
add_block(model + "/Signal Selector", currentSelector, ...
    "Position", [935 270 1085 330]);
packPorts = get_param(pack, "PortHandles");
selectorPorts = get_param(currentSelector, "PortHandles");
add_line(model, packPorts.Outport(2), selectorPorts.Inport(1), ...
    "autorouting", "on");
packCurrentGain = model + "/Parallel Branches to Pack Current";
add_block("simulink/Math Operations/Gain", packCurrentGain, ...
    "Gain", "3", "Position", [1095 275 1140 315]);
gainPorts = get_param(packCurrentGain, "PortHandles");
add_line(model, selectorPorts.Outport(1), gainPorts.Inport(1), ...
    "autorouting", "on");
add_log_from_port(model, packCurrentGain, 1, "pack_current");
add_log_from_port(model, model + "/Signal Selector", 1, ...
    "cell_equivalent_voltage");

% Propagate the source plate's physical dT and dP sensor outputs without
% altering the thermal-liquid network.
add_physical_signal_log(pack, plate, 3, "coolant_temperature_rise", "K", ...
    [1215 675 1255 705], [1300 670 1430 700]);
add_physical_signal_log(pack, plate, 4, "coolant_pressure_drop", "bar", ...
    [1215 725 1255 755], [1300 720 1430 750]);

set_param(model, ...
    "SolverType", "Variable-step", ...
    "Solver", "daessc", ...
    "StartTime", "0", ...
    "StopTime", num2str(def.sim.stop, "%.15g"), ...
    "MaxStep", num2str(def.sim.max_step, "%.15g"), ...
    "ReturnWorkspaceOutputs", "on", ...
    "SimMechanicsOpenEditorOnUpdate", "off");
annotation = Simulink.Annotation(model, ...
    "F90-XTHERM-05 | distributed cooling-plate reference");
annotation.Position = [180 10 870 30];
set_param(model, "SimulationCommand", "update");
save_system(model, modelPath);
localNormalizeSlx(modelPath, sourceModel);
fprintf("F90_XTHERM05_BUILD_OK modules=%d path=%s\n", moduleCount, modelPath);
end

function add_log_from_port(model, parentBlock, portIndex, varName)
ports = get_param(parentBlock, "PortHandles");
assert(numel(ports.Outport) >= portIndex, ...
    "F90_XTHERM05_LOG_SOURCE_PORT_MISSING:%s:%d", parentBlock, portIndex);
safe = regexprep(varName, "[^A-Za-z0-9_]", "_");
destination = model + "/Log_" + safe;
add_block("simulink/Sinks/To Workspace", destination, ...
    "VariableName", varName, ...
    "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", ...
    "Position", [1110 40+45*mod(sum(double(char(varName))),8) ...
    1250 68+45*mod(sum(double(char(varName))),8)]);
destinationPorts = get_param(destination, "PortHandles");
add_line(model, ports.Outport(portIndex), destinationPorts.Inport(1), ...
    "autorouting", "on");
end

function add_physical_signal_log(parent, source, portIndex, varName, unit, ...
    converterPosition, logPosition)
sourcePorts = get_param(source, "PortHandles");
assert(numel(sourcePorts.RConn) >= portIndex, ...
    "F90_XTHERM05_PHYSICAL_SOURCE_PORT_MISSING:%s:%d", source, portIndex);
converter = parent + "/Measure_" + varName;
logBlock = parent + "/Log_" + varName;
add_block("nesl_utility/PS-Simulink" + newline + "Converter", converter, ...
    "Unit", unit, "Position", converterPosition);
converterPorts = get_param(converter, "PortHandles");
add_line(parent, sourcePorts.RConn(portIndex), ...
    converterPorts.LConn(1), "autorouting", "on");
add_block("simulink/Sinks/To Workspace", logBlock, ...
    "VariableName", varName, ...
    "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", ...
    "Position", logPosition);
logPorts = get_param(logBlock, "PortHandles");
add_line(parent, converterPorts.Outport(1), logPorts.Inport(1), ...
    "autorouting", "on");
end

function close_if_loaded(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function close_project(project)
try
    if ~isempty(project), close(project); end
catch
end
end

function localNormalizeSlx(modelPath, sourceModelPath)
% Normalize save-only metadata and ZIP timestamps for a stable archive.
temporary = string(modelPath) + ".normalizing";
assert(~isfile(temporary), "SimuVerity:XTHERM05:NormalizeReuse", ...
    "SLX normalization output already exists: %s", temporary);
input = java.util.zip.ZipInputStream(java.io.BufferedInputStream( ...
    java.io.FileInputStream(char(modelPath))));
output = java.util.zip.ZipOutputStream(java.io.BufferedOutputStream( ...
    java.io.FileOutputStream(char(temporary))));
streamCleanup = onCleanup(@() localCloseZipStreams(input, output)); %#ok<NASGU>
fixedTimeMilliseconds = int64(946684800000); % 2000-01-01T00:00:00Z
fixedUuid = "53a73b22-8993-5f4d-ab31-164f792300e0";
sourceThumbnail = localReadZipEntry(sourceModelPath, "metadata/thumbnail.png");
while true
    sourceEntry = input.getNextEntry();
    if isempty(sourceEntry), break; end
    name = string(sourceEntry.getName());
    payload = javaMethod("toByteArray", ...
        "org.apache.commons.io.IOUtils", input);
    if name == "metadata/thumbnail.png"
        payload = sourceThumbnail;
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
            '<P Name="ModelUUID">' + fixedUuid + '</P>');
        payload = typecast(unicode2native(char(value), "UTF-8"), "int8");
    elseif name == "simulink/windowsInfo.xml"
        raw = reshape(typecast(payload, "uint8"), 1, []);
        value = string(native2unicode(raw, "UTF-8"));
        value = regexprep(value, ...
            '<P Name="BDUuid" Class="char">[^<]+</P>', ...
            '<P Name="BDUuid" Class="char">' + fixedUuid + '</P>');
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
assert(~isempty(payload), "SimuVerity:XTHERM05:NormalizeSource", ...
    "Required source SLX entry is missing: %s", expectedName);
end

function localCloseZipStreams(input, output)
try, input.close(); catch, end
try, output.close(); catch, end
end
