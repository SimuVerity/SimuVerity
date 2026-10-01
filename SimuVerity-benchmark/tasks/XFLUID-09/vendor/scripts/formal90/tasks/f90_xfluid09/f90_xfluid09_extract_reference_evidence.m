function evidence = f90_xfluid09_extract_reference_evidence(modelPath, outDir, evaluationMode)
%F90_XFLUID09_EXTRACT_REFERENCE_EVIDENCE Persistent-session evidence replay.
% The pinned source is opened read-only.  The sole temporary tap observes
% the existing valve-command signal and is never saved into the golden.

arguments
    modelPath (1,1) string
    outDir (1,1) string
    evaluationMode (1,1) string = "reference"
end

try
root = localRepoRoot;
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
assert(isfile(modelPath), "SimuVerity:F90:XFLUID09:ModelMissing", "Pinned model is missing.");
if strcmpi(evaluationMode, "candidate")
    evidence = localRunCandidate(modelPath, outDir, official);
    return;
end
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
assert(evaluationSubject == "reference", ...
    "SimuVerity:F90:XFLUID09:EvaluationSubject", ...
    "Native reference extraction requires reference evaluation subject.");
assetRoot = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
assert(isfolder(assetRoot), "SimuVerity:F90:XFLUID09:ReferenceAssetRoot", ...
    "Evaluator-owned reference asset root is missing.");
expectedModelPresence = lower(strtrim(string("present")));
assert(expectedModelPresence == "present", ...
    "SimuVerity:F90:XFLUID09:ReferencePresence", ...
    "Task-bound reference file presence is missing or invalid.");
if isfile(fullfile(outDir, "evidence.json"))
    prior = jsondecode(fileread(fullfile(outDir, "evidence.json")));
    assert(~isfield(prior, "evidence_complete") || ~prior.evidence_complete, ...
        "SimuVerity:F90:XFLUID09:OutputReuse", "Evidence is already complete for this run.");
end
if ~isfolder(outDir), mkdir(outDir); end
cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XFLUID09:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);

sourceDir = fileparts(modelPath);
initialBinding = localFilePresence(modelPath);
evidence = localEvidenceSkeleton;
assert(strcmpi(initialBinding, expectedModelPresence), ...
    "SimuVerity:F90:XFLUID09:ModelBinding", "Pinned model file presence mismatch.");
supportNames = ["hydrogen_properties.mat"; "silicone_fluid_properties.mat"];
supportBindings = [ ...
    "present"; ...
    "present"];
for index = 1:numel(supportNames)
    support = fullfile(assetRoot, supportNames(index));
    assert(isfile(support) && strcmpi(localFilePresence(support), ...
        supportBindings(index)), ...
        "SimuVerity:F90:XFLUID09:SupportBinding", "Pinned support-file file presence mismatch.");
end

[~, sourceName] = fileparts(modelPath);
model = string(sourceName);
oldFolder = pwd;
folderCleanup = onCleanup(@() cd(oldFolder)); %#ok<NASGU>
try
    cd(sourceDir);
    localLoadSupportFiles(sourceDir);
    load_system(modelPath);
    model = string(bdroot(model));
    evidence.load_pass = true;
    paths = localModelPaths(model);
    localInstallValveTap(model, paths);

    staticReport = formal90_nonfailfast_preflight( ...
        localStaticChecks(modelPath, sourceDir, model, paths, outDir), ...
        fullfile(outDir, "preflight_static.json"));
    evidence.preflight.static = staticReport;
    if ~staticReport.pass
        evidence.errors.preflight = struct("stage", "static", ...
            "message", "One or more adapter/static checks failed.");
        localFinish(model, modelPath, initialBinding, outDir, evidence);
        return;
    end

    set_param(model, "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", "SignalLoggingName", "logsout", ...
        "SimscapeLogType", "all", ...
        "SimscapeLogName", "simlog_HydrogenRefuelingStation", ...
        "SimscapeLogLimitData", "off");
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(model, [], [], [], "compile");
    compiledReport = formal90_nonfailfast_preflight( ...
        localCompiledChecks(paths), fullfile(outDir, "preflight_compiled.json"));
    feval(model, [], [], [], "term");
    evidence.preflight.compiled = compiledReport;
    evidence.compile_pass = compiledReport.pass;
    if ~compiledReport.pass
        evidence.errors.preflight = struct("stage", "compiled", ...
            "message", "One or more compiled port/type/bus checks failed.");
        localFinish(model, modelPath, initialBinding, outDir, evidence);
        return;
    end
    evidence.static_audit = localStaticAudit(model, paths);

    localApplyScenario(model, official.scenarios(1));
    originalStop = string(get_param(model, "StopTime"));
    set_param(model, "StopTime", "60");
    smoke = sim(model, "ReturnWorkspaceOutputs", "on");
    localValidateSmoke(smoke);
    evidence.nominal_smoke_pass = true;
    clear smoke
    set_param(model, "StopTime", originalStop);

    rows = repmat(localEmptyScenario, numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).requested_inputs = scenario;
        try
            localApplyScenario(model, scenario);
            started = tic;
            simOut = sim(model, "ReturnWorkspaceOutputs", "on");
            rows(index).simulation_wall_clock_s = toc(started);
            outputs = localExtractOutputs(simOut);
            rows(index) = localFinalizeScenario(rows(index), outputs, scenario);
            localWriteScenarioEvidence(outDir, rows(index), outputs);
            clear simOut outputs
        catch exception
            rows(index).error = localError(exception);
            localWriteJson(fullfile(outDir, "scenario_" + rows(index).id + ".json"), rows(index));
        end
        evidence.scenarios = rows(1:index);
        localWriteJson(fullfile(outDir, "partial_evidence.json"), evidence);
    end
    evidence.scenarios = rows;
    evidence.evidence_complete = all([rows.valid]) && evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && evidence.nominal_smoke_pass;
catch exception
    evidence.errors.session = localError(exception);
end
localFinish(model, modelPath, initialBinding, outDir, evidence);
catch exception
    if ~isfolder(outDir), mkdir(outDir); end
    evidence = localEvidenceSkeleton;
    evidence.errors.outer_session = localError(exception);
    evidence.runtime.finished_at = localNow;
    localWriteJson(fullfile(outDir, "evidence.json"), evidence);
end
end

function evidence = localRunCandidate(modelPath, outDir, official)
if ~isfolder(outDir), mkdir(outDir); end
evidence=localEvidenceSkeleton; [~,model]=fileparts(modelPath); model=string(model);
old=pwd; cleanup=onCleanup(@() cd(old)); %#ok<NASGU>
try
    addpath(fileparts(modelPath),"-begin"); cd(fileparts(modelPath));
    load_system(modelPath); evidence.load_pass=true;
    set_param(model,"ReturnWorkspaceOutputs","on","SignalLogging","on", ...
        "SignalLoggingName","logsout");
    localApplyCandidateScenario(official.scenarios(1));
    set_param(model,"SimulationCommand","update");
    evidence.update_pass=true;
    feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    evidence.compile_pass=true; evidence.static_audit=localCandidateStaticAudit(model);
    originalStop=string(get_param(model,"StopTime")); set_param(model,"StopTime","60");
    smoke=sim(model,"ReturnWorkspaceOutputs","on");
    localExtractCandidateOutputs(smoke); evidence.nominal_smoke_pass=true;
    set_param(model,"StopTime",originalStop);
    rows=repmat(localEmptyScenario,numel(official.scenarios),1);
    for index=1:numel(official.scenarios)
        scenario=official.scenarios(index); rows(index).id=string(scenario.id);
        rows(index).requested_inputs=scenario;
        try
            localApplyCandidateScenario(scenario);
            set_param(model,"StopTime",string(double(scenario.stop_time_s)));
            started=tic; simOut=sim(model,"ReturnWorkspaceOutputs","on");
            rows(index).simulation_wall_clock_s=toc(started);
            outputs=localExtractCandidateOutputs(simOut);
            rows(index)=localFinalizeScenario(rows(index),outputs,scenario);
            localWriteScenarioEvidence(outDir,rows(index),outputs);
        catch exception
            rows(index).error=localError(exception);
        end
    end
    evidence.scenarios=rows;
    evidence.evidence_complete=all([rows.valid])&&evidence.load_pass&& ...
        evidence.update_pass&&evidence.compile_pass&&evidence.nominal_smoke_pass;
catch exception
    evidence.errors.session=localError(exception);
end
try, close_system(model,0); catch, end
localWriteJson(fullfile(outDir,"evidence.json"),evidence);
end

function localApplyCandidateScenario(scenario)
for name=["p_storage","p_vehicle_init","T_env","T_fluid"]
    assignin("base",name,double(scenario.(name)));
end
end

function outputs=localExtractCandidateOutputs(simOut)
outputs=struct;
outputs.vehicle_pressure=localCandidateTimeseries(simOut,"VehiclePressure_bar",1);
outputs.vehicle_temperature=localCandidateTimeseries(simOut,"VehicleTemperature_C",1);
outputs.vehicle_mass_flow=localCandidateTimeseries(simOut,"VehicleMassFlow_kg_s",1);
outputs.valve_command=localCandidateTimeseries(simOut,"ReductionValveCommand",1);
buffer=localCandidateTimeseries(simOut,"BufferPressure_bar",3);
outputs.buffer_high_pressure=localSignalColumn(buffer,1);
outputs.buffer_medium_pressure=localSignalColumn(buffer,2);
outputs.buffer_low_pressure=localSignalColumn(buffer,3);
outputs.vehicle_density=struct("time_s",buffer.time_s, ...
    "values",zeros(numel(buffer.time_s),1));
end

function output=localCandidateTimeseries(simOut,variable,width)
series=simuverity_public_output_compatibility( ...
 simOut,string(variable),width,AllowBaseWorkspace=true);
output=struct("time_s",double(series.Time(:)),"values",double(series.Data));
end

function output=localSignalColumn(signal,index)
output=struct("time_s",signal.time_s,"values",signal.values(:,index));
end

function audit=localCandidateStaticAudit(model)
blocks=lower(string(find_system(model,"FollowLinks","on", ...
    "LookUnderMasks","all","Type","Block")));
has=@(token) any(contains(blocks,lower(string(token))));
audit=struct("low_pressure_storage_present",has("storage")||has("tank"), ...
    "multistage_compression_present",sum(contains(blocks,"compress"))>=2, ...
    "cascade_buffer_present",has("buffer"),"reduction_valve_present",has("valve"), ...
    "precooler_present",has("cool"),"vehicle_tank_present",has("vehicle")&&has("tank"), ...
    "feedback_and_supervision_present",has("control")||has("feedback"), ...
    "core_physical_path_qualified",has("tank")&&has("valve")&&has("compress"), ...
    "candidate_structure_scan",true);
end

function evidence = localEvidenceSkeleton
evidence = struct( ...
    "schema", "simuverity.f90-xfluid09-evidence.v1", ...
    "task_id", "F90-XFLUID-09", "evidence_complete", false, ...
    "extraction_only", true, "contains_score_decisions", false, ...
    "reference_substantive_modifications", 0, ...
    "load_pass", false, "update_pass", false, "compile_pass", false, ...
    "nominal_smoke_pass", false, "preflight", struct, ...
    "static_audit", struct, "scenarios", struct([]), "errors", struct, ...
    "runtime", struct("generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
        "matlab_release", string(version("-release")), ...
        "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")), ...
        "started_at", localNow));
end

function localFinish(model, modelPath, initialBinding, outDir, evidence)
try
    if strlength(model) > 0 && bdIsLoaded(model), close_system(model, 0); end
catch exception
    evidence.errors.close = localError(exception);
end
evidence.model_closed_without_save = ~bdIsLoaded(model);
evidence.reference_model_binding_after = localFilePresence(modelPath);
evidence.reference_model_unchanged = strcmpi(initialBinding, evidence.reference_model_binding_after);
evidence.runtime.finished_at = localNow;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
fprintf("F90_XFLUID09_EVIDENCE complete=%d smoke=%d valid=%d/%d path=%s\n", ...
    evidence.evidence_complete, evidence.nominal_smoke_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), outDir);
end

function localLoadSupportFiles(sourceDir)
for filename = ["hydrogen_properties.mat", "silicone_fluid_properties.mat"]
    payload = load(fullfile(sourceDir, filename));
    names = fieldnames(payload);
    assert(~isempty(names), "SimuVerity:F90:XFLUID09:SupportEmpty", "Empty support MAT: %s", filename);
    for index = 1:numel(names)
        assignin("base", names{index}, payload.(names{index}));
    end
end
end

function paths = localModelPaths(model)
paths = struct;
paths.valve_command = model + "/From6";
paths.control_logic = model + "/Control Logic";
paths.vehicle_tank = localFindByTokens(model, ["vehicle", "tank"]);
paths.cascade_buffer = localFindByTokens(model, ["cascade", "buffer"]);
paths.reduction_valve = localFindByTokens(model, ["reduction", "valve"]);
paths.precooler = localFindByTokens(model, ["precool"]);
paths.low_storage = localFindByTokens(model, ["low", "pressure", "storage"]);
paths.compressor_count = localCountByToken(model, "compressor");
end

function checks = localStaticChecks(modelPath, sourceDir, model, paths, outDir)
checks = [ ...
    localCheck("golden_model", "path", @() localFileCheck(modelPath)), ...
    localCheck("hydrogen_properties", "dependency", @() localFileCheck(fullfile(sourceDir, "hydrogen_properties.mat"))), ...
    localCheck("silicone_properties", "dependency", @() localFileCheck(fullfile(sourceDir, "silicone_fluid_properties.mat"))), ...
    localCheck("task_output_path", "path", @() localPathCheck(outDir)), ...
    localCheck("simulation_api", "api", @localApiCheck), ...
    localCheck("workspace_inputs", "workspace", @localWorkspaceInputCheck), ...
    localCheck("vehicle_tank_locator", "locator", @() localBlockCheck(paths.vehicle_tank)), ...
    localCheck("cascade_buffer_locator", "locator", @() localBlockCheck(paths.cascade_buffer)), ...
    localCheck("reduction_valve_locator", "locator", @() localBlockCheck(paths.reduction_valve)), ...
    localCheck("precooler_locator", "locator", @() localBlockCheck(paths.precooler)), ...
    localCheck("low_storage_locator", "locator", @() localBlockCheck(paths.low_storage)), ...
    localCheck("control_logic_locator", "locator", @() localBlockCheck(paths.control_logic)), ...
    localCheck("compressor_stages", "locator", @() localCountCheck(paths.compressor_count, 3, "three compression-stage blocks")), ...
    localCheck("valve_command_port", "port", @() localOutportCheck(paths.valve_command)), ...
    localCheck("logging_object", "logging", @() localTapCheck(model)) ...
    ];
end

function checks = localCompiledChecks(paths)
checks = localCheck("valve_command_dimension_type_bus", "compiled", ...
    @() localCompiledSignalCheck(paths.valve_command));
end

function check = localCheck(id, category, action)
check = struct("id", string(id), "category", string(category), "run", action);
end

function result = localFileCheck(path)
result = struct("passed", isfile(path), "observed", string(path), "detail", "required pinned file");
end

function result = localPathCheck(path)
result = struct("passed", strlength(string(path)) < 220, "observed", string(path), ...
    "detail", "Windows output path length must remain safe");
end

function result = localApiCheck
versions = ver;
products = string({versions.Name});
needed = ["Simulink", "Simscape", "Simscape Fluids", "Stateflow"];
passed = all(arrayfun(@(name) any(contains(products, name)), needed));
result = struct("passed", passed, "observed", strjoin(products, ";"), ...
    "detail", "required R2025a Simulink/Simscape/Fluids/Stateflow products");
end

function result = localWorkspaceInputCheck
needed = ["p_storage", "p_vehicle_init", "T_env", "T_fluid"];
names = string(evalin("base", "who"));
result = struct("passed", all(ismember(needed, names)), "observed", strjoin(names, ","), ...
    "detail", "all four supported source workspace inputs must be loaded");
end

function result = localBlockCheck(path)
passed = strlength(path) > 0 && getSimulinkBlockHandle(path) > 0;
result = struct("passed", passed, "observed", path, "detail", "required real source locator");
end

function result = localCountCheck(count, minimum, detail)
result = struct("passed", count >= minimum, "observed", string(count), "detail", detail);
end

function result = localOutportCheck(path)
if strlength(path) == 0 || getSimulinkBlockHandle(path) < 0
    result = struct("passed", false, "observed", path, "detail", "source output locator missing");
    return;
end
ports = get_param(path, "PortHandles");
passed = isfield(ports, "Outport") && numel(ports.Outport) == 1 && ports.Outport(1) > 0;
result = struct("passed", passed, "observed", path, "detail", "one real Simulink output port required");
end

function result = localTapCheck(model)
tap = model + "/F90_Tap_f90_xfluid09_valve_command";
passed = getSimulinkBlockHandle(tap) > 0 && ...
    string(get_param(tap, "VariableName")) == "f90_xfluid09_valve_command" && ...
    string(get_param(tap, "MaxDataPoints")) == "inf";
result = struct("passed", passed, "observed", "f90_xfluid09_valve_command", ...
    "detail", "temporary complete Timeseries tap without a sample cap");
end

function result = localCompiledSignalCheck(path)
types = get_param(path, "CompiledPortDataTypes");
dims = get_param(path, "CompiledPortDimensions");
kind = string(types.Outport);
dimension = dims.Outport;
passed = numel(kind) == 1 && ~contains(kind, "Bus", IgnoreCase=true) && ...
    isnumeric(dimension) && all(isfinite(double(dimension(:))));
result = struct("passed", passed, ...
    "observed", "type=" + kind + ";dims=" + mat2str(dimension), ...
    "detail", "compiled scalar non-bus valve-command output required");
end

function localInstallValveTap(model, paths)
tap = model + "/F90_Tap_f90_xfluid09_valve_command";
assert(getSimulinkBlockHandle(tap) < 0, "SimuVerity:F90:XFLUID09:TapCollision", ...
    "Temporary measurement tap collision.");
add_block("simulink/Sinks/To Workspace", tap, ...
    "VariableName", "f90_xfluid09_valve_command", ...
    "SaveFormat", "Timeseries", "MaxDataPoints", "inf");
sourcePorts = get_param(paths.valve_command, "PortHandles");
tapPorts = get_param(tap, "PortHandles");
add_line(model, sourcePorts.Outport(1), tapPorts.Inport(1), "autorouting", "on");
end

function localApplyScenario(model, scenario)
for name = ["p_storage", "p_vehicle_init", "T_env", "T_fluid"]
    value = double(scenario.(name));
    assert(isfinite(value), "SimuVerity:F90:XFLUID09:Input", "Invalid workspace input %s.", name);
    assignin("base", name, value);
end
set_param(model, "StopTime", string(double(scenario.stop_time_s)));
end

function localValidateSmoke(simOut)
outputs = localExtractOutputs(simOut);
assert(numel(outputs.vehicle_pressure.time_s) >= 2 && ...
    all(isfinite(outputs.vehicle_pressure.values)) && ...
    all(isfinite(outputs.vehicle_temperature.values)) && ...
    all(isfinite(outputs.valve_command.values)), ...
    "SimuVerity:F90:XFLUID09:SmokeOutput", "Short nominal smoke did not produce complete required logs.");
end

function outputs = localExtractOutputs(simOut)
simlog = localGetSimlog(simOut);
outputs = struct;
outputs.vehicle_pressure = localSimscapeSeries(simlog.Vehicle.Vehicle_Tank.p_I, "bar");
outputs.vehicle_temperature = localSimscapeSeries(simlog.Vehicle.Vehicle_Tank.T_I, "degC");
outputs.vehicle_density = localSimscapeSeries(simlog.Vehicle.Vehicle_Tank.rho_I, "kg/m^3");
outputs.vehicle_mass_flow = localSimscapeSeries(simlog.Reduction_Valve.Valve.mdot_A, "kg/s");
outputs.buffer_high_pressure = localSimscapeSeries(simlog.Cascade_Buffer.High_Pressure.Tank.p_I, "bar");
outputs.buffer_medium_pressure = localSimscapeSeries(simlog.Cascade_Buffer.Medium_Pressure.Tank.p_I, "bar");
outputs.buffer_low_pressure = localSimscapeSeries(simlog.Cascade_Buffer.Low_Pressure.Tank.p_I, "bar");
outputs.valve_command = localTimeseries(simOut, "f90_xfluid09_valve_command",1);
end

function simlog = localGetSimlog(simOut)
try
    simlog = simOut.get("simlog_HydrogenRefuelingStation");
catch
    simlog = evalin("base", "simlog_HydrogenRefuelingStation");
end
assert(~isempty(simlog), "SimuVerity:F90:XFLUID09:Simlog", "Required Simscape log is missing.");
end

function output = localSimscapeSeries(node, unit)
% simscape.logging.Series.time is a zero-argument method.  Obtain its
% value before reshaping; indexing it inline is interpreted as a method
% call with an argument on R2025a.
time = double(node.series.time);
time = time(:);
values = double(node.series.values(unit));
values = values(:);
assert(numel(time) >= 2 && numel(time) == numel(values) && ...
    all(isfinite(time)) && all(isfinite(values)), ...
    "SimuVerity:F90:XFLUID09:SimscapeSeries", "Malformed native Simscape series.");
output = struct("time_s", time, "values", values);
end

function output = localTimeseries(simOut, variable, expectedWidth)
try
    series = simOut.get(variable);
catch
    series = evalin("base", variable);
end
assert(isa(series, "timeseries"), "SimuVerity:F90:XFLUID09:Timeseries", ...
    "Required output %s is not a Timeseries.", variable);
time = double(series.Time(:));
values = double(series.Data);
if size(values,1) == numel(time)
    values = reshape(values,numel(time),[]);
elseif size(values,ndims(values)) == numel(time)
    values = permute(values,[ndims(values),1:ndims(values)-1]);
    values = reshape(values,numel(time),[]);
elseif numel(time) == 1
    values = reshape(values,1,[]);
else
    error("SimuVerity:F90:XFLUID09:TimeseriesShape", ...
        "Required output %s does not align with its time vector.",variable);
end
assert(numel(time) >= 2 && size(values,1) == numel(time) && ...
    size(values,2) == expectedWidth && all(isfinite(time)) && ...
    all(isfinite(values),"all"), ...
    "SimuVerity:F90:XFLUID09:TimeseriesShape", "Malformed required Timeseries.");
output = struct("time_s", time, "values", values);
end

function row = localFinalizeScenario(row, outputs, scenario)
p = outputs.vehicle_pressure;
temperature = localInterpolate(outputs.vehicle_temperature, p.time_s);
flow = localInterpolate(outputs.vehicle_mass_flow, p.time_s);
valve = localInterpolate(outputs.valve_command, p.time_s);
bufferRanges = [localRange(outputs.buffer_high_pressure.values), ...
    localRange(outputs.buffer_medium_pressure.values), ...
    localRange(outputs.buffer_low_pressure.values)];
flowMagnitude = abs(flow);
active = flowMagnitude >= max(1e-4, 0.02 * max(flowMagnitude));
if ~any(active), active = true(size(flowMagnitude)); end
dp = diff(p.values);
positive = sum(max(dp, 0));
backtrack = sum(max(-dp, 0)) / max(positive, eps);
dpdt = gradient(p.values, p.time_s);
row.simulation_pass = true;
row.required_evidence_pass = numel(p.time_s) >= 100 && p.time_s(1) <= 0.1 && ...
    p.time_s(end) >= 0.99 * double(scenario.stop_time_s) && ...
    max(flowMagnitude) > 1e-4 && all(isfinite([p.values; temperature; flow; valve]));
row.valid = row.required_evidence_pass;
row.sample_count = numel(p.time_s);
row.start_time_s = p.time_s(1);
row.end_time_s = p.time_s(end);
row.metrics = struct( ...
    "vehicle_initial_pressure_bar", p.values(1), ...
    "vehicle_final_pressure_bar", p.values(end), ...
    "vehicle_pressure_rise_bar", p.values(end) - p.values(1), ...
    "vehicle_peak_temperature_C", max(temperature), ...
    "vehicle_final_temperature_C", temperature(end), ...
    "delivered_mass_kg", trapz(p.time_s, flowMagnitude), ...
    "max_vehicle_mass_flow_kg_s", max(flowMagnitude), ...
    "valve_command_range", localRange(valve), ...
    "buffer_pressure_excursion_bar", max(bufferRanges), ...
    "pressure_backtrack_fraction", backtrack, ...
    "valve_flow_correlation", localCorrelation(valve(active), flowMagnitude(active)), ...
    "pressure_flow_correlation", localCorrelation(dpdt(active), flowMagnitude(active)));
row.error = struct;
end

function localWriteScenarioEvidence(outDir, row, outputs)
matPath = fullfile(outDir, "scenario_" + row.id + ".mat");
temporary = matPath + ".tmp.mat";
save(temporary, "outputs", "row");
movefile(temporary, matPath, "f");
row.evidence_mat_file_presence = localFilePresence(matPath);
localWriteJson(fullfile(outDir, "scenario_" + row.id + ".json"), row);
end

function audit = localStaticAudit(model, paths)
audit = struct( ...
    "low_pressure_storage_present", localExists(paths.low_storage), ...
    "multistage_compression_present", paths.compressor_count >= 3, ...
    "cascade_buffer_present", localExists(paths.cascade_buffer), ...
    "reduction_valve_present", localExists(paths.reduction_valve), ...
    "precooler_present", localExists(paths.precooler), ...
    "vehicle_tank_present", localExists(paths.vehicle_tank), ...
    "feedback_and_supervision_present", localExists(paths.control_logic) && localExists(paths.valve_command), ...
    "core_physical_path_qualified", localExists(paths.low_storage) && ...
        paths.compressor_count >= 3 && localExists(paths.cascade_buffer) && ...
        localExists(paths.reduction_valve) && localExists(paths.precooler) && ...
        localExists(paths.vehicle_tank) && localExists(paths.control_logic), ...
    "source_model", model);
end

function path = localFindByTokens(model, tokens)
blocks = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block");
path = "";
for index = 1:numel(blocks)
    name = lower(string(get_param(blocks{index}, "Name")));
    if all(arrayfun(@(token) contains(name, lower(token)), tokens))
        path = string(blocks{index});
        return;
    end
end
end

function count = localCountByToken(model, token)
blocks = find_system(model, "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block");
count = 0;
for index = 1:numel(blocks)
    if contains(lower(string(get_param(blocks{index}, "Name"))), lower(token))
        count = count + 1;
    end
end
end

function present = localExists(path)
present = strlength(path) > 0 && getSimulinkBlockHandle(path) > 0;
end

function values = localInterpolate(source, time)
values = interp1(source.time_s, source.values, time, "linear", "extrap");
values = double(values(:));
end

function value = localRange(values)
values = double(values(:));
value = max(values) - min(values);
end

function value = localCorrelation(a, b)
a = double(a(:)); b = double(b(:));
if numel(a) < 3 || std(a) <= eps || std(b) <= eps
    value = 0;
else
    coefficient = corrcoef(a, b);
    value = coefficient(1, 2);
end
end

function row = localEmptyScenario
row = struct("id", "", "requested_inputs", struct, "simulation_pass", false, ...
    "required_evidence_pass", false, "valid", false, "simulation_wall_clock_s", NaN, ...
    "sample_count", 0, "start_time_s", NaN, "end_time_s", NaN, ...
    "metrics", struct, "error", struct);
end

function count = localValidCount(rows)
if isempty(rows) || ~isfield(rows, "valid"), count = 0; else, count = sum([rows.valid]); end
end

function localWriteJson(path, payload)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
temporary = path + ".tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XFLUID09:Write", "Cannot write %s", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(payload, PrettyPrint=true));
clear cleanup
movefile(temporary, path, "f");
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

function result = localError(exception)
result = struct("identifier", string(exception.identifier), ...
    "message", string(exception.message), ...
    "report", string(getReport(exception,"extended","hyperlinks","off")));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function root = localRepoRoot
root = fileparts(fileparts(fileparts(fileparts(fileparts(mfilename("fullpath"))))));
end
