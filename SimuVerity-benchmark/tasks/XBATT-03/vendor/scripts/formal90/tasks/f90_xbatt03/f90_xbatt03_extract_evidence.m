function evidence = f90_xbatt03_extract_evidence(modelPath, outDir)
%F90_XBATT03_EXTRACT_EVIDENCE One-session, score-free evidence extraction.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

root = localProjectRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
scenarioContract = jsondecode(fileread(simuverity_official_scenarios_path()));
runtimeRoot = string(getenv("SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE"));
sourceRoot = fullfile(runtimeRoot, ...
    "Optimize-BEV-Thermal-Management-with-Simscape");
referenceModel = fullfile(sourceRoot, "Models", ...
    "BEV_Thermal_Management.slx");
if strlength(modelPath) == 0, modelPath = referenceModel; end
assert(isfile(modelPath), "SimuVerity:F90:XBATT03:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XBATT03:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(outDir) == 0
    outDir = fullfile(tempdir, "SimuVerity", "F90-XBATT-03", generationRunId);
end
assert(~isfolder(outDir), "SimuVerity:F90:XBATT03:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

isReference = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
localAssertDependencies(taskRoot, sourceRoot, referenceModel, isReference);
[~, model, modelExtension] = fileparts(modelPath);
localConfigureIsolation;
set(groot, "defaultFigureVisible", "off");
pathBefore = path;
pathCleanup = onCleanup(@() path(pathBefore)); %#ok<NASGU>

evidence = struct( ...
    "schema", "simuverity.f90-xbatt03-evidence.v1", ...
    "task_id", "F90-XBATT-03", ...
    "adapter_recovery_authorized", true, ...
    "adapter_recovery_pending", true, ...
    "generation_run_id", generationRunId, ...
    "model_file", string(model) + string(modelExtension), ...
    "reference_subject", logical(isReference), ...
    "reference_substantive_modifications", 0, ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "scenarios", struct([]), ...
    "static_audit", struct(), ...
    "errors", struct(), ...
    "model_closed_without_save", false, ...
    "started_at", localNow, ...
    "runtime", localRuntimeIdentity);
fatal = [];
try
    if isReference, addpath(genpath(sourceRoot)); end
    load_system(modelPath);
    evidence.load_pass = true;
    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "LimitDataPoints", "off");
    if isReference, localAddReferenceTaps(model); end
    evidence.static_audit = localStaticAudit(model, isReference);
    initialScenario = scenarioContract.scenarios(1);
    [~, initialCommand] = localDriveCommand( ...
        char(initialScenario.drive_template), ...
        double(initialScenario.speed_scale), ...
        double(initialScenario.duration_s));
    localAssignPublicInputs(initialScenario, initialCommand);
    try
        set_param(model, "SimulationCommand", "update");
        evidence.update_pass = true;
    catch ME
        evidence.errors.update = localError(ME);
    end
    if evidence.update_pass
        compiled = false;
        try
            feval(model, [], [], [], "compile");
            compiled = true;
            evidence.compile_pass = true;
        catch ME
            evidence.errors.compile = localError(ME);
        end
        if compiled
            try
                feval(model, [], [], [], "term");
            catch
            end
        end
    end
    if evidence.update_pass && evidence.compile_pass
        rows = repmat(localEmptyScenario, numel(scenarioContract.scenarios), 1);
        for index = 1:numel(scenarioContract.scenarios)
            scenario = scenarioContract.scenarios(index);
            row = localEmptyScenario;
            row.id = string(scenario.id);
            row.class = string(scenario.class);
            row.started_at = localNow;
            timer = tic;
            try
                [cycle, speedCommand] = localDriveCommand( ...
                    char(scenario.drive_template), ...
                    double(scenario.speed_scale), ...
                    double(scenario.duration_s));
                simInput = localSimulationInput(model, scenario, ...
                    cycle, speedCommand, isReference);
                simOut = sim(simInput);
                localValidateSimulationCoverage(simOut, double(scenario.duration_s));
                outputs = localExtractOutputs(simOut, speedCommand, ...
                    double(scenario.duration_s), isReference);
                localValidateOutputs(outputs, double(scenario.duration_s));
                outputFile = "scenario_" + row.id + ".json";
                localWriteJson(fullfile(outDir, outputFile), outputs);
                row.success = true;
                row.output_file = outputFile;
                row.samples = numel(outputs.time_s);
                row.time_start_s = outputs.time_s(1);
                row.time_end_s = outputs.time_s(end);
            catch ME
                row.error = localError(ME);
            end
            row.wall_clock_seconds = toc(timer);
            row.finished_at = localNow;
            rows(index) = row;
            clear simOut outputs
        end
        evidence.scenarios = rows;
    end
catch ME
    fatal = ME;
    evidence.errors.session = localError(ME);
end
try
    if bdIsLoaded(model), close_system(model, 0); end
    evidence.model_closed_without_save = true;
catch ME
    evidence.errors.close_model = localError(ME);
end
allPass = numel(evidence.scenarios) == numel(scenarioContract.scenarios) && ...
    all([evidence.scenarios.success]);
evidence.adapter_recovery_pending = ~(evidence.load_pass && ...
    evidence.update_pass && evidence.compile_pass && allPass);
evidence.finished_at = localNow;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
if ~isempty(fatal), rethrow(fatal); end
assert(evidence.load_pass && evidence.update_pass && ...
    evidence.compile_pass && allPass, ...
    "SimuVerity:F90:XBATT03:EvidenceIncomplete", ...
    "The fixed-evidence session did not complete all required stages.");
end

function localAssertDependencies(taskRoot, sourceRoot, referenceModel, isReference)
required = [
    string(fullfile(taskRoot, "public_spec.json"))
    string(simuverity_official_scenarios_path())
    ];
if isReference
    required = [required
        string(fullfile(sourceRoot, "OptimizingBatteryElectricVehicles.prj"))
        string(referenceModel)
        string(fullfile(sourceRoot, "Scripts_Data", "Data", ...
            "BEV_Thermal_Management_param.m"))
        string(fullfile(sourceRoot, "Scripts_Data", "Data", ...
            "setScenario.m"))
        ];
end
missing = required(~arrayfun(@isfile, required));
assert(isempty(missing), "SimuVerity:F90:XBATT03:DependencyMissing", ...
    "Missing dependency: %s", strjoin(missing, "; "));
end

function localConfigureIsolation
cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XBATT03:Isolation", ...
    "Isolated Simulink cache and codegen folders are required.");
if ~isfolder(cacheDir), mkdir(cacheDir); end
if ~isfolder(codegenDir), mkdir(codegenDir); end
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
end

function [cycle, command] = localDriveCommand(template, scale, duration)
% Scenario profiles are generated here so candidate execution
% never imports the reference repository's driveCycleParam helper.
time = (0:1:duration)';
if strcmpi(string(template), "HWFET")
    knotsT = [0 10 100 270 300 310 360 550 600 745 765]';
    knotsV = [0 0 80 80 55 55 95 95 80 80 0]';
else
    knotsT = [0 20 55 110 125 160 210 300 330 345 360 385 395 405 ...
        430 445 465 490 505 510 530 545 555 565 575 590 610 620 ...
        640 665 680 690 725 750 765]';
    knotsV = [0 0 48 48 0 0 80 80 0 0 56 56 0 0 0 0 55 55 0 0 ...
        40 40 0 0 26 26 45 0 0 40 0 0 45 45 0]';
end
[knotsT, uniqueIndex] = unique(min(knotsT, duration), "stable");
knotsV = knotsV(uniqueIndex);
if knotsT(end) < duration
    knotsT(end+1,1) = duration;
    knotsV(end+1,1) = knotsV(end);
end
speed = min(max(scale .* interp1(knotsT, knotsV, time, "linear"), 0), 130);
cycle = struct("t", time(2:end), "v", speed(2:end), ...
    "mode", zeros(max(numel(time)-1, 0), 1));
command = timeseries(speed, time);
end

function localAssignPublicInputs(scenario, command)
names = ["speed_command","ambient_temperature_C", ...
    "initial_temperature_C","relative_humidity","solar_load_W", ...
    "cabin_temperature_setpoint_C","initial_soc", ...
    "vehicle_mass_kg","cooling_enable"];
values = {command, double(scenario.ambient_temperature_C), ...
    double(scenario.initial_temperature_C), ...
    double(scenario.relative_humidity), ...
    double(scenario.solar_load_W), ...
    double(scenario.cabin_temperature_setpoint_C), ...
    double(scenario.initial_soc), ...
    double(scenario.vehicle_mass_kg), ...
    double(scenario.cooling_enable)};
for index = 1:numel(names)
    assignin("base", char(names(index)), values{index});
end
end

function simInput = localSimulationInput(model, scenario, cycle, command, isReference)
simInput = Simulink.SimulationInput(model);
simInput = simInput.setModelParameter( ...
    "StopTime", num2str(double(scenario.duration_s), "%.15g"), ...
    "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off", ...
    "SaveTime", "on", "TimeSaveName", "tout");
names = ["speed_command","ambient_temperature_C", ...
    "initial_temperature_C","relative_humidity","solar_load_W", ...
    "cabin_temperature_setpoint_C","initial_soc", ...
    "vehicle_mass_kg","cooling_enable"];
values = {command, double(scenario.ambient_temperature_C), ...
    double(scenario.initial_temperature_C), ...
    double(scenario.relative_humidity), ...
    double(scenario.solar_load_W), ...
    double(scenario.cabin_temperature_setpoint_C), ...
    double(scenario.initial_soc), ...
    double(scenario.vehicle_mass_kg), ...
    double(scenario.cooling_enable)};
for index = 1:numel(names)
    simInput = simInput.setVariable(names(index), values{index});
end
if ~isReference, return; end

initialK = double(scenario.initial_temperature_C) + 273.15;
modelVars = {
    "cycle", cycle;
    "battery_T_init", initialK;
    "plate_T_init", initialK;
    "Emachine_T_init", initialK;
    "DCDC_T_init", initialK;
    "coolant_T_init", initialK;
    "cabin_T_init", initialK;
    "SOC_start", double(scenario.initial_soc);
    "vehMass", double(scenario.vehicle_mass_kg)
    };
for index = 1:size(modelVars, 1)
    simInput = simInput.setVariable(modelVars{index,1}, ...
        modelVars{index,2}, "Workspace", model);
end
simInput = localSetBatteryInitialTargets(simInput, model, ...
    double(scenario.initial_soc), initialK);
simInput = simInput.setBlockParameter( ...
    model + "/Scenario/Temperature [degC]", ...
    "Value", num2str(double(scenario.ambient_temperature_C), "%.15g"));
simInput = simInput.setBlockParameter( ...
    model + "/Scenario/Relative Humidity", ...
    "Value", num2str(double(scenario.relative_humidity), "%.15g"));
simInput = simInput.setBlockParameter( ...
    model + "/Scenario/AC On//Off", ...
    "Value", num2str(double(scenario.cooling_enable), "%.15g"));
simInput = simInput.setBlockParameter( ...
    model + "/Scenario/Sun Radiaton [W]", ...
    "Value", num2str(double(scenario.solar_load_W), "%.15g"));
simInput = simInput.setBlockParameter( ...
    model + "/Scenario/Temperature Setpoint [degC]", ...
    "Value", num2str(double(scenario.cabin_temperature_setpoint_C), "%.15g"));
set_param(model + "/Scenario", "popup", ...
    localThermalMode(double(scenario.ambient_temperature_C)));
set_param(model + "/Charger", "pop_charger", "No Charger");
end

function simInput = localSetBatteryInitialTargets(simInput, model, soc, temperatureK)
workspace = get_param(model, "ModelWorkspace");
for assemblyIndex = 1:4
    variable = "ModuleAssembly" + assemblyIndex;
    assembly = workspace.getVariable(variable);
    for moduleIndex = 1:2
        field = "Module" + moduleIndex;
        module = assembly.(field);
        module.socCell = soc;
        module.temperatureCell = temperatureK;
        if isfield(module, "socParallelAssembly")
            module.socParallelAssembly(:) = soc;
        end
        assembly.(field) = module;
    end
    simInput = simInput.setVariable(variable, assembly, ...
        "Workspace", model);
end
end

function mode = localThermalMode(ambientC)
if ambientC <= 10, mode = "Winter"; else, mode = "Summer"; end
end

function localValidateSimulationCoverage(simOut, duration)
actualTime = double(simOut.get("tout"));
actualTime = actualTime(:);
assert(~isempty(actualTime) && all(isfinite(actualTime)) && ...
    actualTime(end) >= duration - 0.5, ...
    "SimuVerity:F90:XBATT03:SimulationCoverage", ...
    "Simulation stopped before the required duration.");
end

function localAddReferenceTaps(model)
thermalManagement = model + "/Thermal" + newline + "Management";
spec = {
    model + "/Vehicle and Battery/From5", 1, "__F90_SpeedCmd", "f90_xbatt03_speed_cmd";
    model + "/Vehicle and Battery/From4", 1, "__F90_Speed", "f90_xbatt03_speed";
    model + "/Vehicle and Battery/From8", 1, "__F90_SOC", "f90_xbatt03_soc";
    model + "/Vehicle and Battery/From7", 1, "__F90_MotorTorque", "f90_xbatt03_motor_torque";
    thermalManagement + "/From2", 1, "__F90_Ambient", "f90_xbatt03_ambient";
    thermalManagement + "/From1", 1, "__F90_Cabin", "f90_xbatt03_cabin";
    thermalManagement + "/From19", 1, "__F90_BatteryTemp", "f90_xbatt03_batt_temp";
    thermalManagement + "/From21", 1, "__F90_PlateTemp", "f90_xbatt03_plate_temp";
    thermalManagement + "/From25", 1, "__F90_MotorTemp", "f90_xbatt03_motor_temp";
    model + "/Controls/From10", 1, "__F90_BattCoolIn", "f90_xbatt03_batt_cool_in";
    model + "/Controls/From16", 1, "__F90_MotorCoolOut", "f90_xbatt03_motor_cool_out";
    thermalManagement + "/From30", 1, "__F90_BattPump", "f90_xbatt03_batt_pump";
    thermalManagement + "/From29", 1, "__F90_MotorPump", "f90_xbatt03_motor_pump";
    thermalManagement + "/From28", 1, "__F90_Compressor", "f90_xbatt03_compressor";
    thermalManagement + "/From27", 1, "__F90_Fan", "f90_xbatt03_fan";
    thermalManagement + "/From31", 1, "__F90_Blower", "f90_xbatt03_blower";
    model + "/Heater/From", 1, "__F90_Heater", "f90_xbatt03_heater";
    model + "/Controls/Cabin Air Control", 2, "__F90_PTC", "f90_xbatt03_ptc";
    thermalManagement + "/From5", 1, "__F90_ChillerBypass", "f90_xbatt03_chiller_bypass";
    thermalManagement + "/From6", 1, "__F90_RadiatorBypass", "f90_xbatt03_radiator_bypass";
    thermalManagement + "/From4", 1, "__F90_SerialParallel", "f90_xbatt03_serial_parallel";
    thermalManagement + "/Add", 1, "__F90_BattHeat", "f90_xbatt03_batt_heat";
    thermalManagement + "/Add1", 1, "__F90_MotorHeat", "f90_xbatt03_motor_heat";
    thermalManagement + "/Add2", 1, "__F90_CondenserHeat", "f90_xbatt03_condenser_heat";
    thermalManagement + "/Add3", 1, "__F90_ChillerHeat", "f90_xbatt03_chiller_heat"
    };
for index = 1:size(spec, 1)
    localAddTap(spec{index,1}, spec{index,2}, ...
        spec{index,3}, spec{index,4}, index);
end
% Vehicle and Battery/From6 is charger current and is identically zero
% when the native scenario disables charging.  Measure the traction-battery
% current at the real series current sensor instead.
localAddPhysicalSignalTap( ...
    model + "/Battery/Lumped/Battery current1", 1, ...
    "__F90_BattCurrentPS", "__F90_BattCurrent", ...
    "f90_xbatt03_batt_current", size(spec, 1) + 1);
end

function localAddTap(source, port, name, variable, index)
parent = string(get_param(source, "Parent"));
destination = parent + "/" + name;
assert(getSimulinkBlockHandle(source) > 0, ...
    "SimuVerity:F90:XBATT03:SemanticLocator", ...
    "Required semantic source block is missing: %s", source);
add_block("simulink/Sinks/To Workspace", destination, ...
    "VariableName", variable, "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", "Decimation", "1", ...
    "Position", [3200 30*index 3340 30*index+20]);
sourcePorts = get_param(source, "PortHandles");
destinationPorts = get_param(destination, "PortHandles");
assert(numel(sourcePorts.Outport) >= port, ...
    "SimuVerity:F90:XBATT03:SemanticPort", ...
    "Required output port is missing at %s#out:%d.", source, port);
add_line(parent, sourcePorts.Outport(port), ...
    destinationPorts.Inport(1), "autorouting", "on");
end

function localAddPhysicalSignalTap(source, port, converterName, ...
        sinkName, variable, index)
parent = string(get_param(source, "Parent"));
converter = parent + "/" + converterName;
sink = parent + "/" + sinkName;
assert(getSimulinkBlockHandle(source) > 0, ...
    "SimuVerity:F90:XBATT03:SemanticLocator", ...
    "Required physical signal source block is missing: %s", source);
add_block("nesl_utility/PS-Simulink" + newline + "Converter", converter, ...
    "Position", [3050 30*index 3130 30*index+30]);
add_block("simulink/Sinks/To Workspace", sink, ...
    "VariableName", variable, "SaveFormat", "Timeseries", ...
    "MaxDataPoints", "inf", "Decimation", "1", ...
    "Position", [3200 30*index 3340 30*index+20]);
sourcePorts = get_param(source, "PortHandles");
converterPorts = get_param(converter, "PortHandles");
sinkPorts = get_param(sink, "PortHandles");
assert(numel(sourcePorts.RConn) >= port && ...
    ~isempty(converterPorts.LConn) && ~isempty(converterPorts.Outport), ...
    "SimuVerity:F90:XBATT03:SemanticPort", ...
    "Required physical signal port is missing at %s#rconn:%d.", ...
    source, port);
add_line(parent, sourcePorts.RConn(port), ...
    converterPorts.LConn(1), "autorouting", "on");
add_line(parent, converterPorts.Outport(1), ...
    sinkPorts.Inport(1), "autorouting", "on");
end

function outputs = localExtractOutputs(simOut, command, duration, isReference)
if ~isReference
    outputs = localExtractPublic(simOut);
    return;
end
grid = (0:0.5:duration).';
speedCommand = localSample(simOut, "f90_xbatt03_speed_cmd", grid);
vehicle = [
    speedCommand, ...
    localSample(simOut, "f90_xbatt03_speed", grid), ...
    localScalarSample(simOut, "f90_xbatt03_soc", grid, "minimum"), ...
    localScalarSample(simOut, "f90_xbatt03_batt_current", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_motor_torque", grid, "mean")];
temperatureC = [
    localScalarSample(simOut, "f90_xbatt03_ambient", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_cabin", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_batt_temp", grid, "maximum"), ...
    localScalarSample(simOut, "f90_xbatt03_plate_temp", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_motor_temp", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_batt_cool_in", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_motor_cool_out", grid, "mean")];
control = [
    localScalarSample(simOut, "f90_xbatt03_batt_pump", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_motor_pump", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_compressor", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_fan", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_blower", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_heater", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_ptc", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_chiller_bypass", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_radiator_bypass", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_serial_parallel", grid, "mean")];
heat = [
    localScalarSample(simOut, "f90_xbatt03_batt_heat", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_motor_heat", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_condenser_heat", grid, "mean"), ...
    localScalarSample(simOut, "f90_xbatt03_chiller_heat", grid, "mean")];
outputs = struct("time_s", grid, "vehicle_state", vehicle, ...
    "temperature_state", temperatureC, ...
    "thermal_control", control, "heat_flow_state", heat);
end

function outputs = localExtractPublic(simOut)
required = ["vehicle_state","temperature_state", ...
    "thermal_control","heat_flow_state"];
widths = [5, 7, 10, 4];
series = cell(size(required));
for index = 1:numel(required)
    series{index} = simuverity_public_output_compatibility( ...
        simOut,required(index),widths(index),AllowBaseWorkspace=true);
end
grid = double(series{1}.Time(:));
outputs = struct("time_s", grid, ...
    "vehicle_state", localTimeseriesData(series{1}), ...
    "temperature_state", localTimeseriesData(series{2}), ...
    "thermal_control", localTimeseriesData(series{3}), ...
    "heat_flow_state", localTimeseriesData(series{4}));
end

function values = localSample(simOut, variable, grid)
ts = localGet(simOut, variable);
data = localTimeseriesData(ts);
time = double(ts.Time(:));
[time, uniqueIndex] = unique(time, "stable");
data = data(uniqueIndex, :);
assert(~isempty(time), "SimuVerity:F90:XBATT03:EmptyLog", ...
    "Required Timeseries %s contains no samples.", variable);
if numel(time) == 1
    % Simulink may retain a single sample for a truly constant signal.
    % Treat that sample as constant over the requested evidence grid instead
    % of passing a degenerate grid to interp1.
    values = repmat(data(1, :), numel(grid), 1);
    return;
end
values = interp1(time, data, grid, "linear", "extrap");
end

function values = localScalarSample(simOut, variable, grid, reducer)
values = localSample(simOut, variable, grid);
switch reducer
    case "minimum", values = min(values, [], 2);
    case "maximum", values = max(values, [], 2);
    otherwise, values = mean(values, 2);
end
end

function ts = localGet(simOut, variable)
try
    ts = simOut.get(variable);
catch
    ts = [];
end
if isempty(ts)
    try, ts = evalin("base", variable); catch, end
end
assert(isa(ts, "timeseries"), "SimuVerity:F90:XBATT03:MissingLog", ...
    "Required Timeseries %s is missing.", variable);
end

function data = localTimeseriesData(ts)
data = squeeze(double(ts.Data));
if isvector(data), data = data(:); end
if size(data,1) ~= numel(ts.Time) && size(data,2) == numel(ts.Time)
    data = data.';
end
assert(size(data,1) == numel(ts.Time), ...
    "SimuVerity:F90:XBATT03:TimeseriesShape", ...
    "Timeseries data do not align with time.");
end

function localValidateOutputs(outputs, duration)
contracts = {
    "vehicle_state", 5;
    "temperature_state", 7;
    "thermal_control", 10;
    "heat_flow_state", 4
    };
time = double(outputs.time_s(:));
assert(numel(time) > 1024 && abs(time(1)) < 1e-9 && ...
    time(end) >= duration - 0.5 && all(diff(time) > 0), ...
    "SimuVerity:F90:XBATT03:TimeContract", ...
    "Evidence is truncated or has an invalid time base.");
for index = 1:size(contracts, 1)
    data = double(outputs.(contracts{index,1}));
    assert(isequal(size(data), [numel(time), contracts{index,2}]) && ...
        all(isfinite(data), "all"), ...
        "SimuVerity:F90:XBATT03:OutputContract", ...
        "Invalid output %s.", contracts{index,1});
end
end

function audit = localStaticAudit(model, isReference)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
physicalPorts = 0;
dynamicBlocks = 0;
for index = 1:numel(blocks)
    try
        ports = get_param(blocks(index), "PortHandles");
        physicalPorts = physicalPorts + numel(ports.LConn) + numel(ports.RConn);
    catch
    end
    kind = lower(localParam(blocks(index), "BlockType") + " " + ...
        localParam(blocks(index), "MaskType"));
    dynamicBlocks = dynamicBlocks + double(contains(kind, ...
        ["integrator","state-space","transfer fcn","delay","simscape"]));
end
audit = struct( ...
    "block_count", numel(blocks), ...
    "physical_conserving_port_count", physicalPorts, ...
    "dynamic_block_count", dynamicBlocks, ...
    "implementation_dynamics_gate", ...
        logical(physicalPorts >= 20 || dynamicBlocks >= 8), ...
    "reference_subject", logical(isReference), ...
    "name_based_agent_gate_used", false);
end

function value = localParam(block, name)
try, value = string(get_param(block, name)); catch, value = ""; end
end

function row = localEmptyScenario
row = struct("id","","class","","success",false, ...
    "output_file","","samples",0, ...
    "time_start_s",NaN,"time_end_s",NaN, ...
    "wall_clock_seconds",0,"started_at","","finished_at","", ...
    "error",struct);
end

function value = localRuntimeIdentity
value = struct( ...
    "matlab_release", string(version("-release")), ...
    "isolated_cache_configured", ...
        strlength(string(getenv("SIMULINK_CACHE_FOLDER"))) > 0, ...
    "isolated_codegen_configured", ...
        strlength(string(getenv("SIMULINK_CODEGEN_FOLDER"))) > 0);
end

function value = localError(ME)
value = struct("identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XBATT03:Write", "Cannot write %s.", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", jsonencode(value, "PrettyPrint", true));
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
