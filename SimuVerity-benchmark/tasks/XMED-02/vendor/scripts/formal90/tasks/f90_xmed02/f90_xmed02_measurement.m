function result = f90_xmed02_measurement(modelPath, outputDir)
%F90_XMED02_SCORE Dedicated multi-scenario physical scorer.

task = f90_xmed02_definition();
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = fullfile(pwd, task.target_model_file);
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(fileparts(modelPath), "f90_xmed02_score");
end
if ~isfolder(outputDir), mkdir(outputDir); end

reasons = strings(0, 1);
scenarioRows = repmat(localEmptyScenario(), 0, 1);
audit = struct("valid", false, "score", 0, ...
    "core_mechanism_ok", false);

if ~isfile(modelPath)
    reasons(end + 1, 1) = "missing_model";
    result = localFinalize(false, audit, scenarioRows, reasons, ...
        task, modelPath);
    localWriteJson(fullfile(outputDir, "receipt.json"), result);
    return;
end

[~, model] = fileparts(modelPath);
oldDir = pwd;
oldPath = path;
cleanup = onCleanup(@() localCleanup(model, oldDir, oldPath));
try
    localAssignScenario(task.scenarios(1));
    load_system(modelPath);
    set_param(model, "SimulationCommand", "update");
catch exception
    reasons(end + 1, 1) = "load_update_compile_failed:" + ...
        string(exception.identifier);
    result = localFinalize(false, audit, scenarioRows, reasons, ...
        task, modelPath);
    localWriteJson(fullfile(outputDir, "receipt.json"), result);
    return;
end

try
    audit = f90_xmed02_static_audit_core(model);
catch exception
    audit = struct("valid", false, "score", 0, ...
        "core_mechanism_ok", false, ...
        "error", string(exception.identifier));
    reasons(end + 1, 1) = "static_audit_failed:" + ...
        string(exception.identifier);
end
if ~localGetBool(audit, "core_mechanism_ok", false)
    reasons(end + 1, 1) = "missing_or_unproved_core_physical_feedback_mechanism";
    result = localFinalize(false, audit, scenarioRows, reasons, ...
        task, modelPath);
    localWriteJson(fullfile(outputDir, "receipt.json"), result);
    fprintf("F90_XMED02_SCORE G=0 score=0 static_core_failed\n");
    return;
end

for index = 1:numel(task.scenarios)
    scenario = task.scenarios(index);
    row = localEmptyScenario();
    row.id = scenario.id;
    try
        localAssignScenario(scenario);
        set_param(model, "StopTime", char(string(task.stop_time_s)), ...
            "ReturnWorkspaceOutputs", "on");
        runStart = tic;
        output = sim(model);
        row.runtime_s = toc(runStart);
        pressure = localTimeseries(output, "pressure_state", 3, ...
            task.stop_time_s, task.windows.minimum_samples);
        flow = localTimeseries(output, "flow_state", 3, ...
            task.stop_time_s, task.windows.minimum_samples);
        command = localTimeseries(output, "pump_command", 1, ...
            task.stop_time_s, task.windows.minimum_samples);
        row.interface_valid = pressure.valid && flow.valid && ...
            command.valid;
        row.interface_reasons = [pressure.reasons; flow.reasons; ...
            command.reasons];
        if row.interface_valid
            row.metrics = localScenarioMetrics( ...
                scenario, task, pressure, flow, command);
            row.M = row.metrics.M;
            row.Q = row.metrics.Q;
            row.R = row.metrics.R;
            row.D = row.metrics.D;
            row.valid = all(isfinite([row.M row.Q row.R row.D]));
        end
    catch exception
        row.error_id = string(exception.identifier);
        row.error_message = string(exception.message);
        row.valid = false;
    end
    if ~row.valid
        reasons(end + 1, 1) = "scenario_failed:" + row.id;
    end
    scenarioRows(end + 1, 1) = row; %#ok<AGROW>
end

gate = localGetBool(audit, "core_mechanism_ok", false) && ...
    numel(scenarioRows) == numel(task.scenarios) && ...
    all([scenarioRows.valid]);
result = localFinalize(gate, audit, scenarioRows, reasons, task, modelPath);
localWriteJson(fullfile(outputDir, "receipt.json"), result);
fprintf("F90_XMED02_SCORE G=%d score=%.6f A=%.6f Q=%.6f M=%.6f R=%.6f D=%.6f\n", ...
    result.G, result.score, result.A, result.Q, result.M, result.R, result.D);
end

function row = localEmptyScenario()
row = struct("id", "", "valid", false, "runtime_s", NaN, ...
    "interface_valid", false, "interface_reasons", strings(0, 1), ...
    "M", NaN, "Q", NaN, "R", NaN, "D", NaN, ...
    "metrics", struct(), "error_id", "", "error_message", "");
end

function result = localFinalize(gate, audit, rows, reasons, task, modelPath)
result = struct();
result.schema = "simuverity.formal90-xmed02-score.v1";
result.task_id = task.task_id;
result.policy_id = task.policy_id;
result.model_path = string(modelPath);
result.matlab_release = string(version("-release"));
result.G = logical(gate);
result.A = min(max(localGetNumber(audit, "score", 0), 0), 1);
if isempty(rows) || ~all([rows.valid])
    result.Q = 0;
    result.M = 0;
    result.R = 0;
    result.D = 0;
else
    result.Q = min([rows.Q]);
    result.M = min([rows.M]);
    result.R = min([rows.R]);
    result.D = min([rows.D]);
end
result.weights = task.weights;
if gate
    result.score = 100 * ...
        result.A ^ task.weights.A * ...
        result.Q ^ task.weights.Q * ...
        result.M ^ task.weights.M * ...
        result.R ^ task.weights.R * ...
        result.D ^ task.weights.D;
else
    result.score = 0;
end
result.formula = ...
    "G*100*A^0.15*Q^0.10*M^0.30*R^0.20*D^0.25";
result.multi_scenario_policy = ...
    "Each score-bearing group uses the worst official scenario.";
result.static_audit = audit;
result.scenarios = rows;
result.failure_reasons = unique(reasons);
end

function localAssignScenario(scenario)
names = string(fieldnames(scenario));
for index = 1:numel(names)
    name = char(names(index));
    if strcmp(name, "id"), continue; end
    assignin("base", name, scenario.(name));
end
end

function signal = localTimeseries(output, variable, channels, stopTime, minSamples)
signal = struct("valid", false, "reasons", strings(0, 1), ...
    "time", zeros(0, 1), "data", zeros(0, channels));
try
    value = output.get(variable);
catch
    signal.reasons(end + 1, 1) = "missing_" + variable;
    return;
end
if ~isa(value, "timeseries")
    signal.reasons(end + 1, 1) = variable + "_not_timeseries";
    return;
end
time = double(value.Time(:));
data = squeeze(double(value.Data));
if isvector(data), data = data(:); end
if size(data, 1) ~= numel(time) && size(data, 2) == numel(time)
    data = data.';
end
if size(data, 1) ~= numel(time)
    signal.reasons(end + 1, 1) = variable + "_time_data_mismatch";
elseif size(data, 2) ~= channels
    signal.reasons(end + 1, 1) = variable + "_wrong_channel_count";
elseif numel(time) < minSamples
    signal.reasons(end + 1, 1) = variable + "_too_few_samples";
elseif isempty(time) || time(1) > 1e-6 || time(end) < stopTime - 0.02
    signal.reasons(end + 1, 1) = variable + "_incomplete_time_coverage";
elseif any(diff(time) <= 0)
    signal.reasons(end + 1, 1) = variable + "_nonmonotonic_time";
elseif ~all(isfinite(data), "all")
    signal.reasons(end + 1, 1) = variable + "_nonfinite_data";
else
    signal.valid = true;
end
signal.time = time;
signal.data = data;
end

function metrics = localScenarioMetrics(scenario, task, pressure, flow, command)
dt = 0.002;
grid = (0:dt:task.stop_time_s).';
p = interp1(pressure.time, pressure.data, grid, "linear", "extrap");
f = interp1(flow.time, flow.data, grid, "linear", "extrap");
u = interp1(command.time, command.data, grid, "linear", "extrap");

period = 60 / scenario.heart_rate_bpm;
windowSamples = max(3, round(period / dt));
map = movmean(p(:, 1), [windowSamples - 1, 0]);
preMask = grid >= max(period, scenario.target_step_time_s - ...
    task.windows.pre_step_tail_s) & ...
    grid <= scenario.target_step_time_s - 0.10;
postMask = grid >= task.stop_time_s - task.windows.post_step_tail_s;
assert(any(preMask) && any(postMask), "SimuVerity:F90:XMED02:ScoreWindow", ...
    "Official scoring windows are empty.");

mapInitial = mean(map(preMask));
mapFinal = mean(map(postMask));
initialError = abs(mapInitial - scenario.target_map_initial_mmHg);
finalError = abs(mapFinal - scenario.target_map_final_mmHg);
initialQ = localDescending(initialError, [1 2 4 8 15], ...
    [1 0.92 0.70 0.30 0]);
finalQ = localDescending(finalError, [1 2 4 8 15], ...
    [1 0.92 0.70 0.30 0]);
M = min(initialQ, finalQ);

tailPeriod = grid >= task.stop_time_s - period;
pulsePressure = max(p(tailPeriod, 1)) - min(p(tailPeriod, 1));
cvpMean = mean(p(postMask, 2));
papMean = mean(p(postMask, 3));
systemicFlow = mean(f(postMask, 2));
pulmonaryFlow = mean(f(postMask, 3));
ecmoMean = mean(f(postMask, 1));
flowBalance = abs(systemicFlow - pulmonaryFlow - ecmoMean) / ...
    max(mean(abs([systemicFlow pulmonaryFlow + ecmoMean])), 1);
heartRateEstimate = localHeartRateEstimate(grid, p(:, 1), ...
    scenario.heart_rate_bpm);
heartRateError = abs(heartRateEstimate - scenario.heart_rate_bpm);

qPulse = localPlateau(pulsePressure, [8 15 65 90]);
qCvp = localPlateau(cvpMean, [0 1 10 18]);
qPap = localPlateau(papMean, [5 10 35 55]);
qBalance = localDescending(flowBalance, [0.10 0.20 0.40 0.80], ...
    [1 0.9 0.5 0]);
qHeartRate = localDescending(heartRateError, [1 3 7 15], ...
    [1 0.9 0.5 0]);
Q = mean([qPulse qCvp qPap qBalance qHeartRate]);

commandInitialMean = mean(u(preMask));
commandFinalMean = mean(u(postMask));
negativeFraction = mean(f(:, 1) < -1e-5);
forwardQ = min(localAscending(ecmoMean, [0 2 8], [0 0.7 1]), ...
    localDescending(negativeFraction, [0 0.001 0.02 0.10], ...
    [1 0.9 0.4 0]));
flowRangeQ = mean([ ...
    localPlateau(systemicFlow, [5 20 150 250]), ...
    localPlateau(pulmonaryFlow, [5 20 150 250])]);
commandWithinLimit = all(u >= -1e-6 & ...
    u <= scenario.pump_speed_limit_rpm + 1e-6);
saturationFraction = mean(u >= 0.995 * scenario.pump_speed_limit_rpm);
authorityQ = double(commandWithinLimit) * ...
    localDescending(saturationFraction, [0.30 0.60 0.85 1.0], ...
    [1 0.9 0.4 0]);
physiologyQ = mean([qCvp qPap qPulse]);
R = mean([forwardQ flowRangeQ authorityQ physiologyQ]);

targetAfter = scenario.target_map_final_mmHg;
afterMask = grid >= scenario.target_step_time_s;
afterTime = grid(afterMask);
afterError = abs(map(afterMask) - targetAfter);
lastBad = find(afterError > 3, 1, "last");
if isempty(lastBad)
    settlingTime = 0;
elseif lastBad < numel(afterTime)
    settlingTime = afterTime(lastBad + 1) - scenario.target_step_time_s;
else
    settlingTime = Inf;
end
settlingQ = localDescending(settlingTime, [0.8 1.4 2.3 3.5], ...
    [1 0.9 0.5 0]);
if scenario.target_map_final_mmHg > scenario.target_map_initial_mmHg
    overshoot = max(0, max(map(afterMask)) - targetAfter);
elseif scenario.target_map_final_mmHg < scenario.target_map_initial_mmHg
    overshoot = max(0, targetAfter - min(map(afterMask)));
else
    overshoot = max(abs(map(afterMask) - targetAfter));
end
overshootQ = localDescending(overshoot, [2 4 8 15], ...
    [1 0.9 0.5 0]);
beforeMask = grid < scenario.target_step_time_s;
beforeTime = grid(beforeMask);
beforeError = abs(map(beforeMask) - scenario.target_map_initial_mmHg);
lastInitialBad = find(beforeError > 3, 1, "last");
if isempty(lastInitialBad)
    initialSettlingTime = 0;
elseif lastInitialBad < numel(beforeTime)
    initialSettlingTime = beforeTime(lastInitialBad + 1);
else
    initialSettlingTime = Inf;
end
initialSettlingQ = localDescending(initialSettlingTime, ...
    [0.8 1.2 1.8 2.5], [1 0.9 0.5 0]);
D = mean([settlingQ overshootQ initialSettlingQ]);

metrics = struct( ...
    "M", M, "Q", Q, "R", R, "D", D, ...
    "map_initial_mmHg", mapInitial, ...
    "map_final_mmHg", mapFinal, ...
    "initial_error_mmHg", initialError, ...
    "final_error_mmHg", finalError, ...
    "pulse_pressure_mmHg", pulsePressure, ...
    "cvp_mean_mmHg", cvpMean, ...
    "pap_mean_mmHg", papMean, ...
    "ecmo_flow_mean_cm3_s", ecmoMean, ...
    "command_initial_mean_rpm", commandInitialMean, ...
    "command_final_mean_rpm", commandFinalMean, ...
    "systemic_flow_mean_cm3_s", systemicFlow, ...
    "pulmonary_flow_mean_cm3_s", pulmonaryFlow, ...
    "flow_balance_fraction", flowBalance, ...
    "heart_rate_estimate_bpm", heartRateEstimate, ...
    "heart_rate_error_bpm", heartRateError, ...
    "pump_saturation_fraction", saturationFraction, ...
    "settling_time_s", settlingTime, ...
    "overshoot_mmHg", overshoot, ...
    "initial_settling_time_s", initialSettlingTime, ...
    "subscores", struct( ...
        "initial_tracking", initialQ, "final_tracking", finalQ, ...
        "pulse_pressure", qPulse, "cvp", qCvp, "pap", qPap, ...
        "flow_balance", qBalance, "heart_rate", qHeartRate, ...
        "forward_ecmo_flow", forwardQ, "flow_range", flowRangeQ, ...
        "command_authority", authorityQ, "settling", settlingQ, ...
        "overshoot", overshootQ, ...
        "initial_establishment", initialSettlingQ));
end

function bpm = localHeartRateEstimate(time, signal, expectedBpm)
mask = time >= max(time(end) - 4.5, time(1) + 0.5);
t = time(mask);
y = signal(mask);
if numel(y) < 20
    bpm = NaN;
    return;
end
dt = median(diff(t));
y = detrend(y, 1);
expectedPeriod = 60 / expectedBpm;
minimumLag = max(2, round(0.75 * expectedPeriod / dt));
maximumLag = min(numel(y) - 2, round(1.25 * expectedPeriod / dt));
if maximumLag <= minimumLag
    bpm = NaN;
    return;
end
scores = -Inf(maximumLag - minimumLag + 1, 1);
for lag = minimumLag:maximumLag
    left = y(1:end-lag);
    right = y(1+lag:end);
    denominator = sqrt(sum(left .^ 2) * sum(right .^ 2));
    if denominator > 0
        scores(lag - minimumLag + 1) = ...
            sum(left .* right) / denominator;
    end
end
[~, bestIndex] = max(scores);
bestLag = minimumLag + bestIndex - 1;
if bestIndex > 1 && bestIndex < numel(scores)
    leftScore = scores(bestIndex - 1);
    centerScore = scores(bestIndex);
    rightScore = scores(bestIndex + 1);
    curvature = leftScore - 2 * centerScore + rightScore;
    if isfinite(curvature) && abs(curvature) > eps
        bestLag = bestLag + 0.5 * ...
            (leftScore - rightScore) / curvature;
    end
end
bpm = 60 / (bestLag * dt);
end

function score = localDescending(value, anchors, scores)
if ~isfinite(value)
    score = 0;
elseif value <= anchors(1)
    score = scores(1);
elseif value >= anchors(end)
    score = scores(end);
else
    score = interp1(anchors, scores, value, "linear");
end
score = min(max(score, 0), 1);
end

function score = localAscending(value, anchors, scores)
if ~isfinite(value)
    score = 0;
elseif value <= anchors(1)
    score = scores(1);
elseif value >= anchors(end)
    score = scores(end);
else
    score = interp1(anchors, scores, value, "linear");
end
score = min(max(score, 0), 1);
end

function score = localPlateau(value, bounds)
if ~isfinite(value) || value <= bounds(1) || value >= bounds(4)
    score = 0;
elseif value >= bounds(2) && value <= bounds(3)
    score = 1;
elseif value < bounds(2)
    score = (value - bounds(1)) / (bounds(2) - bounds(1));
else
    score = (bounds(4) - value) / (bounds(4) - bounds(3));
end
score = min(max(score, 0), 1);
end

function value = localGetNumber(source, field, fallback)
value = fallback;
if isstruct(source) && isfield(source, field)
    candidate = double(source.(field));
    if isscalar(candidate) && isfinite(candidate), value = candidate; end
end
end

function value = localGetBool(source, field, fallback)
value = fallback;
if isstruct(source) && isfield(source, field)
    candidate = source.(field);
    if isscalar(candidate), value = logical(candidate); end
end
end

function localWriteJson(path, value)
fid = fopen(path, "w");
assert(fid >= 0, "SimuVerity:F90:XMED02:WriteScore", "Cannot write %s.", path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleanup;
end

function localCleanup(model, oldDir, oldPath)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
try, cd(oldDir); catch, end
try, path(oldPath); catch, end
end

