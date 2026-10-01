function varargout = f90_xrobo01_measurement_compatibility(helperName, varargin)
%f90_xrobo01_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xrobo01_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["execute_scenarios", "empty_row"];
        end
    case "execute_scenarios"
        if nargout == 0
            execute_scenarios(varargin{:});
        else
            [varargout{1:nargout}] = execute_scenarios(varargin{:});
        end
    case "empty_row"
        if nargout == 0
            empty_row(varargin{:});
        else
            [varargout{1:nargout}] = empty_row(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xrobo01_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function [rows, runRows] = execute_scenarios(modelPath, def)
rows = repmat(empty_row, 1, numel(def.scenarios));
runTemplate = struct("id","","stage","not_run","valid",false, ...
    "elapsed_seconds",NaN,"error_identifier","","error_message","");
runRows = repmat(runTemplate, 1, numel(def.scenarios));

bdclose("all");
load_system(modelPath);
[~, modelName] = fileparts(modelPath);
model = string(modelName);
cleanupModel = onCleanup(@() close_if_loaded(model)); %#ok<NASGU>
set_param(model, "ReturnWorkspaceOutputs", "on", ...
    "SolverType", "Variable-step", "Solver", def.sim.solver, ...
    "MaxStep", num2str(def.sim.max_step, 17), ...
    "StartTime", num2str(def.sim.start, 17), ...
    "StopTime", num2str(def.sim.stop, 17));

for k = 1:numel(def.scenarios)
    scenario = def.scenarios(k);
    runRows(k).id = scenario.id;
    timer = tic;
    try
        assign_inputs(scenario.values);
        clear_logged_outputs;
        set_param(model, "SimulationCommand", "update");
        out = sim(model, "StopTime", num2str(def.sim.stop, 17), ...
            "ReturnWorkspaceOutputs", "on");
        rows(k) = extract_row(out, scenario, def);
        runRows(k).stage = "simulated";
        runRows(k).valid = rows(k).valid;
    catch ME
        rows(k).id = scenario.id;
        rows(k).kind = scenario.kind;
        rows(k).pair = scenario.pair;
        rows(k).values = scenario.values;
        rows(k).failure_reason = string(ME.identifier) + ": " + ...
            string(ME.message);
        runRows(k).stage = "candidate_failed";
        runRows(k).error_identifier = string(ME.identifier);
        runRows(k).error_message = string(ME.message);
    end
    runRows(k).elapsed_seconds = toc(timer);
end
end

function row = empty_row
row = struct( ...
    "id","","kind","","pair","","values",struct, ...
    "valid",false,"samples",[0 0 0 0], ...
    "forward_displacement_m",NaN,"progress_ratio",NaN, ...
    "initial_vx_error_fraction",Inf, ...
    "positive_progress_fraction",0,"minimum_body_height_m",NaN, ...
    "vertical_ripple_m",Inf,"lateral_span_m",Inf, ...
    "body_kinematic_error_mps",Inf, ...
    "contact_transition_counts",[0 0 0 0], ...
    "landing_counts",[0 0 0 0], ...
    "contact_duty_fractions",[0 0 0 0], ...
    "contact_gait_mismatch_fraction",Inf, ...
    "diagonal_alternation_count",0,"gait_phase_coverage",0, ...
    "gait_establishment_time_s",Inf, ...
    "bus_voltage_median_v",NaN,"load_current_rms_a",NaN, ...
    "battery_current_rms_a",NaN,"battery_smoothing_ratio",Inf, ...
    "electrical_power_rms_w",NaN,"electrical_dynamic",false, ...
    "failure_reason","");
end

function row = extract_row(out, scenario, def)
required = string({def.outputs.name});
channels = [def.outputs.channels];
series = cell(1, numel(required));
time = cell(1, numel(required));
data = cell(1, numel(required));
for k = 1:numel(required)
    series{k} = simuverity_public_output_compatibility( ...
        out, required(k), channels(k), AllowBaseWorkspace=true);
    [time{k}, data{k}] = series_matrix(series{k}, channels(k));
    assert(numel(time{k}) >= 20 && all(isfinite(time{k})) && ...
        all(isfinite(data{k}), "all"), ...
        "F90_XROBO01_OUTPUT_NONFINITE_OR_SHORT:%s", required(k));
    assert(time{k}(1) <= 1e-9 && ...
        time{k}(end) >= def.sim.stop-1e-6, ...
        "F90_XROBO01_OUTPUT_TIME_COVERAGE:%s", required(k));
end

[tb, body] = unique_time(time{1}, data{1});
[tc, contact] = unique_time(time{2}, data{2});
[tg, gait] = unique_time(time{3}, data{3});
[te, electrical] = unique_time(time{4}, data{4});
assert(numel(tb) >= 20 && numel(tc) >= 20 && ...
    numel(tg) >= 20 && numel(te) >= 20, ...
    "F90_XROBO01_UNIQUE_TIME_SAMPLES");

analysis = tb >= min(0.15, def.sim.stop/10);
x = body(:,1); height = body(:,2); lateral = body(:,3);
vx = body(:,4);
dx = x(end)-x(1);
duration = max(tb(end)-tb(1), eps);
positiveProgress = mean(vx(analysis) > .05);
minimumHeight = min(height(analysis));
verticalRipple = percentile(height(analysis), .95) - ...
    percentile(height(analysis), .05);
lateralSpan = span_value(lateral(analysis));
dxdt = gradient(x, tb);
kinematicError = percentile(abs(dxdt(analysis)-vx(analysis)), .90);

contactBool = contact > .5;
contactTransitions = zeros(1,4);
landingCounts = zeros(1,4);
contactDuty = zeros(1,4);
for j = 1:4
    transitions = diff(contactBool(:,j));
    contactTransitions(j) = nnz(transitions ~= 0);
    landingCounts(j) = nnz(transitions > 0);
    contactDuty(j) = mean(contactBool(:,j));
end
supportOne = contactBool(:,2) | contactBool(:,3);
supportTwo = contactBool(:,4) | contactBool(:,1);
gaitOnContact = interp1(tg, gait, tc, "previous", "extrap");
aerialOne = gaitOnContact(:,1) > .5;
aerialTwo = gaitOnContact(:,2) > .5;
mismatchOne = best_binary_mismatch(~supportOne, aerialOne, tc, .05);
mismatchTwo = best_binary_mismatch(~supportTwo, aerialTwo, tc, .05);
contactGaitMismatch = max(mismatchOne, mismatchTwo);
phase = round(gait(:,3));
phase = phase(isfinite(phase));
phaseCoverage = numel(unique(phase));
[alternations, establishmentTime] = ...
    diagonal_alternation(tc, supportOne, supportTwo);

power = electrical(:,1);
loadCurrent = electrical(:,2);
batteryCurrent = electrical(:,3);
currentFloor = max(.05, .05*rms_value(loadCurrent));
validVoltage = abs(loadCurrent) >= currentFloor;
if nnz(validVoltage) >= 10
    busVoltage = median(abs(power(validVoltage)./loadCurrent(validVoltage)));
else
    busVoltage = NaN;
end
loadAc = rms_value(loadCurrent-mean(loadCurrent));
batteryAc = rms_value(batteryCurrent-mean(batteryCurrent));
batterySmoothing = batteryAc/max(loadAc, 1e-9);
electricalPowerRms = rms_value(power);
electricalDynamic = std(loadCurrent) > 1e-4 && ...
    std(power) > 1e-3 && electricalPowerRms > .1;

row = empty_row;
row.id = scenario.id;
row.kind = scenario.kind;
row.pair = scenario.pair;
row.values = scenario.values;
row.valid = true;
row.samples = [numel(tb),numel(tc),numel(tg),numel(te)];
row.forward_displacement_m = dx;
row.progress_ratio = dx/max( ...
    scenario.values.initial_forward_speed_mps*duration, 1e-9);
row.initial_vx_error_fraction = abs(vx(1)- ...
    scenario.values.initial_forward_speed_mps)/ ...
    max(abs(scenario.values.initial_forward_speed_mps), 1);
row.positive_progress_fraction = positiveProgress;
row.minimum_body_height_m = minimumHeight;
row.vertical_ripple_m = verticalRipple;
row.lateral_span_m = lateralSpan;
row.body_kinematic_error_mps = kinematicError;
row.contact_transition_counts = contactTransitions;
row.landing_counts = landingCounts;
row.contact_duty_fractions = contactDuty;
row.contact_gait_mismatch_fraction = contactGaitMismatch;
row.diagonal_alternation_count = alternations;
row.gait_phase_coverage = phaseCoverage;
row.gait_establishment_time_s = establishmentTime;
row.bus_voltage_median_v = busVoltage;
row.load_current_rms_a = rms_value(loadCurrent);
row.battery_current_rms_a = rms_value(batteryCurrent);
row.battery_smoothing_ratio = batterySmoothing;
row.electrical_power_rms_w = electricalPowerRms;
row.electrical_dynamic = electricalDynamic;
row.failure_reason = "";
end

function assign_inputs(values)
names = fieldnames(values);
for k = 1:numel(names)
    assignin("base", names{k}, values.(names{k}));
end
end

function clear_logged_outputs
% Clear only the four public outputs before each independent scenario.
% This is the task-local helper used by the bundled measurement source;
% it does not alter inputs, model state, thresholds, or performance evidence.
evalin("base", ...
    "clear body_state contact_state gait_state electrical_state");
end

function close_if_loaded(model)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
end

function [time, data] = series_matrix(series, channels)
time = double(series.Time(:));
data = squeeze(double(series.Data));
if isvector(data)
    if channels == 1
        data = data(:);
    elseif numel(time) == 1 && numel(data) == channels
        data = reshape(data, 1, channels);
    end
end
if size(data,1) ~= numel(time) && size(data,2) == numel(time)
    data = data.';
end
assert(size(data,1) == numel(time) && size(data,2) == channels, ...
    "F90_XROBO01_OUTPUT_CHANNEL_COUNT");
end

function [time, data] = unique_time(time, data)
[time, indices] = unique(double(time(:)), "stable");
data = data(indices,:);
end

function mismatch = best_binary_mismatch(reference, candidate, time, maxLag)
reference = logical(reference(:));
candidate = logical(candidate(:));
dt = median(diff(time));
maxShift = max(0, round(maxLag/max(dt,1e-9)));
scores = ones(1,2*maxShift+1);
index = 0;
for shift = -maxShift:maxShift
    index = index+1;
    if shift < 0
        a = reference(1-shift:end);
        b = candidate(1:end+shift);
    elseif shift > 0
        a = reference(1:end-shift);
        b = candidate(1+shift:end);
    else
        a = reference;
        b = candidate;
    end
    if numel(a) >= 10, scores(index) = mean(a ~= b); end
end
mismatch = min(scores);
end

function [count, establishment] = diagonal_alternation(time, one, two)
dominance = double(one)-double(two);
valid = dominance ~= 0;
time = time(valid);
dominance = dominance(valid);
if isempty(dominance)
    count = 0;
    establishment = Inf;
    return;
end
keep = [true; diff(dominance) ~= 0];
eventTime = time(keep);
count = max(0,numel(eventTime)-1);
if count >= 2
    establishment = eventTime(3);
else
    establishment = Inf;
end
end

function value = percentile(values, fraction)
values = sort(double(values(:)));
assert(~isempty(values), "F90_XROBO01_EMPTY_PERCENTILE");
position = 1 + (numel(values)-1)*fraction;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    value = values(lowerIndex);
else
    weight = position-lowerIndex;
    value = values(lowerIndex)*(1-weight)+values(upperIndex)*weight;
end
end

function value = span_value(values)
value = max(values,[],"all")-min(values,[],"all");
end

function value = rms_value(values)
value = sqrt(mean(double(values(:)).^2));
end
