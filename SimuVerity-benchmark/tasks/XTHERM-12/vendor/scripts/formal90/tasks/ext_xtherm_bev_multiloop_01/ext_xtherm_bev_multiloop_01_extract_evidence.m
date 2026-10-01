function evidence = ext_xtherm_bev_multiloop_01_extract_evidence(modelPath,outDir,officialScenarios,evaluatorAssetRoot)
%EXT_XTHERM_BEV_MULTILOOP_01_EXTRACT_EVIDENCE Dual-role evidence runner.
% The exact current reference file binding is evaluated from a fresh complete-project
% copy and uses only existing measurement ports.  Every other model is a
% candidate and is observed only through the four public Timeseries.
% Scoring is intentionally absent from this MATLAB process.
arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end

taskId = "EXT-XTHERM-BEV-MULTILOOP-01";
referencePresence = "present";
sourcePresenceBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
spec = localOfficialSpec(taskId);
stopTime = double(spec.simulation.stop_time_s);
gridStep = double(spec.simulation.evidence_output_step_s);
assert(stopTime==30.0 && gridStep==0.1, ...
    "SimuVerity:EXT:BEVStaticContract", "Unexpected official time contract.");
if ~isfolder(outDir), mkdir(outDir); end

scriptFolder = fileparts(mfilename("fullpath"));
oldPath = path;
oldFolder = pwd;
pathCleanup = onCleanup(@()path(oldPath)); %#ok<NASGU>
folderCleanup = onCleanup(@()cd(oldFolder)); %#ok<NASGU>
baseSnapshot = localSnapshotBase();
baseCleanup = onCleanup(@()localRestoreBase(baseSnapshot)); %#ok<NASGU>
restoredefaultpath;
addpath(scriptFolder,"-begin");
localReloadCandidateDependencies(isReference);
localConfigureFileGeneration();

started = tic;
stage = struct("setup",false,"load",false,"update",false, ...
    "compile",false,"smoke",false);
timing = struct("setup_s",0,"load_s",0,"update_s",0, ...
    "compile_s",0,"smoke_s",0,"scenarios_s",0,"total_s",0);
runtimeModel = "";
runtimePresenceBefore = "";
loaded = false;
project = [];

try
    timer = tic;
    if isReference
        assert(isfolder(evaluatorAssetRoot),"SimuVerity:EXT:BEVReferenceAssetRoot","Evaluator-owned reference asset root is missing.");
        referenceRoot=evaluatorAssetRoot;
        runtimeRoot=string(tempname);
        assert(~isfolder(runtimeRoot),"SimuVerity:EXT:BEVFreshRuntime", ...
            "Reference runtime copy already exists: %s",runtimeRoot);
        [copied,message] = copyfile(referenceRoot,runtimeRoot);
        assert(copied,"SimuVerity:EXT:BEVRuntimeCopy","%s",message);
        runtimeCleanup=onCleanup(@()localRemoveRuntime(runtimeRoot)); %#ok<NASGU>
        runtimeModel = fullfile(runtimeRoot,"Models", ...
            "BEV_Thermal_Management.slx");
        runtimeProject = fullfile(runtimeRoot,"BEV_Thermal_Management.prj");
        assert(isfile(runtimeModel) && isfile(runtimeProject), ...
            "SimuVerity:EXT:BEVRuntimeClosure", "Fresh project copy is incomplete.");
        assert(strcmpi(localFilePresence(runtimeModel),referencePresence), ...
            "SimuVerity:EXT:BEVRuntimePresence", "Reference file binding changed during materialization.");
        cd(runtimeRoot);
        project = openProject(runtimeProject);
        projectCleanup = onCleanup(@()localCloseProject(project)); %#ok<NASGU>
        [~,model] = fileparts(runtimeModel);
        localCloseReferenceStartupAlias(model,runtimeModel,referencePresence);
    else
        runtimeModel = localCanonicalPath(modelPath);
        candidateRoot = fileparts(runtimeModel);
        cd(candidateRoot);
        addpath(genpath(candidateRoot),"-begin");
    end
    runtimePresenceBefore = localFilePresence(runtimeModel);
    timing.setup_s = toc(timer);
    stage.setup = true;

    [~,model] = fileparts(runtimeModel);
    timer = tic;
    load_system(runtimeModel);
    loaded = true;
    modelCleanup = onCleanup(@()localCloseModel(model)); %#ok<NASGU>
    localConfigureRuntime(model,isReference);
    timing.load_s = toc(timer);
    stage.load = true;

    firstScenario = spec.scenarios(1);
    localAssignPublicInputs(firstScenario,stopTime,gridStep);
    if isReference, localApplyReferenceScenario(model,firstScenario); end
    timer = tic;
    set_param(model,"SimulationCommand","update");
    timing.update_s = toc(timer);
    stage.update = true;

    timer = tic;
    feval(model,[],[],[],"compile");
    feval(model,[],[],[],"term");
    timing.compile_s = toc(timer);
    stage.compile = true;

    localClearPublicOutputs();
    timer = tic;
    smoke = sim(model,"StopTime","0.1","SimulationMode","normal", ...
        "SrcWorkspace","base","ReturnWorkspaceOutputs","on", ...
        "CaptureErrors","on");
    localAssertSimulationSuccess(smoke,"smoke");
    timing.smoke_s = toc(timer);
    stage.smoke = true;
catch exception
    timing.total_s = toc(started);
    evidence = localAssemble(taskId,modelPath,sourcePresenceBefore,isReference, ...
        runtimeModel,runtimePresenceBefore,"",false,stage,timing,struct([]),exception);
    localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
    if isReference, rethrow(exception); end
    return
end

items = cell(numel(spec.scenarios),1);
timer = tic;
suiteException = [];
for index = 1:numel(spec.scenarios)
    scenario = spec.scenarios(index);
    scenarioTimer = tic;
    localClearPublicOutputs();
    try
        localAssignPublicInputs(scenario,stopTime,gridStep);
        if isReference, localApplyReferenceScenario(model,scenario); end
        simulation = sim(model,"StopTime",num2str(stopTime,17), ...
            "SimulationMode","normal","SrcWorkspace","base", ...
            "ReturnWorkspaceOutputs","on","CaptureErrors","on");
        localAssertSimulationSuccess(simulation,string(scenario.id));
        if isReference
            logs = localReferenceLogs(simulation,model,stopTime,gridStep);
        else
            logs = localCandidateLogs(simulation,stopTime,gridStep);
        end
        item = localScenarioEvidence(scenario,logs,toc(scenarioTimer));
    catch exception
        item = localInvalidScenario(scenario,toc(scenarioTimer),exception);
        if isReference, suiteException = exception; end
    end
    items{index} = item;
    localWriteJsonAtomic(fullfile(outDir, ...
        "scenario_"+string(scenario.id)+".json"),item);
    if ~isempty(suiteException), break, end
end
items = items(~cellfun(@isempty,items));
scenarios = vertcat(items{:});
timing.scenarios_s = toc(timer);
timing.total_s = toc(started);
runtimePresenceAfter = localFilePresence(runtimeModel);
runtimeUnchanged = strcmpi(runtimePresenceBefore,runtimePresenceAfter);
evidence = localAssemble(taskId,modelPath,sourcePresenceBefore,isReference, ...
    runtimeModel,runtimePresenceBefore,runtimePresenceAfter,runtimeUnchanged, ...
    stage,timing,scenarios,suiteException);
localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
if ~isempty(suiteException), rethrow(suiteException); end
end

function localConfigureRuntime(model,isReference)
set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on", ...
    "LimitDataPoints","off");
toWorkspace = find_system(model,"LookUnderMasks","all", ...
    "FollowLinks","on","BlockType","ToWorkspace");
for index = 1:numel(toWorkspace)
    try, set_param(toWorkspace{index},"MaxDataPoints","inf"); catch, end
end
if ~isReference, return, end

% The published operating condition starts the cabin hot while the battery
% and liquid loops start below the source controller's 30--35 degC chiller
% override band.  Apply it only in the evaluator-owned, unsaved reference
% runtime copy; candidate models must implement the same public condition.
localApplyPublishedInitialConditions(model);

measurementPath = model+"/Thermal Management/Measurements";
assert(getSimulinkBlockHandle(measurementPath,true)~=-1, ...
    "SimuVerity:EXT:BEVNativeMeasurements", "Native Measurements subsystem is missing.");
ports = get_param(measurementPath,"PortHandles");
assert(numel(ports.Outport)==6,"SimuVerity:EXT:BEVNativeMeasurements", ...
    "Expected six native measurement outputs.");
set_param(model,"SignalLogging","on", ...
    "SignalLoggingName","bev_evaluator_native_logs");
names = ["vehicle","cabin","mode","heat_flow", ...
    "component_temperature","actuator"];
for index = 1:6
    set_param(ports.Outport(index),"DataLogging","on", ...
        "DataLoggingNameMode","Custom", ...
        "DataLoggingName","bev_native_"+names(index));
end

driveLogicPath = model+"/Scenario/Drive Cycle Logic";
required = [driveLogicPath, ...
    model+"/Scenario/Transfer Fcn3", ...
    model+"/Scenario/Driving Distance"];
for block = required
    assert(getSimulinkBlockHandle(block,true)~=-1, ...
        "SimuVerity:EXT:BEVNativeDrive", "Missing required native drive block %s.",block);
end
drivePorts = get_param(driveLogicPath,"PortHandles");
assert(~isempty(drivePorts.Outport),"SimuVerity:EXT:BEVNativeDrive", ...
    "Drive Cycle Logic has no speed-reference output.");
set_param(drivePorts.Outport(1),"DataLogging","on", ...
    "DataLoggingNameMode","Custom", ...
    "DataLoggingName","bev_native_speed_reference_input");
end

function localApplyPublishedInitialConditions(model)
workspace = get_param(model,"ModelWorkspace");
componentInitialDegC = 25.0;
assignin(workspace,"cabin_T_init",40.0);
assignin(workspace,"battery_T_init",componentInitialDegC);
assignin(workspace,"coolant_T_init",componentInitialDegC);
assignin(workspace,"plate_T_init",componentInitialDegC);

for assemblyIndex = 1:4
    variableName = "ModuleAssembly"+string(assemblyIndex);
    assembly = evalin(workspace,variableName);
    for moduleIndex = 1:2
        moduleName = "Module"+string(moduleIndex);
        assembly.(moduleName).temperatureCell = componentInitialDegC+273.15;
    end
    assignin(workspace,variableName,assembly);
end
coolingPlate = evalin(workspace,"CoolingPlateBottom");
coolingPlate.plateTemp_ini = componentInitialDegC+273.15;
assignin(workspace,"CoolingPlateBottom",coolingPlate);
end

function localApplyReferenceScenario(model,scenario)
mapping = { ...
    "Temperature [degC]",scenario.ambient_temperature_degC; ...
    "Relative Humidity",scenario.relative_humidity; ...
    "Temperature Setpoint [degC]",scenario.cabin_setpoint_degC; ...
    "Number of Occupants",scenario.occupant_count; ...
    "AC On//Off",scenario.ac_enable; ...
    "Recirculation On//Off",scenario.recirculation_enable; ...
    "Pressure [MPa]",0.101325; ...
    "CO2 Fraction",0.0004; ...
    "Driving Distance",700};
for index = 1:size(mapping,1)
    block = model+"/Scenario/"+string(mapping{index,1});
    assert(getSimulinkBlockHandle(block,true)~=-1, ...
        "SimuVerity:EXT:BEVNativeScenario", "Missing source scenario block %s.",block);
    set_param(block,"Value",num2str(double(mapping{index,2}),17));
end
end

function localAssignPublicInputs(scenario,stopTime,gridStep)
time = (0:gridStep:stopTime).';
speed = min(1.62*time,50.0);
assignin("base","bev_drive_command",timeseries(speed,time));
command = struct( ...
    "ambient_temperature_degC",double(scenario.ambient_temperature_degC), ...
    "relative_humidity",double(scenario.relative_humidity), ...
    "cabin_setpoint_degC",double(scenario.cabin_setpoint_degC), ...
    "occupant_count",double(scenario.occupant_count), ...
    "ac_enable",double(scenario.ac_enable), ...
    "recirculation_enable",double(scenario.recirculation_enable));
assignin("base","bev_thermal_command",command);
end

function logs = localReferenceLogs(simulation,model,stopTime,gridStep)
dataset = [];
try, dataset = simulation.get("bev_evaluator_native_logs"); catch, end
assert(isa(dataset,"Simulink.SimulationData.Dataset"), ...
    "SimuVerity:EXT:BEVNativeDataset", "Native evaluator signal log is missing.");
grid = (0:gridStep:stopTime).';
nativeVehicle = localNativeDatasetAt(dataset,"bev_native_vehicle",2,grid);
speedReference = localNativeDatasetAt(dataset, ...
    "bev_native_speed_reference_input",1,grid);
vehicle = [speedReference nativeVehicle(:,2)];
cabin = localNativeDatasetAt(dataset,"bev_native_cabin",3,grid);
heat = localNativeDatasetAt(dataset,"bev_native_heat_flow",6,grid);
component = localNativeDatasetAt(dataset, ...
    "bev_native_component_temperature",3,grid);
actuator = localNativeDatasetAt(dataset,"bev_native_actuator",5,grid);
logs = struct( ...
    "time_s",grid, ...
    "bev_vehicle_response",vehicle, ...
    "bev_temperature_response",[cabin component], ...
    "bev_heat_flow_response",heat, ...
    "bev_actuator_response",actuator, ...
    "availability",struct( ...
        "bev_vehicle_response",true, ...
        "bev_temperature_response",true, ...
        "bev_heat_flow_response",true, ...
        "bev_actuator_response",true), ...
    "failure_reasons",struct( ...
        "bev_vehicle_response","", ...
        "bev_temperature_response","", ...
        "bev_heat_flow_response","", ...
        "bev_actuator_response",""), ...
    "adapter_detail", ...
        "current_native_measurement_ports_plus_prefilter_speed_tap_resampled_0p1s", ...
    "source_model",model);
end

function values = localNativeDatasetAt(dataset,name,width,grid)
element = dataset.get(name);
assert(~isempty(element),"SimuVerity:EXT:BEVNativeSignal", ...
    "Missing native signal %s.",name);
value = element;
if isa(element,"Simulink.SimulationData.Signal"), value = element.Values; end
[time,data,ok,reason] = localTimeseriesMatrix(value,width);
assert(ok,"SimuVerity:EXT:BEVNativeSignal","Invalid native signal %s: %s",name,reason);
assert(time(1)<=1e-8 && time(end)>=grid(end)-1e-6, ...
    "SimuVerity:EXT:BEVNativeCoverage", "Native signal %s lacks 0--30 s coverage.",name);
values = interp1(time,data,grid,"linear");
assert(all(isfinite(values),"all"),"SimuVerity:EXT:BEVNativeResample", ...
    "Native signal %s is nonfinite after resampling.",name);
end

function logs = localCandidateLogs(simulation,stopTime,gridStep)
grid = (0:gridStep:stopTime).';
names = ["bev_vehicle_response","bev_temperature_response", ...
    "bev_heat_flow_response","bev_actuator_response"];
widths = [2 6 6 5];
logs = struct("time_s",grid,"adapter_detail", ...
    "candidate_public_timeseries_only_resampled_0p1s");
for index = 1:numel(names)
    [matrix,available,reason] = localOptionalPublic( ...
        simulation,names(index),widths(index),grid,stopTime,gridStep);
    logs.(names(index)) = matrix;
    logs.availability.(names(index)) = available;
    logs.failure_reasons.(names(index)) = reason;
end
end

function [matrix,available,reason] = localOptionalPublic( ...
    simulation,name,width,grid,stopTime,maximumGap)
matrix = [];
available = false;
reason = "missing_public_timeseries";
value = localResolvePublicValue(simulation,name);
if isempty(value), return, end
[time,data,ok,reason] = localTimeseriesMatrix(value,width);
if ~ok, return, end
if abs(time(1))>1e-8 || time(end)<stopTime-1e-6
    reason = "incomplete_0_to_30_second_coverage";
    return
end
if max(diff(time))>maximumGap+1e-9
    reason = "public_sample_gap_exceeds_0p1_seconds";
    return
end
matrix = interp1(time,data,grid,"linear");
if ~all(isfinite(matrix),"all")
    matrix = [];
    reason = "nonfinite_after_public_resampling";
    return
end
available = true;
reason = "";
end

function value = localResolvePublicValue(simulation,name)
value = [];
try, value = simulation.get(name); catch, end
if isempty(value) && evalin("base","exist('"+name+"','var')~=0")
    value = evalin("base",name);
end
if isempty(value)
    for containerName = ["logsout","yout"]
        container = [];
        try, container = simulation.get(containerName); catch, end
        value = localDatasetElement(container,name);
        if ~isempty(value), break, end
    end
end
if isa(value,"Simulink.SimulationData.Signal"), value = value.Values; end
end

function value = localDatasetElement(container,name)
value = [];
if ~isa(container,"Simulink.SimulationData.Dataset"), return, end
try, value = container.get(name); catch, end
if isa(value,"Simulink.SimulationData.Signal"), value = value.Values; end
end

function [time,data,ok,reason] = localTimeseriesMatrix(value,width)
time = [];
data = [];
ok = false;
reason = "not_a_timeseries";
if ~isa(value,"timeseries"), return, end
try
    time = double(value.Time(:));
    data = squeeze(double(value.Data));
catch
    reason = "timeseries_conversion_failed";
    return
end
if isvector(data) && width==1, data = data(:); end
if size(data,1)~=numel(time) && size(data,2)==numel(time), data = data.'; end
if size(data,1)~=numel(time) || size(data,2)~=width
    reason = "wrong_public_channel_width";
    return
end
if numel(time)<2 || ~all(isfinite(time)) || ...
        ~all(isfinite(data),"all") || ~all(diff(time)>0)
    reason = "nonfinite_or_nonincreasing_timeseries";
    return
end
ok = true;
reason = "";
end

function item = localScenarioEvidence(scenario,logs,wallSeconds)
input = localScenarioInput(scenario);
available = logs.availability;
valid = all([available.bev_vehicle_response, ...
    available.bev_temperature_response, ...
    available.bev_heat_flow_response, ...
    available.bev_actuator_response]);
item = struct( ...
    "id",string(scenario.id), ...
    "valid",valid, ...
    "simulation_valid",true, ...
    "wall_seconds",wallSeconds, ...
    "input",input, ...
    "time_s",double(logs.time_s(:)), ...
    "bev_vehicle_response",double(logs.bev_vehicle_response), ...
    "bev_temperature_response",double(logs.bev_temperature_response), ...
    "bev_heat_flow_response",double(logs.bev_heat_flow_response), ...
    "bev_actuator_response",double(logs.bev_actuator_response), ...
    "container_availability",available, ...
    "container_failure_reasons",logs.failure_reasons, ...
    "adapter_detail",string(logs.adapter_detail), ...
    "failure_identifier","", ...
    "failure_message","");
end

function item = localInvalidScenario(scenario,wallSeconds,exception)
item = struct( ...
    "id",string(scenario.id), ...
    "valid",false, ...
    "simulation_valid",false, ...
    "wall_seconds",wallSeconds, ...
    "input",localScenarioInput(scenario), ...
    "time_s",[], ...
    "bev_vehicle_response",[], ...
    "bev_temperature_response",[], ...
    "bev_heat_flow_response",[], ...
    "bev_actuator_response",[], ...
    "container_availability",struct( ...
        "bev_vehicle_response",false, ...
        "bev_temperature_response",false, ...
        "bev_heat_flow_response",false, ...
        "bev_actuator_response",false), ...
    "container_failure_reasons",struct( ...
        "bev_vehicle_response","simulation_failed", ...
        "bev_temperature_response","simulation_failed", ...
        "bev_heat_flow_response","simulation_failed", ...
        "bev_actuator_response","simulation_failed"), ...
    "adapter_detail","simulation_failed_before_public_resolution", ...
    "failure_identifier",string(exception.identifier), ...
    "failure_message",string(exception.message));
end

function input = localScenarioInput(scenario)
input = struct( ...
    "ambient_temperature_degC",double(scenario.ambient_temperature_degC), ...
    "relative_humidity",double(scenario.relative_humidity), ...
    "cabin_setpoint_degC",double(scenario.cabin_setpoint_degC), ...
    "occupant_count",double(scenario.occupant_count), ...
    "ac_enable",double(scenario.ac_enable), ...
    "recirculation_enable",double(scenario.recirculation_enable));
end

function evidence = localAssemble(taskId,modelPath,sourcePresenceBefore,isReference, ...
    runtimeModel,runtimePresenceBefore,runtimePresenceAfter,runtimeUnchanged, ...
    stage,timing,scenarios,exception)
sourcePresenceAfter = localFilePresence(modelPath);
sourceUnchanged = strcmpi(sourcePresenceBefore,sourcePresenceAfter);
simulationValid = ~isempty(scenarios) && all([scenarios.simulation_valid]);
outputsComplete = ~isempty(scenarios) && all([scenarios.valid]);
stagePass = all([stage.setup stage.load stage.update stage.compile stage.smoke]);
evidence = struct( ...
    "schema","simuverity.ext-xtherm-bev-multiloop-evidence.v1", ...
    "task_id",taskId, ...
    "scoring_run_id",string(getenv("SIMUVERITY_SCORING_RUN_ID")), ...
    "timestamp_utc",char(datetime("now","TimeZone","UTC", ...
        "Format","yyyy-MM-dd'T'HH:mm:ss.SSSXXX")), ...
    "source_model_path",modelPath, ...
    "source_model_file_presence_before",sourcePresenceBefore, ...
    "source_model_file_presence_after",sourcePresenceAfter, ...
    "source_model_unchanged",sourceUnchanged, ...
    "runtime_model_path",runtimeModel, ...
    "runtime_model_file_presence_before",runtimePresenceBefore, ...
    "runtime_model_file_presence_after",runtimePresenceAfter, ...
    "runtime_model_unchanged",runtimeUnchanged, ...
    "adapter_role",localTernary(isReference, ...
        "reference_native_measurement_ports", ...
        "candidate_public_timeseries_only"), ...
    "reference_native_locator_used",isReference, ...
    "candidate_contract_only",~isReference, ...
    "public_input_names",["bev_drive_command","bev_thermal_command"], ...
    "public_output_names",["bev_vehicle_response", ...
        "bev_temperature_response","bev_heat_flow_response", ...
        "bev_actuator_response"], ...
    "reference_drive_binding",localTernary(isReference, ...
        "current_native_0p45_mps2_drive_cycle_equals_published_1p62_kphps_profile_before_native_smoothing", ...
        "public_bev_drive_command_timeseries"), ...
    "evidence_grid_step_s",0.1, ...
    "stages",stage, ...
    "timings",timing, ...
    "scenario_count",numel(scenarios), ...
    "scenarios",scenarios, ...
    "all_official_simulations_valid",simulationValid, ...
    "required_outputs_complete",outputsComplete, ...
    "partial_output_policy", ...
        "missing public container is preserved as empty and zeros only dependent offline metrics", ...
    "contains_score_decisions",false, ...
    "evaluator_runtime_change_manifest",struct( ...
        "saved_file_changes",false, ...
        "reference_complete_project_runtime_copy",isReference, ...
        "reference_existing_measurement_port_logging",isReference, ...
        "reference_prefilter_speed_reference_tap",isReference, ...
        "published_initial_condition_override_in_memory",isReference, ...
        "published_cabin_initial_temperature_degC",40.0, ...
        "published_battery_coolant_plate_initial_temperature_degC",25.0, ...
        "in_memory_limit_data_points_disabled",true, ...
        "in_memory_to_workspace_max_data_points_inf",true, ...
        "fixed_grid_resampling_only_after_source_validation",true), ...
    "EVIDENCE_COMPLETE",stagePass && simulationValid && ...
        sourceUnchanged && runtimeUnchanged);
if ~isempty(exception)
    evidence.failure_identifier = string(exception.identifier);
    evidence.failure_message = string(exception.message);
    evidence.failure_report = string(getReport(exception, ...
        "extended","hyperlinks","off"));
end
end

function localAssertSimulationSuccess(simulation,label)
message = "";
try, message = string(simulation.ErrorMessage); catch, end
assert(strlength(message)==0,"SimuVerity:EXT:BEVSimulation", ...
    "Simulation %s failed: %s",label,message);
end

function localConfigureFileGeneration()
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache)>0 && strlength(codegen)>0, ...
    "SimuVerity:EXT:BEVIsolation", "Missing isolated file-generation paths.");
if ~isfolder(cache), mkdir(cache); end
if ~isfolder(codegen), mkdir(codegen); end
Simulink.fileGenControl("set","CacheFolder",cache, ...
    "CodeGenFolder",codegen,"createDir",true);
end

function spec = localOfficialSpec(taskId)
root = fileparts(mfilename("fullpath"));
for level = 1:4, root = fileparts(root); end
spec = jsondecode(fileread(simuverity_official_scenarios_path()));
end

function localClearPublicOutputs()
names = ["bev_vehicle_response","bev_temperature_response", ...
    "bev_heat_flow_response","bev_actuator_response"];
for name = names
    evalin("base","if exist('"+name+"','var'),clear('"+name+"');end");
end
end

function snapshot = localSnapshotBase()
snapshot = evalin("base","whos");
end

function localRestoreBase(snapshot)
before = string({snapshot.name});
after = string(evalin("base","who"));
created = setdiff(after,before);
for index = 1:numel(created)
    evalin("base","clear('"+created(index)+"')");
end
end

function localCloseModel(model)
try, if bdIsLoaded(model), close_system(model,0); end, catch, end
end

function localCloseProject(project)
try, if ~isempty(project), close(project); end, catch, end
end

function localRemoveRuntime(runtimeRoot)
try
    if strlength(runtimeRoot)>0 && isfolder(runtimeRoot), rmdir(runtimeRoot,"s"); end
catch
end
end

function localCloseReferenceStartupAlias(model,runtimeModel,referencePresence)
if ~bdIsLoaded(model), return, end
loadedPath = string(get_param(model,"FileName"));
assert(isfile(loadedPath) && strcmpi(localFilePresence(loadedPath),referencePresence) && ...
    ~strcmpi(localCanonicalPath(loadedPath),localCanonicalPath(runtimeModel)), ...
    "SimuVerity:EXT:BEVStartupAliasIdentity", ...
    "Project startup loaded an unexpected BEV_Thermal_Management alias.");
close_system(model,0);
assert(~bdIsLoaded(model), "SimuVerity:EXT:BEVStartupAliasClose", ...
    "Unable to close the project-startup BEV_Thermal_Management alias.");
end

function pathName = localCanonicalPath(pathName)
pathName = string(char(java.io.File(char(pathName)).getCanonicalPath()));
end

function binding = localFilePresence(pathName)
assert(isfile(pathName), "SimuVerity:FileMissing", "Required file is missing: %s", pathName);
binding = "present";
end

function localWriteJsonAtomic(pathName,value)
folder = fileparts(pathName);
if ~isfolder(folder), mkdir(folder); end
temporary = pathName+".tmp."+string(char(java.util.UUID.randomUUID));
fid = fopen(temporary,"w","n","UTF-8");
assert(fid>=0,"SimuVerity:EXT:BEVJsonWrite","Cannot write %s.",temporary);
cleanup = onCleanup(@()localSafeFclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(value,"PrettyPrint",true));
fclose(fid);
clear cleanup
[moved,message] = movefile(temporary,pathName,"f");
assert(moved,"SimuVerity:EXT:BEVJsonMove","%s",message);
end

function localSafeFclose(fid)
try, fclose(fid); catch, end
end

function value = localTernary(condition,yesValue,noValue)
if condition, value = yesValue; else, value = noValue; end
end

function localReloadCandidateDependencies(isReference)
if isReference, return, end
helperRoot = string(getenv("SIMUVERITY_CANDIDATE_CLOSURE_HELPER_ROOT"));
assert(strlength(helperRoot)>0 && isfolder(helperRoot), ...
    "SimuVerity:EXT:BEVDependencyHelper", ...
    "Evaluator-owned candidate dependency helper root is unavailable.");
addpath(helperRoot,"-begin");
loaded = unified_reload_candidate_dependencies();
assert(string(loaded.status)=="LOADED_BEFORE_PUBLIC_INPUTS", ...
    "SimuVerity:EXT:BEVDependencyReload", ...
    "Verified candidate dependencies were not reloaded before official inputs.");
end
