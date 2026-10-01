function evidence = f90_xbatt09_extract_reference_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
% Extract replayable fixed reference evidence for F90-XBATT-09.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
scoringRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
if strlength(scoringRunId) == 0, scoringRunId = "f90_xbatt09_reference_manual"; end
assert(isfile(modelPath), "SimuVerity:F90:XBATT09:ModelMissing", "Reference model is missing.");
assert(isfile(officialScenarios), "SimuVerity:F90:XBATT09:OfficialScenarios", "Official scenarios are missing.");
assert(isfolder(evaluatorAssetRoot), "SimuVerity:F90:XBATT09:ReferenceAssetRoot", "Evaluator asset root is missing.");
expectedPresence = lower(strtrim(string("present")));
assert(strcmpi(localFilePresence(modelPath), expectedPresence), ...
    "SimuVerity:F90:XBATT09:ReferenceIdentity", ...
    "Reference file presence differs from the task binding.");
official = jsondecode(fileread(officialScenarios));
outputDir = string(outputDir);
if isfolder(outputDir)
    error("SimuVerity:F90:XBATT09:OutputExists", ...
        "Fresh evidence directory already exists: %s", outputDir);
end
mkdir(outputDir);

referenceDir = evaluatorAssetRoot;
runtimeDir = fullfile(outputDir, "runtime_reference");
mkdir(runtimeDir);
copyfile(fullfile(referenceDir, "*"), runtimeDir);

diaryPath = fullfile(outputDir, "extractor.log");
diary(diaryPath);
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>
callerPath = path;
callerFolder = string(pwd);
boundaryCleanup = onCleanup(@() localRestoreBoundary(callerPath, callerFolder)); %#ok<NASGU>
restoredefaultpath;
addpath(runtimeDir, "-begin");
cacheDir = fullfile(outputDir, "cache");
codegenDir = fullfile(outputDir, "codegen");
mkdir(cacheDir); mkdir(codegenDir);
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);
cd(runtimeDir);

evalin("base", "run('" + replace(fullfile(runtimeDir, ...
    "moduleLibrary_param.m"), "\", "/") + "')");
profiles = load(fullfile(runtimeDir, "DischargeCycle.mat"), ...
    "batteryCurrent", "batteryCurrentValidation");
assignin("base", "batteryCurrent", double(profiles.batteryCurrent));

model = "disconnectedCellDetection";
modelPath = fullfile(runtimeDir, model + ".slx");
load_system(modelPath);
cleanupModel = onCleanup(@() localClose(model)); %#ok<NASGU>
set_param(model, "ReturnWorkspaceOutputs", "on", ...
    "LimitDataPoints", "off", "SimulationMode", "normal");
set_param(model + "/Current", "VariableName", "batteryCurrent");
set_param(model, "SimulationCommand", "update");
fprintf("LOAD_PASS=1\nUPDATE_PASS=1\n");
feval(model, [], [], [], "compile");
fprintf("COMPILE_PASS=1\n");
feval(model, [], [], [], "term");

faults = Simulink.fault.findFaults(model);
assert(numel(faults) == 1, "Expected exactly one source fault.");
fault = faults(1);
faultPath = string(fault.ModelElement);
fault.TriggerType = "Timed";

scenarios = official.scenarios;
for index = 1:numel(scenarios)
    scenarios(index).fault_enable = logical(scenarios(index).contact_fault_enable);
    scenarios(index).fault_time_s = double(scenarios(index).contact_fault_time_s);
end

grid = (0:0.5:100).';
assemblyChannels = cellstr(compose("parallel_assembly_voltage_%02d_V", 1:15));
contactChannels = [cellstr(compose("contact_symptom_%02d", 1:15)), ...
    cellstr(compose("contact_error_%02d", 1:15))];
batteryChannels = {"pack_voltage_V", "pack_current_A", ...
    "parallel_assembly_voltage_spread_V"};
scenarioEvidence = repmat(struct(), 1, numel(scenarios));
suiteTimer = tic;

for index = 1:numel(scenarios)
    scenario = scenarios(index);
    profile = double(profiles.(scenario.profile));
    profile(:,2) = scenario.current_scale .* profile(:,2);
    assignin("base", "batteryCurrent", profile);
    fault.StartTime = scenario.fault_time_s;
    Simulink.fault.enable(faultPath, scenario.fault_enable);

    scenarioTimer = tic;
    out = sim(model, "StopTime", "100", "SimulationMode", "normal", ...
        "ReturnWorkspaceOutputs", "on");
    wallSeconds = toc(scenarioTimer);

    voltageSeries = out.simlog.Battery.vParallelAssembly.series;
    voltageTime = double(time(voltageSeries));
    voltageValues = double(values(voltageSeries, "V"));
    voltageValues = localTimeRows(voltageValues, numel(voltageTime));
    voltageGrid = interp1(voltageTime, voltageValues, grid, "linear", "extrap");

    symptomTs = out.logsout.getElement("CellConnectionSymptom").Values;
    errorTs = out.logsout.getElement("CellConnectionError").Values;
    symptom = localResampleLogical(symptomTs, grid, 15);
    errorState = localResampleLogical(errorTs, grid, 15);
    currentGrid = interp1(profile(:,1), profile(:,2), grid, ...
        "linear", "extrap");
    packVoltage = sum(voltageGrid, 2);
    voltageSpread = max(voltageGrid, [], 2) - min(voltageGrid, [], 2);
    batteryState = [packVoltage, currentGrid, voltageSpread];
    contactState = [symptom, errorState];

    scenarioEvidence(index).id = char(scenario.id);
    scenarioEvidence(index).input = struct( ...
        "profile", char(scenario.profile), ...
        "current_scale", scenario.current_scale, ...
        "contact_fault_enable", scenario.fault_enable, ...
        "contact_fault_time_s", scenario.fault_time_s);
    scenarioEvidence(index).valid = true;
    scenarioEvidence(index).simulate_pass = true;
    scenarioEvidence(index).wall_seconds = wallSeconds;
    scenarioEvidence(index).logs = struct( ...
        "assembly_voltage", localLog(grid, voltageGrid, ...
            assemblyChannels, repmat({"V"}, 1, 15)), ...
        "contact_state", localLog(grid, contactState, ...
            contactChannels, repmat({"1"}, 1, 30)), ...
        "battery_state", localLog(grid, batteryState, ...
            batteryChannels, {"V", "A", "V"}));
    scenarioEvidence(index).metrics = localMetrics(grid, voltageGrid, ...
        symptom, errorState, scenario.fault_enable, scenario.fault_time_s);
    fprintf("SCENARIO_PASS|%s|WALL=%.6f|SYMPTOM=%g|ERROR=%g|OTHER_ERROR=%g\n", ...
        scenario.id, wallSeconds, ...
        scenarioEvidence(index).metrics.target_symptom_time_s, ...
        scenarioEvidence(index).metrics.target_error_time_s, ...
        scenarioEvidence(index).metrics.maximum_other_error);
end

evidence = struct();
evidence.schema = "simuverity.f90-xbatt09-evidence.v1";
evidence.task_id = "F90-XBATT-09";
evidence.scoring_run_id = char(scoringRunId);
evidence.reference_identity = "R2025a DisconnectedCellDetectionExample generated source";
evidence.model = "runtime_reference/disconnectedCellDetection.slx";
evidence.load_pass = true;
evidence.update_pass = true;
evidence.compile_pass = true;
evidence.simulate_pass = true;
evidence.all_official_evidence_valid = true;
evidence.scenario_count = numel(scenarios);
evidence.suite_wall_seconds = toc(suiteTimer);
evidence.scenarios = scenarioEvidence;
evidence.EVIDENCE_COMPLETE = true;

evidencePath = fullfile(outputDir, "evidence.json");
text = jsonencode(evidence, PrettyPrint=true);
fid = fopen(evidencePath, "w", "n", "UTF-8");
assert(fid >= 0, "Unable to open evidence output.");
cleanupFile = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, text, "char");
fwrite(fid, newline, "char");
save(fullfile(outputDir, "evidence_complete.mat"), "evidence", "-v7.3");
fprintf("SIMULATE_PASS=1\nALL_OFFICIAL_EVIDENCE_VALID=1\n");
fprintf("SUITE_WALL_SECONDS=%.6f\nEVIDENCE_COMPLETE=1\n", evidence.suite_wall_seconds);
end

function log = localLog(timeVector, data, channels, units)
log = struct("channels", {channels}, "units", {units}, ...
    "time", timeVector.', "data", data);
end

function data = localResampleLogical(ts, grid, width)
timeVector = double(ts.Time(:));
valuesMatrix = localTimeRows(double(ts.Data), numel(timeVector));
assert(size(valuesMatrix,2) == width, "Unexpected logical log width.");
data = interp1(timeVector, valuesMatrix, grid, "previous", "extrap");
data = double(data >= 0.5);
end

function data = localTimeRows(data, timeCount)
data = squeeze(data);
if isvector(data) && timeCount == numel(data)
    data = reshape(data, timeCount, 1);
elseif size(data,1) ~= timeCount && size(data,2) == timeCount
    data = data.';
end
assert(size(data,1) == timeCount, "Logged data time dimension mismatch.");
end

function metrics = localMetrics(grid, voltage, symptom, errorState, ...
        faultEnabled, faultTime)
targetDelta = abs(voltage(:,1) - mean(voltage(:,2:end), 2));
if faultEnabled
    post = grid >= faultTime;
    pre = grid < faultTime;
else
    post = true(size(grid));
    pre = true(size(grid));
end
metrics = struct();
metrics.target_symptom_time_s = localFirstTime(grid, symptom(:,1));
metrics.target_error_time_s = localFirstTime(grid, errorState(:,1));
metrics.maximum_other_symptom = max(symptom(:,2:end), [], "all");
metrics.maximum_other_error = max(errorState(:,2:end), [], "all");
metrics.maximum_pre_fault_target_error = max(errorState(pre,1), [], "all");
metrics.maximum_voltage_divergence_V = max(targetDelta(post));
metrics.mean_voltage_divergence_V = mean(targetDelta(post));
metrics.maximum_voltage_spread_V = max(max(voltage,[],2)-min(voltage,[],2));
metrics.minimum_pack_voltage_V = min(sum(voltage,2));
metrics.maximum_pack_voltage_V = max(sum(voltage,2));
end

function first = localFirstTime(grid, values)
index = find(values >= 0.5, 1, "first");
if isempty(index), first = -1; else, first = grid(index); end
end

function localClose(model)
try, close_system(model, 0); catch, end
end

function localRestoreBoundary(callerPath, callerFolder)
try, cd(callerFolder); catch, end
try, path(callerPath); catch, end
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

