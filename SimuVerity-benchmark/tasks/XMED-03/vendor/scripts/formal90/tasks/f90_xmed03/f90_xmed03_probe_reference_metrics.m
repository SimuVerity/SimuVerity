function receipt = f90_xmed03_probe_reference_metrics(modelPath, outputPath)
%F90_XMED03_PROBE_REFERENCE_METRICS Characterize all official scenarios.

task = f90_xmed03_definition();
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = string(getenv("SIMUVERITY_SEALED_CANDIDATE_PATH"));
end
if nargin < 2 || strlength(string(outputPath)) == 0
    outputPath = fullfile(fileparts(modelPath), ...
        "reference_metric_probe.json");
end
assert(isfile(modelPath), "SimuVerity:F90:XMED03:ProbeModel", ...
    "Reference model is missing.");
[~, model] = fileparts(modelPath);
load_system(modelPath);
cleanup = onCleanup(@() close_system(model, 0)); %#ok<NASGU>

rowCells = cell(numel(task.scenarios), 1);
for index = 1:numel(task.scenarios)
    scenario = task.scenarios(index);
    try
        localAssignScenario(scenario);
        set_param(model, "SimulationCommand", "update");
        % The official contract freezes a 24 s evidence window.  Do not inherit
        % a candidate-authored StopTime expression, which may be longer.
        simOut = sim(model, ...
            "StopTime", char(string(task.stop_time_s)), ...
            "ReturnWorkspaceOutputs", "on");
        rowCells{index} = localScenarioMetrics(simOut, scenario);
    catch error
        row = scenario;
        row.valid = false;
        row.error = string(getReport(error, "extended", ...
            "hyperlinks", "off"));
        rowCells{index} = row;
    end
end
rows = vertcat(rowCells{:});
receipt = struct( ...
    "schema", "simuverity.formal90-xmed03-reference-metrics.v1", ...
    "task_id", task.task_id, ...
    "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "matlab_release", string(version("-release")), ...
    "model", string(modelPath), ...
    "scenarios", rows, ...
    "all_valid", all([rows.valid]));
localWriteJson(outputPath, receipt);
fprintf("F90_XMED03_REFERENCE_METRICS valid=%d/%d output=%s\n", ...
    sum([rows.valid]), numel(rows), outputPath);
end

function localAssignScenario(scenario)
names = string(fieldnames(scenario));
for index = 1:numel(names)
    name = names(index);
    if name == "id", continue; end
    assignin("base", name, scenario.(name));
end
end

function row = localScenarioMetrics(simOut, scenario)
row = scenario;
row.valid = false;
row.error = "";
try
    pressure = localSeries(simOut, "patient_pressure");
    flow = localSeries(simOut, "patient_flow");
    volume = localSeries(simOut, "patient_volume");
    command = localSeries(simOut, "branch_command");
    period = 60 / scenario.respiratory_rate_bpm;
    initialWindow = [max(0.5, scenario.target_step_time_s - 2*period), ...
        scenario.target_step_time_s - 0.05];
    finalWindow = [max(scenario.target_step_time_s + 0.5, ...
        volume.Time(end) - 2*period), volume.Time(end)];
    row.initial_window_s = initialWindow;
    row.final_window_s = finalWindow;
    row.initial_tidal_volume_mL = localAmplitude(volume, initialWindow);
    row.final_tidal_volume_mL = localAmplitude(volume, finalWindow);
    row.initial_target_mL = [ ...
        scenario.target_tv1_initial_mL, scenario.target_tv2_initial_mL];
    row.final_target_mL = [ ...
        scenario.target_tv1_final_mL, scenario.target_tv2_final_mL];
    row.initial_relative_error = abs(row.initial_tidal_volume_mL - ...
        row.initial_target_mL) ./ row.initial_target_mL;
    row.final_relative_error = abs(row.final_tidal_volume_mL - ...
        row.final_target_mL) ./ row.final_target_mL;
    row.pressure_peep_cmH2O = localPercentileWindow( ...
        pressure, finalWindow, 5);
    row.pressure_pip_cmH2O = localPercentileWindow( ...
        pressure, finalWindow, 95);
    row.pressure_max_cmH2O = localMaximumWindow(pressure, finalWindow);
    row.flow_min_Lps = localMinimumWindow(flow, finalWindow);
    row.flow_max_Lps = localMaximumWindow(flow, finalWindow);
    row.command_initial_mean = localMeanWindow(command, initialWindow);
    row.command_final_mean = localMeanWindow(command, finalWindow);
    row.command_min = min(command.Data, [], 1);
    row.command_max = max(command.Data, [], 1);
    [row.breath_tidal_volume_mL, row.breath_command_mean] = ...
        localBreathMetrics(volume, command, period);
    row.valid = true;
catch error
    row.error = string(getReport(error, "extended", "hyperlinks", "off"));
end
end

function [tidalVolume, commandMean] = ...
        localBreathMetrics(volume, command, period)
breathCount = floor(min(volume.Time(end), command.Time(end)) / period);
tidalVolume = zeros(breathCount, 2);
commandMean = zeros(breathCount, 2);
for breath = 1:breathCount
    window = [(breath - 1) * period, breath * period - 1e-6];
    tidalVolume(breath, :) = localAmplitude(volume, window);
    commandMean(breath, :) = localMeanWindow(command, window);
end
end

function series = localSeries(simOut, name)
series = simuverity_public_output_compatibility( ...
    simOut, string(name), 2, AllowBaseWorkspace=true);
assert(series.Time(1) <= 1e-9 && ...
    series.Time(end) >= 24 - 1e-6, ...
    "SimuVerity:F90:XMED03:ProbeCoverage", "%s lacks full coverage.", name);
end

function values = localAmplitude(series, window)
data = localWindowData(series, window);
values = localPercentile(data, 95) - localPercentile(data, 5);
end

function values = localPercentileWindow(series, window, percentile)
values = localPercentile(localWindowData(series, window), percentile);
end

function values = localMaximumWindow(series, window)
values = max(localWindowData(series, window), [], 1);
end

function values = localMinimumWindow(series, window)
values = min(localWindowData(series, window), [], 1);
end

function values = localMeanWindow(series, window)
values = mean(localWindowData(series, window), 1);
end

function data = localWindowData(series, window)
mask = series.Time >= window(1) & series.Time <= window(2);
assert(nnz(mask) >= 10, "SimuVerity:F90:XMED03:ProbeShortWindow", ...
    "Insufficient samples in analysis window.");
data = double(series.Data(mask, :));
end

function values = localPercentile(data, percentile)
data = sort(double(data), 1);
positions = 1 + (size(data, 1) - 1) * percentile / 100;
lowerIndex = floor(positions);
upperIndex = ceil(positions);
fraction = positions - lowerIndex;
values = data(lowerIndex, :) * (1 - fraction) + ...
    data(upperIndex, :) * fraction;
end

function root = localProjectRoot()
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end

function localWriteJson(path, value)
folder = fileparts(path);
if ~isfolder(folder), mkdir(folder); end
fid = fopen(path, "w");
assert(fid >= 0, "SimuVerity:F90:XMED03:WriteProbe", "Cannot write %s.", path);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
end
