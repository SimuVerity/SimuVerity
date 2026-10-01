function evidence = f90_xfluid03_extract_reference_evidence( ...
        modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
%F90_XFLUID03_EXTRACT_REFERENCE_EVIDENCE Native bundled-reference replay.
%
% The official Tractor-Simscape project is opened from the evaluator-owned
% bundled closure.  The adapter only exposes existing workspace inputs,
% shortens the native run in memory, and converts native logged measurements
% to the current score evidence.  The source project and model are never saved.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
outDir = outputDir;
sourceRoot = fullfile(evaluatorAssetRoot, "Tractor-Simscape");
projectPath = fullfile(sourceRoot, "TractorSimscape.prj");
referenceModelPath = fullfile(sourceRoot, "Model", ...
    "TractorEnergyComputation.slx");
inputScript = fullfile(sourceRoot, "Scripts", ...
    "TractorEnergyComputationInput.m");

assert(isfile(officialScenarios), "SimuVerity:F90:XFLUID03:OfficialScenarios", ...
    "Official scenarios are missing.");
assert(isfolder(sourceRoot), "SimuVerity:F90:XFLUID03:ReferenceAssetRoot", ...
    "Evaluator-owned Tractor-Simscape reference root is missing.");
scenarioContract = jsondecode(fileread(officialScenarios));
expectedPresence = lower(strtrim(string("present")));
modelPresenceBefore = localFilePresenceFile(modelPath);
assert(modelPresenceBefore == expectedPresence, "SimuVerity:F90:XFLUID03:ReferenceIdentity", ...
    "Reference file presence differs from the task binding.");
referenceModelPresenceBefore = localFilePresenceFile(referenceModelPath);
assert(referenceModelPresenceBefore == expectedPresence, ...
    "SimuVerity:F90:XFLUID03:ReferenceAssetIdentity", ...
    "Project-owned reference model file presence differs from the task binding.");

generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XFLUID03:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
assert(isfile(modelPath) && isfile(projectPath) && ...
    isfile(referenceModelPath) && isfile(inputScript), ...
    "SimuVerity:F90:XFLUID03:ReferenceMissing", ...
    "The pinned reference project is incomplete.");
assert(~isfolder(outDir), "SimuVerity:F90:XFLUID03:OutputReuse", ...
    "Evidence output already exists for GenerationRunId %s.", generationRunId);
mkdir(outDir);

localConfigureIsolation;
set(groot, "defaultFigureVisible", "off");
oldDir = pwd;
dirCleanup = onCleanup(@() cd(oldDir)); %#ok<NASGU>
cd(sourceRoot);

evidence = struct;
evidence.schema = "simuverity.f90-xfluid03-evidence.v1";
evidence.task_id = "F90-XFLUID-03";
evidence.reference_adapter = ...
    "direct_pinned_project_in_memory_workspace_and_logging_adapter";
evidence.source = struct( ...
    "repository", "https://github.com/simscape/Tractor-Simscape.git", ...
    "tag", "25.1.1.0", ...
    "commit", "866554b3fcbe8a01c4366790b35c007688e223ca", ...
    "main_model", "Model/TractorEnergyComputation.slx", ...
    "fluid_model", "Component/Transmission/HydrostaticCVT.slx");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.reference_identity_applicable = true;
evidence.reference_subject = modelPresenceBefore == expectedPresence;
evidence.runtime_model_file_presence_before = modelPresenceBefore;
evidence.reference_model_file_presence_before = referenceModelPresenceBefore;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.model_closed_without_save = false;
evidence.binding_preserved = false;
evidence.scenarios = repmat(localEmptyScenario, 0, 1);
evidence.static_audit = struct;
evidence.errors = struct;
evidence.started_at = localNow;
evidence.runtime = localRuntime(generationRunId);

project = [];
model = "";
artifacts = repmat(struct("id", "", "signals", struct), ...
    numel(scenarioContract.scenarios), 1);
try
    project = openProject(projectPath);
    projectCleanup = onCleanup(@() localCloseProject(project)); %#ok<NASGU>
    modelHandle = load_system(referenceModelPath);
    model = string(get_param(modelHandle, "Name"));
    modelCleanup = onCleanup(@() localCloseModel(model)); %#ok<NASGU>
    evidence.load_pass = true;

    originalInit = string(get_param(model, "InitFcn"));
    initCleanup = onCleanup(@() localRestoreInit(model, originalInit)); %#ok<NASGU>
    set_param(model, "InitFcn", "");
    set_param(model, ...
        "StopTime", string(scenarioContract.simulation.stop_time_s), ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "SignalLoggingSaveFormat", "Dataset", ...
        "LimitDataPoints", "off");

    localLoadNativeInputs(inputScript);
    localApplyScenario(scenarioContract.scenarios(1));
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

    evidence.static_audit = localStaticAudit(model);
    rows = repmat(localEmptyScenario, ...
        numel(scenarioContract.scenarios), 1);
    for index = 1:numel(scenarioContract.scenarios)
        scenario = scenarioContract.scenarios(index);
        rows(index).id = string(scenario.id);
        rows(index).requested_inputs = rmfield(scenario, "id");
        artifacts(index).id = string(scenario.id);
        started = tic;
        try
            localLoadNativeInputs(inputScript);
            localApplyScenario(scenario);
            simOut = sim(model, "ReturnWorkspaceOutputs", "on", ...
                "StopTime", string(scenarioContract.simulation.stop_time_s));
            logs = localGetLogs(simOut);
            [signals, metrics] = localExtractNativeSignals(logs, scenario);
            rows(index).simulation_pass = true;
            rows(index).sample_count = numel(signals.time_s);
            rows(index).end_time_s = signals.time_s(end);
            rows(index).time_coverage_pass = ...
                signals.time_s(1) <= 0.05 && ...
                signals.time_s(end) >= ...
                    double(scenarioContract.simulation.stop_time_s) - 0.1;
            rows(index).required_evidence_pass = ...
                rows(index).sample_count >= 20 && ...
                all(isfinite(localNumericValues(signals)));
            rows(index).valid = rows(index).time_coverage_pass && ...
                rows(index).required_evidence_pass;
            rows(index).metrics = metrics;
            artifacts(index).signals = signals;
        catch ME
            rows(index).simulation_pass = false;
            rows(index).valid = false;
            rows(index).error = localError(ME);
        end
        rows(index).wall_clock_seconds = toc(started);
    end
    evidence.scenarios = rows;

    rawPath = fullfile(outDir, "raw_evidence.mat");
    save(rawPath, "artifacts", "-v7.3");
    evidence.raw_artifact = struct( ...
        "path", string(rawPath), ...
        "format", "MAT-v7.3", ...
        "variable", "artifacts");
catch ME
    evidence.errors.session = localError(ME);
end

localCloseModel(model);
localCloseProject(project);
evidence.model_closed_without_save = ...
    strlength(model) == 0 || ~bdIsLoaded(model);
evidence.runtime_model_file_presence_after = localFilePresenceFile(modelPath);
evidence.reference_model_file_presence_after = localFilePresenceFile(referenceModelPath);
evidence.binding_preserved = ...
    evidence.runtime_model_file_presence_after == modelPresenceBefore && ...
    evidence.reference_model_file_presence_after == referenceModelPresenceBefore;
evidence.finished_at = localNow;
evidencePath = fullfile(outDir, "evidence.json");
localWriteJson(evidencePath, evidence);
fprintf("F90_XFLUID03_REFERENCE_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    localValidCount(evidence.scenarios), numel(evidence.scenarios), ...
    evidencePath);
end

function localLoadNativeInputs(inputScript)
escaped = replace(string(inputScript), "'", "''");
evalin("base", "run('" + escaped + "')");
end

function localApplyScenario(scenario)
engine = evalin("base", "engine");
pump = evalin("base", "pump");
implement = evalin("base", "implement");
tire = evalin("base", "tire");

engine.upperLimit = double(scenario.engine_speed_rpm);
pump.initialDisplacement = double(scenario.pump_displacement_cm3_rev);
implement.depth1Tillage = double(scenario.implement_depth_cm);
implement.depth2Tillage = double(scenario.implement_depth_cm);
tire.tc = double(scenario.soil_cohesion_kpa);

assignin("base", "engine", engine);
assignin("base", "pump", pump);
assignin("base", "implement", implement);
assignin("base", "tire", tire);
assignin("base", "engine_speed_rpm", ...
    double(scenario.engine_speed_rpm));
assignin("base", "pump_displacement_cm3_rev", ...
    double(scenario.pump_displacement_cm3_rev));
assignin("base", "implement_depth_cm", ...
    double(scenario.implement_depth_cm));
assignin("base", "soil_cohesion_kpa", ...
    double(scenario.soil_cohesion_kpa));
end

function logs = localGetLogs(simOut)
logs = [];
names = string(simOut.who);
preferred = ["logsoutTractorEnergyComputation", "logsout"];
for key = preferred
    if any(names == key)
        logs = simOut.get(key);
        break
    end
end
if isempty(logs)
    for key = preferred
        try
            logs = evalin("base", key);
            if ~isempty(logs), break; end
        catch
        end
    end
end
assert(~isempty(logs) && numElements(logs) >= 1, ...
    "SimuVerity:F90:XFLUID03:LogsMissing", ...
    "The native logged bus was not returned.");
end

function [signals, metrics] = localExtractNativeSignals(logs, scenario)
values = logs{1}.Values;
engine = localSeries(values, ["Engine", "engineSpeed"]);
pumpDisp = localSeries(values, ["Pump_Displacement"]);
pumpTorque = localSeries(values, ...
    ["Transmission", "Main_Pump", "trq__N_m_"]);
pumpFlow = localSeries(values, ...
    ["Transmission", "Main_Pump", "q__m_3_s_"]);
frontSpeed = localSeries(values, ...
    ["Transmission", "Front_Motor", "w__rpm_"]);
frontTorque = localSeries(values, ...
    ["Transmission", "Front_Motor", "trq__N_m_"]);
frontFlow = localSeries(values, ...
    ["Transmission", "Front_Motor", "q__m_3_s_"]);
rearSpeed = localSeries(values, ...
    ["Transmission", "Rear_Motor", "w__rpm_"]);
rearTorque = localSeries(values, ...
    ["Transmission", "Rear_Motor", "trq__N_m_"]);
rearFlow = localSeries(values, ...
    ["Transmission", "Rear_Motor", "q__m_3_s_"]);
pA1 = localSeries(values, ["Transmission", "Pipe_A", "pA__bar_"]);
pB1 = localSeries(values, ["Transmission", "Pipe_A", "pB__bar_"]);
pA2 = localSeries(values, ["Transmission", "Pipe_B", "pA__bar_"]);
pB2 = localSeries(values, ["Transmission", "Pipe_B", "pB__bar_"]);
tractorSpeed = localSeries(values, ["Tractor_Velocity"]);
implementDepth = localSeries(values, ...
    ["Controller", "Implement_Depth_Command"]);

t = double(engine.time(:));
assert(numel(t) >= 20, "SimuVerity:F90:XFLUID03:Samples", ...
    "The native log has insufficient samples.");
interpolate = @(series) localInterp(series, t);
engineRpm = interpolate(engine);
pumpDispValue = interpolate(pumpDisp);
pumpTorqueValue = interpolate(pumpTorque);
pumpFlowValue = interpolate(pumpFlow);
frontSpeedValue = interpolate(frontSpeed);
frontTorqueValue = interpolate(frontTorque);
frontFlowValue = interpolate(frontFlow);
rearSpeedValue = interpolate(rearSpeed);
rearTorqueValue = interpolate(rearTorque);
rearFlowValue = interpolate(rearFlow);
pressureMatrix = [interpolate(pA1), interpolate(pB1), ...
    interpolate(pA2), interpolate(pB2)];
loopHighPressure = max(pressureMatrix, [], 2);
tractorSpeedValue = interpolate(tractorSpeed);
implementDepthValue = interpolate(implementDepth);

signals = struct;
signals.time_s = t;
signals.tractor_state = [engineRpm, tractorSpeedValue, ...
    implementDepthValue, pumpDispValue];
signals.hydraulic_state = [pumpTorqueValue, pumpFlowValue, ...
    loopHighPressure, frontSpeedValue, rearSpeedValue];
signals.drivetrain_effort = [frontTorqueValue, rearTorqueValue, ...
    frontFlowValue, rearFlowValue];

late = t >= max(t(end) - 10, 0.8 * t(end));
assert(nnz(late) >= 5, "SimuVerity:F90:XFLUID03:LateWindow", ...
    "The native log has insufficient late-window samples.");
vehicleFinal = median(tractorSpeedValue(late));
engineFinal = median(engineRpm(late));
pumpDispFinal = median(pumpDispValue(late));
frontSpeedFinal = median(frontSpeedValue(late));
rearSpeedFinal = median(rearSpeedValue(late));
frontTorqueRms = sqrt(mean(frontTorqueValue(late).^2));
rearTorqueRms = sqrt(mean(rearTorqueValue(late).^2));
frontFlowRms = sqrt(mean(frontFlowValue(late).^2));
rearFlowRms = sqrt(mean(rearFlowValue(late).^2));
pressureMax = max(loopHighPressure);
inputPowerKw = abs(engineRpm * (2*pi/60) .* pumpTorqueValue) / 1000;
frontPowerKw = ...
    abs(frontSpeedValue * (2*pi/60) .* frontTorqueValue) / 1000;
rearPowerKw = ...
    abs(rearSpeedValue * (2*pi/60) .* rearTorqueValue) / 1000;
outputPowerKw = frontPowerKw + rearPowerKw;
lateInputPower = mean(inputPowerKw(late));
lateOutputPower = mean(outputPowerKw(late));
efficiency = lateOutputPower / max(lateInputPower, eps);
lossPowerKw = max(lateInputPower - lateOutputPower, 0);
targetVehicle = max(abs(vehicleFinal), eps);
riseTime = localRiseTime(t, abs(tractorSpeedValue), 0.90 * targetVehicle);
lateVehicleCv = std(tractorSpeedValue(late)) / ...
    max(abs(mean(tractorSpeedValue(late))), 1e-6);
axleSpeedMismatch = abs(frontSpeedFinal - rearSpeedFinal) / ...
    max(max(abs([frontSpeedFinal rearSpeedFinal])), 1e-6);
axleTorqueMismatch = abs(frontTorqueRms - rearTorqueRms) / ...
    max(max(abs([frontTorqueRms rearTorqueRms])), 1e-6);
axleFlowMismatch = abs(frontFlowRms - rearFlowRms) / ...
    max(max(abs([frontFlowRms rearFlowRms])), 1e-9);

metrics = struct( ...
    "requested_engine_speed_rpm", double(scenario.engine_speed_rpm), ...
    "requested_pump_displacement_cm3_rev", ...
        double(scenario.pump_displacement_cm3_rev), ...
    "requested_implement_depth_cm", ...
        double(scenario.implement_depth_cm), ...
    "requested_soil_cohesion_kpa", ...
        double(scenario.soil_cohesion_kpa), ...
    "final_engine_speed_rpm", engineFinal, ...
    "final_pump_displacement_cm3_rev", pumpDispFinal, ...
    "final_implement_depth_cm", median(implementDepthValue(late)), ...
    "final_tractor_speed_kph", vehicleFinal, ...
    "minimum_tractor_speed_kph", min(tractorSpeedValue), ...
    "maximum_loop_pressure_bar", pressureMax, ...
    "late_mean_input_power_kw", lateInputPower, ...
    "late_mean_output_power_kw", lateOutputPower, ...
    "late_transmission_loss_kw", lossPowerKw, ...
    "late_energy_efficiency", efficiency, ...
    "front_motor_speed_rpm", frontSpeedFinal, ...
    "rear_motor_speed_rpm", rearSpeedFinal, ...
    "front_motor_torque_rms_nm", frontTorqueRms, ...
    "rear_motor_torque_rms_nm", rearTorqueRms, ...
    "front_motor_flow_rms_m3_s", frontFlowRms, ...
    "rear_motor_flow_rms_m3_s", rearFlowRms, ...
    "axle_speed_relative_mismatch", axleSpeedMismatch, ...
    "axle_torque_relative_mismatch", axleTorqueMismatch, ...
    "axle_flow_relative_mismatch", axleFlowMismatch, ...
    "cold_start_rise_time_s", riseTime, ...
    "late_vehicle_speed_cv", lateVehicleCv, ...
    "negative_vehicle_speed_fraction", ...
        mean(tractorSpeedValue < -0.05), ...
    "finite_fraction", mean(isfinite([signals.tractor_state, ...
        signals.hydraulic_state, signals.drivetrain_effort]), "all"));
end

function series = localSeries(root, tokens)
value = root;
for index = 1:numel(tokens)
    value = localField(value, tokens(index));
end
assert(isa(value, "timeseries"), "SimuVerity:F90:XFLUID03:SignalType", ...
    "Native signal %s is not a timeseries.", strjoin(tokens, "."));
data = squeeze(double(value.Data));
if size(data, 2) > 1
    data = data(:,1);
end
series = struct("time", double(value.Time(:)), "data", data(:));
end

function value = localField(parent, requested)
names = string(fieldnames(parent));
target = localNorm(requested);
normal = arrayfun(@localNorm, names);
match = find(normal == target, 1);
if isempty(match)
    match = find(contains(normal, target) | contains(target, normal), 1);
end
assert(~isempty(match), "SimuVerity:F90:XFLUID03:NativeFieldMissing", ...
    "Native field %s was not found among [%s].", ...
    requested, strjoin(names, ", "));
value = parent.(char(names(match)));
end

function value = localNorm(text)
value = lower(regexprep(string(text), "[^a-zA-Z0-9]", ""));
end

function values = localInterp(series, time)
[uniqueTime, uniqueIndex] = unique(series.time, "stable");
uniqueData = series.data(uniqueIndex);
if numel(uniqueTime) == 1
    values = repmat(uniqueData, numel(time), 1);
else
    values = interp1(uniqueTime, uniqueData, time, "linear", "extrap");
end
values = double(values(:));
end

function rise = localRiseTime(time, values, threshold)
hit = find(values >= threshold, 1, "first");
if isempty(hit)
    rise = time(end);
else
    rise = time(hit);
end
end

function values = localNumericValues(signals)
values = [signals.time_s(:); signals.tractor_state(:); ...
    signals.hydraulic_state(:); signals.drivetrain_effort(:)];
end

function audit = localStaticAudit(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
text = lower(blocks);
audit = struct;
audit.block_count = numel(blocks);
audit.hydrostatic_cvt_count = sum(contains(text, "hydrostatic cvt"));
audit.pump_path_count = sum(contains(text, "pump"));
audit.motor_path_count = sum(contains(text, "motor"));
audit.pressure_protection_count = sum(contains(text, "relief") | ...
    contains(text, "check valve"));
audit.pipe_path_count = sum(contains(text, "pipe"));
audit.tire_path_count = sum(contains(text, "tire"));
audit.implement_path_count = sum(contains(text, "implement"));
audit.vehicle_body_path_count = sum(contains(text, "vehicle body") | ...
    contains(text, "tractor body"));
audit.front_drive_signature = any(contains(text, "front motor")) && ...
    any(contains(text, "front axle"));
audit.rear_drive_signature = any(contains(text, "rear motor")) && ...
    any(contains(text, "rear axle"));
audit.causal_hydro_mechanical_signature = ...
    audit.hydrostatic_cvt_count >= 1 && ...
    audit.pump_path_count >= 2 && audit.motor_path_count >= 2 && ...
    audit.pressure_protection_count >= 2 && ...
    audit.front_drive_signature && audit.rear_drive_signature && ...
    audit.tire_path_count >= 4 && audit.implement_path_count >= 1 && ...
    audit.vehicle_body_path_count >= 1;
audit.required_products = ["Simulink", "Simscape", ...
    "Simscape Driveline", "Simscape Fluids"];
products = ver;
installed = string({products.Name});
audit.required_products_available = all(ismember( ...
    audit.required_products, installed));
end

function localConfigureIsolation
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache) > 0 && strlength(codegen) > 0, ...
    "SimuVerity:F90:XFLUID03:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", ...
    "CacheFolder", cache, "CodeGenFolder", codegen, ...
    "createDir", true);
end

function value = localRuntime(generationRunId)
value = struct( ...
    "generation_run_id", generationRunId, ...
    "matlab_release", string(version("-release")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "localappdata", string(getenv("LOCALAPPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));
end

function count = localValidCount(rows)
if isempty(rows) || ~isfield(rows, "valid")
    count = 0;
else
    count = sum([rows.valid]);
end
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "time_coverage_pass", false, ...
    "required_evidence_pass", false, ...
    "valid", false, ...
    "sample_count", 0, ...
    "end_time_s", 0, ...
    "wall_clock_seconds", 0, ...
    "metrics", struct, ...
    "error", struct);
end

function localRestoreInit(model, originalInit)
try
    if bdIsLoaded(model)
        set_param(model, "InitFcn", originalInit);
    end
catch
end
end

function localCloseModel(model)
try
    if strlength(model) > 0 && bdIsLoaded(model)
        close_system(model, 0);
    end
catch
end
end

function localCloseProject(project)
try
    if ~isempty(project)
        close(project);
    end
catch
end
end

function payload = localError(ME)
payload = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path, payload)
text = jsonencode(payload, "PrettyPrint", true);
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XFLUID03:Write", "Cannot write %s.", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", text);
end

function binding = localFilePresenceFile(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

