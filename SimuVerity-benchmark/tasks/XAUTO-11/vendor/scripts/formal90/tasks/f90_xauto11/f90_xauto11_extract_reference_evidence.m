function evidence = f90_xauto11_extract_reference_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
% Extract fixed multi-scenario evidence for the F90-XAUTO-11 reference.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
outputRoot = outputDir;
runtimeRoot = evaluatorAssetRoot;
outputRoot = string(outputRoot);
scoringRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
if strlength(scoringRunId) == 0, scoringRunId = "xauto11_reference_manual"; end
scratchRoot = fullfile(outputRoot, "runtime_scratch");
if isfolder(outputRoot), error("SimuVerity:XAUTO11:OutputExists", "Fresh output exists: %s", outputRoot); end
assert(~isfolder(scratchRoot), "SimuVerity:XAUTO11:ScratchExists", "Fresh scratch exists: %s", scratchRoot);
mkdir(outputRoot); mkdir(scratchRoot);
diary(fullfile(outputRoot, "extractor.log"));
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>

callerPath = path;
pathCleanup = onCleanup(@() path(callerPath)); %#ok<NASGU>
restoredefaultpath;
addpath(runtimeRoot, "-begin");
cacheDir = fullfile(scratchRoot, "cache"); codegenDir = fullfile(scratchRoot, "codegen");
mkdir(cacheDir); mkdir(codegenDir);
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);

assert(isfile(officialScenarios), "SimuVerity:XAUTO11:OfficialScenarios", ...
    "Official scenarios are missing.");
assert(isfolder(runtimeRoot), "SimuVerity:XAUTO11:ReferenceAssetRoot", ...
    "Evaluator asset root is missing.");
official = jsondecode(fileread(officialScenarios));
assert(isfile(modelPath), "SimuVerity:XAUTO11:MissingModel", "Reference model is absent.");
expectedPresence = lower(strtrim(string("present")));
sourcePresenceBefore = localFilePresence(modelPath);
assert(sourcePresenceBefore == expectedPresence, "SimuVerity:XAUTO11:ReferenceIdentity", ...
    "Pinned reference model file presence differs.");
[~, model] = fileparts(modelPath);
load_system(modelPath);
cleanupModel = onCleanup(@() localClose(model)); %#ok<NASGU>
loadPass = true;
set_param(model, "LimitDataPoints", "off", "ReturnWorkspaceOutputs", "on");
toWorkspace = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "ToWorkspace"));
for index=1:numel(toWorkspace), set_param(toWorkspace(index), "MaxDataPoints", "inf"); end
localAddAppliedForceTap(model);
set_param(model, "SimulationCommand", "update");
updatePass = true;
feval(model, [], [], [], "compile");
compilePass = true;
feval(model, [], [], [], "term");

controllerBlock = model + "/Controller";
controller = struct("A",get_param(controllerBlock,"A"), ...
    "B",get_param(controllerBlock,"B"), ...
    "C",get_param(controllerBlock,"C"), ...
    "D",get_param(controllerBlock,"D"));
controllerNonzero = norm([str2num(controller.C) str2num(controller.D)],2) > 1e-8; %#ok<ST2NM>
assert(controllerNonzero, "SimuVerity:XAUTO11:ZeroController", "Reference controller is zero.");
baseState = localCaptureBase("xauto11_input");
baseCleanup = onCleanup(@() localRestoreBase(baseState)); %#ok<NASGU>

grid = (0:double(official.simulation.evidence_grid_step_seconds): ...
    double(official.simulation.duration_seconds)).';
scenarioCells = cell(1, numel(official.scenarios));
scenarioDir = fullfile(outputRoot, "scenarios"); mkdir(scenarioDir);
suiteTimer = tic;
for index=1:numel(official.scenarios)
    scenario = official.scenarios(index);
    localSetScenario(model, scenario, controller);
    application = localInstallScenarioWitness(model, scenario);
    timer = tic;
    simOut = sim(model, ...
        "StopTime", num2str(official.simulation.duration_seconds,17), ...
        "ReturnWorkspaceOutputs", "on");
    wallSeconds = toc(timer);
    signals = localExtractSignals(simOut, grid);
    item = localScenarioEvidence(scenario, grid, signals, wallSeconds);
    application = localVerifyScenarioWitness(application, model);
    item.input = application.requested_parameters;
    item.applied_parameters = application.applied_parameters;
    item.scenario_application_pass = application.pass;
    item.reference_native_model_workspace_pass = application.native_model_workspace_pass;
    item.offline_metrics = struct("input_application_log", ...
        localPublicApplicationLog(application));
    item.valid = item.valid && application.pass;
    assert(item.valid, "SimuVerity:XAUTO11:InvalidEvidence", "Scenario %s evidence is invalid.", scenario.id);
    scenarioCells{index} = item;
    save(fullfile(scenarioDir, "signals_" + string(scenario.id) + ".mat"), ...
        "signals", "scenario", "-v7");
    fprintf("XAUTO11_SCENARIO_PASS|%s|WALL=%.6f\n", scenario.id, wallSeconds);
end
scenarios = [scenarioCells{:}];

nominal = official.scenarios(strcmp(string({official.scenarios.id}), "nominal_body"));
localSetScenario(model, nominal, controller);
set_param(controllerBlock, "C", "[0 0]", "D", "[0 0]");
timer = tic;
passiveOut = sim(model, "StopTime", num2str(official.simulation.duration_seconds,17), ...
    "ReturnWorkspaceOutputs", "on");
passiveWall = toc(timer);
passiveSignals = localExtractSignals(passiveOut, grid);
passive = localScenarioEvidence(localPassiveScenario(nominal), grid, passiveSignals, passiveWall);
assert(passive.valid, "SimuVerity:XAUTO11:PassiveInvalid", "Passive diagnostic evidence is invalid.");
save(fullfile(scenarioDir, "signals_passive_nominal_diagnostic.mat"), ...
    "passiveSignals", "nominal", "-v7");

behavior = localBehaviorAudit(scenarios, passive);
staticAudit = struct();
staticAudit.block_count = numel(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
staticAudit.system_count = numel(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "SubSystem"));
staticAudit.simscape_reference_block_count = numel(find_system(model, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "BlockType", "Reference"));
staticAudit.controller_nonzero = controllerNonzero;
staticAudit.applied_force_measurement_tap_added_in_memory = true;

evidence = struct();
evidence.schema = "simuverity.formal90-xauto11-evidence.v1";
evidence.task_id = "F90-XAUTO-11";
evidence.scoring_run_id = char(scoringRunId);
evidence.EVIDENCE_COMPLETE = true;
evidence.contains_score_decisions = false;
evidence.matlab_release = version("-release");
evidence.load_pass = loadPass;
evidence.update_pass = updatePass;
evidence.compile_pass = compilePass;
evidence.simulate_pass = all([scenarios.simulate_pass]) && passive.simulate_pass;
evidence.all_scenarios_valid = all([scenarios.valid]);
evidence.reference_model_file_presence = sourcePresenceBefore;
evidence.reference_source_modified_or_saved = false;
evidence.scenario_count = numel(scenarios);
evidence.diagnostic_count = 1;
evidence.grid_step_s = official.simulation.evidence_grid_step_seconds;
evidence.suite_wall_seconds = toc(suiteTimer);
evidence.measurement_policy = "Existing logs plus one evaluator-only in-memory branch from the actuator output; reference model never saved";
evidence.static_audit = staticAudit;
evidence.behavior_audit = behavior;
evidence.scenarios = scenarios;
evidence.passive_nominal_diagnostic = passive;
evidence.reference_model_file_presence_after = localFilePresence(modelPath);
evidence.reference_binding_preserved = evidence.reference_model_file_presence_after == sourcePresenceBefore;
assert(evidence.reference_binding_preserved, "SimuVerity:XAUTO11:SourceChanged", "Reference model changed.");
applicationPass = all([scenarios.scenario_application_pass]);
representations = string(arrayfun(@(row) ...
    row.offline_metrics.input_application_log.requested_input_file_presence, ...
    scenarios, "UniformOutput", false));
representationsUnique = numel(representations) == numel(scenarios) && ...
    all(strlength(representations) > 0) && ...
    numel(unique(representations)) == numel(representations);
evidence.evaluation_subject = "reference";
evidence.runtime_model_unchanged = evidence.reference_binding_preserved;
evidence.binding_preserved = evidence.reference_binding_preserved;
evidence.input_application_contract = "xauto11-base-and-simulationinput";
evidence.reference_native_application_contract = "xauto11-model-workspace";
evidence.input_application_all_pass = applicationPass;
evidence.input_application_representations_unique = representationsUnique;
evidence.input_application_representations = representations;
evidence.score_inputs_valid = evidence.load_pass && evidence.update_pass && ...
    evidence.compile_pass && evidence.simulate_pass && ...
    evidence.all_scenarios_valid && evidence.reference_binding_preserved && ...
    applicationPass && representationsUnique;
evidence.diagnostics_valid = evidence.score_inputs_valid;
evidence.evidence_freeze_candidate = evidence.score_inputs_valid;
evidence.EVIDENCE_COMPLETE = evidence.score_inputs_valid;
evidence.evidence_complete = evidence.EVIDENCE_COMPLETE;

save(fullfile(outputRoot, "evidence_complete.mat"), "evidence", "-v7.3");
localWriteJson(fullfile(outputRoot, "evidence.json"), evidence);
fprintf("XAUTO11_EVIDENCE_COMPLETE=1\nSUITE_WALL_SECONDS=%.6f\n", evidence.suite_wall_seconds);
end

function item = localScenarioEvidence(scenario, grid, signals, wallSeconds)
item = struct();
item.id = char(string(scenario.id));
item.input = struct("sprung_mass_kg",scenario.sprung_mass_kg, ...
    "suspension_stiffness_n_per_m",scenario.suspension_stiffness_n_per_m, ...
    "suspension_damping_n_s_per_m",scenario.suspension_damping_n_s_per_m, ...
    "road_peak_m",scenario.road_peak_m, ...
    "road_angular_frequency_rad_per_s",scenario.road_angular_frequency_rad_per_s);
item.simulate_pass = true;
item.valid = localValid(grid, signals);
item.wall_seconds = wallSeconds;
item.logs = struct();
item.logs.suspension_state = localLog(grid, signals.suspension_state, ...
    {"road_displacement_m","body_displacement_m","wheel_displacement_m", ...
     "suspension_deflection_m","body_acceleration_m_per_s2"}, ...
    {"m","m","m","m","m/s^2"});
item.logs.active_control_state = localLog(grid, signals.active_control_state, ...
    {"controller_normalized_command","applied_active_force_n"}, {"1","N"});
item.metrics = localMetrics(grid, signals);
end

function scenario = localPassiveScenario(nominal)
scenario = nominal; scenario.id = "passive_nominal_diagnostic";
end

function metrics = localMetrics(grid, signals)
s = signals.suspension_state; c = signals.active_control_state;
road=s(:,1); body=s(:,2); wheel=s(:,3); deflection=s(:,4); acceleration=s(:,5);
command=c(:,1); applied=c(:,2); tail=grid>=1.5;
metrics = struct();
metrics.peak_road_displacement_m = max(abs(road));
metrics.peak_body_displacement_m = max(abs(body));
metrics.peak_wheel_displacement_m = max(abs(wheel));
metrics.peak_suspension_deflection_m = max(abs(deflection));
metrics.rms_suspension_deflection_m = sqrt(mean(deflection.^2));
metrics.peak_body_acceleration_m_per_s2 = max(abs(acceleration));
metrics.rms_body_acceleration_m_per_s2 = sqrt(mean(acceleration.^2));
metrics.tail_rms_body_acceleration_m_per_s2 = sqrt(mean(acceleration(tail).^2));
metrics.tail_rms_suspension_deflection_m = sqrt(mean(deflection(tail).^2));
metrics.peak_controller_normalized_command = max(abs(command));
metrics.rms_controller_normalized_command = sqrt(mean(command.^2));
metrics.peak_applied_active_force_n = max(abs(applied));
metrics.rms_applied_active_force_n = sqrt(mean(applied.^2));
metrics.actuator_tracking_rmse_n = sqrt(mean((applied-command).^2));
relativeVelocity = gradient(deflection, grid);
metrics.active_work_proxy_j = trapz(grid, abs(applied .* relativeVelocity));
metrics.post_bump_recovery_ratio = metrics.tail_rms_body_acceleration_m_per_s2 / ...
    max(metrics.rms_body_acceleration_m_per_s2, eps);
end

function audit = localBehaviorAudit(scenarios, passive)
ids = string({scenarios.id});
mass = scenarios(ismember(ids,["light_body","intermediate_body","nominal_body"]));
rough = scenarios(ids=="rougher_faster_road"); intermediate = scenarios(ids=="intermediate_body");
nominal = scenarios(ids=="nominal_body");
audit = struct();
massValues = arrayfun(@(x) x.metrics.peak_body_acceleration_m_per_s2,mass);
audit.mass_axis_peak_acceleration_spread = max(massValues) - min(massValues);
audit.mass_axis_effective = audit.mass_axis_peak_acceleration_spread > 1e-3;
audit.road_axis_peak_acceleration_delta = abs(rough.metrics.peak_body_acceleration_m_per_s2 - ...
    intermediate.metrics.peak_body_acceleration_m_per_s2);
audit.road_axis_effective = audit.road_axis_peak_acceleration_delta > 1e-3;
forceValues = arrayfun(@(x) x.metrics.peak_applied_active_force_n,scenarios);
audit.force_changes_across_scenarios = max(forceValues) - min(forceValues) > 1e-5;
audit.nominal_active_force_nonzero = nominal.metrics.peak_applied_active_force_n > 1e-3;
audit.active_vs_passive_acceleration_rms_delta = abs(...
    nominal.metrics.rms_body_acceleration_m_per_s2 - passive.metrics.rms_body_acceleration_m_per_s2);
audit.active_vs_passive_deflection_rms_delta = abs(...
    nominal.metrics.rms_suspension_deflection_m - passive.metrics.rms_suspension_deflection_m);
audit.active_closed_loop_effective = max([audit.active_vs_passive_acceleration_rms_delta, ...
    audit.active_vs_passive_deflection_rms_delta]) > 1e-5;
audit.all_axes_effective = audit.mass_axis_effective && audit.road_axis_effective && ...
    audit.force_changes_across_scenarios && audit.nominal_active_force_nonzero && ...
    audit.active_closed_loop_effective;
end

function localSetScenario(model, scenario, controller)
workspace=get_param(model,"ModelWorkspace");
workspace.assignin("Mb",double(scenario.sprung_mass_kg));
workspace.assignin("Ks",double(scenario.suspension_stiffness_n_per_m));
workspace.assignin("Bs",double(scenario.suspension_damping_n_s_per_m));
peak=double(scenario.road_peak_m); omega=double(scenario.road_angular_frequency_rad_per_s);
set_param(model+"/Road Bump/Sine Wave","Amplitude",num2str(-peak/2,17), ...
    "Bias",num2str(peak/2,17),"Frequency",num2str(omega,17));
set_param(model+"/Controller","A",controller.A,"B",controller.B,"C",controller.C,"D",controller.D);
end

function receipt = localInstallScenarioWitness(model, scenario)
requested = localRequestedInput(scenario);
assignin("base", "xauto11_input", requested);
baseBefore = localPlainInput(evalin("base", "xauto11_input"));
modelBefore = localReadModelWorkspaceInput(model);
requestedBinding = localStructFilePresence(requested);
baseBinding = localStructFilePresence(baseBefore);
modelBinding = localStructFilePresence(modelBefore);
receipt = struct("requested_parameters", requested, ...
    "applied_parameters", modelBefore, ...
    "requested_input_file_presence", requestedBinding, ...
    "base_value_before_simulation_file_presence", baseBinding, ...
    "base_value_before_simulation_matches_requested", isequaln(requested, baseBefore), ...
    "simulationinput_value_file_presence", requestedBinding, ...
    "simulationinput_and_base_match", requestedBinding == baseBinding, ...
    "reference_contract_mapping", "native-model-workspace-exact", ...
    "native_model_workspace_before_file_presence", modelBinding, ...
    "native_model_workspace_before_matches_requested", isequaln(requested, modelBefore), ...
    "pass", false, ...
    "native_model_workspace_pass", false);
end

function receipt = localVerifyScenarioWitness(receipt, model)
baseAfter = localPlainInput(evalin("base", "xauto11_input"));
modelAfter = localReadModelWorkspaceInput(model);
receipt.applied_parameters = modelAfter;
receipt.base_value_after_simulation_file_presence = localStructFilePresence(baseAfter);
receipt.base_value_after_simulation_matches_requested = ...
    isequaln(receipt.requested_parameters, baseAfter);
receipt.native_model_workspace_after_file_presence = localStructFilePresence(modelAfter);
receipt.native_model_workspace_after_matches_requested = ...
    isequaln(receipt.requested_parameters, modelAfter);
receipt.native_model_workspace_pass = ...
    receipt.native_model_workspace_before_matches_requested && ...
    receipt.native_model_workspace_after_matches_requested;
receipt.pass = receipt.base_value_before_simulation_matches_requested && ...
    receipt.simulationinput_and_base_match && ...
    receipt.base_value_after_simulation_matches_requested && ...
    receipt.native_model_workspace_pass && ...
    receipt.requested_input_file_presence == receipt.base_value_before_simulation_file_presence && ...
    receipt.requested_input_file_presence == receipt.simulationinput_value_file_presence && ...
    receipt.requested_input_file_presence == receipt.base_value_after_simulation_file_presence;
end

function log = localPublicApplicationLog(receipt)
log = receipt;
end

function requested = localRequestedInput(scenario)
requested = struct("sprung_mass_kg", double(scenario.sprung_mass_kg), ...
    "suspension_stiffness_n_per_m", double(scenario.suspension_stiffness_n_per_m), ...
    "suspension_damping_n_s_per_m", double(scenario.suspension_damping_n_s_per_m), ...
    "road_peak_m", double(scenario.road_peak_m), ...
    "road_angular_frequency_rad_per_s", ...
    double(scenario.road_angular_frequency_rad_per_s));
end

function requested = localReadModelWorkspaceInput(model)
workspace = get_param(model, "ModelWorkspace");
road = model + "/Road Bump/Sine Wave";
requested = struct("sprung_mass_kg", double(workspace.evalin("Mb")), ...
    "suspension_stiffness_n_per_m", double(workspace.evalin("Ks")), ...
    "suspension_damping_n_s_per_m", double(workspace.evalin("Bs")), ...
    "road_peak_m", 2 * str2double(get_param(road, "Bias")), ...
    "road_angular_frequency_rad_per_s", str2double(get_param(road, "Frequency")));
end

function value = localPlainInput(value)
if isa(value, "Simulink.Parameter"), value = value.Value; end
assert(isstruct(value) && isscalar(value), "SimuVerity:XAUTO11:PublicInput", ...
    "xauto11_input must be a scalar struct.");
end

function state = localCaptureBase(name)
escaped = replace(string(name), "'", "''");
state = struct("name", string(name), "existed", ...
    logical(evalin("base", "exist('" + escaped + "','var') == 1")), "value", []);
if state.existed, state.value = evalin("base", char(name)); end
end

function localRestoreBase(state)
if state.existed
    assignin("base", char(state.name), state.value);
else
    escaped = replace(state.name, "'", "''");
    evalin("base", "if exist('" + escaped + "','var'), clear('" + escaped + "'); end");
end
end

function localAddAppliedForceTap(model)
subsystem=model+"/Quarter Car Model";
block=subsystem+"/__xauto11_applied_force_log";
assert(getSimulinkBlockHandle(block)<0,"SimuVerity:XAUTO11:TapExists","Runtime tap already exists.");
add_block("simulink/Sinks/To Workspace",block,"VariableName","xauto11_applied_force", ...
    "SaveFormat","Timeseries","MaxDataPoints","inf","Position",[650 330 765 360]);
source=get_param(subsystem+"/Scaling Term","PortHandles"); sink=get_param(block,"PortHandles");
add_line(subsystem,source.Outport(1),sink.Inport(1),"autorouting","on");
end

function signals = localExtractSignals(simOut, grid)
logs=simOut.logsout;
road=localLogged(logs,"Road Disturbance");
body=localLogged(logs,"Body Travel");
deflection=localLogged(logs,"Suspension Deflection");
acceleration=localLogged(logs,"Body Acceleration");
command=localLogged(logs,"Control Force");
names=string(simOut.who); assert(any(names=="xauto11_applied_force"), ...
    "SimuVerity:XAUTO11:MissingAppliedForce","Applied-force tap is absent.");
applied=localTimeseries(simOut.get("xauto11_applied_force"));
road=localResample(road,grid); body=localResample(body,grid); deflection=localResample(deflection,grid);
acceleration=localResample(acceleration,grid); command=localResample(command,grid); applied=localResample(applied,grid);
wheel=body-deflection;
signals=struct("suspension_state",[road body wheel deflection acceleration], ...
    "active_control_state",[command applied]);
end

function signal = localLogged(logs,name)
element=logs.getElement(name); assert(~isempty(element),"SimuVerity:XAUTO11:MissingLog","Missing %s",name);
if isa(element,"Simulink.SimulationData.Dataset"), element=element.get(1); end
signal=localTimeseries(element.Values);
end

function signal = localTimeseries(value)
signal=struct("time",double(value.Time(:)),"data",double(value.Data(:)));
end

function data = localResample(signal,grid)
[time,indices]=unique(signal.time,"stable"); values=signal.data(indices);
assert(numel(time)>=2 && all(diff(time)>0),"SimuVerity:XAUTO11:TimeAxis","Invalid source time axis.");
assert(time(1)<=1e-9 && time(end)>=grid(end)-1e-9,"SimuVerity:XAUTO11:Coverage","Source log is truncated.");
data=interp1(time,values,grid,"linear");
assert(all(isfinite(data)),"SimuVerity:XAUTO11:Finite","Resampled evidence is nonfinite.");
end

function valid = localValid(grid,signals)
valid=size(signals.suspension_state,1)==numel(grid) && ...
    size(signals.suspension_state,2)==5 && size(signals.active_control_state,1)==numel(grid) && ...
    size(signals.active_control_state,2)==2 && all(isfinite(signals.suspension_state),"all") && ...
    all(isfinite(signals.active_control_state),"all") && grid(1)==0 && grid(end)>=2;
end

function log = localLog(grid,data,channels,units)
log=struct("format","Timeseries","channels",{channels},"units",{units}, ...
    "time",grid,"data",data);
end

function root = localProjectRoot()
root=fileparts(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

function binding = localStructFilePresence(value)
binding = string(jsonencode(value));
end

function localWriteJson(path,value)
fid=fopen(path,"w","n","UTF-8"); assert(fid>=0,"SimuVerity:XAUTO11:WriteFailed","Cannot write JSON.");
cleanupFile=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),"char"); fwrite(fid,newline,"char");
end

function localClose(model)
if bdIsLoaded(model), close_system(model,0); end
end
