function result = f90_xcomm05_extract_candidate_evidence(modelPath, outputDir)
repo = fileparts(mfilename("fullpath"));
for level = 1:4
    repo = fileparts(repo);
end
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = fullfile(taskDir, "reference", "slexHybridBeamforming.slx");
end
if nargin < 2 || strlength(string(outputDir)) == 0
    generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
    if strlength(generationRunId) == 0
        generationRunId = "f90_xcomm05_manual_" + string(datetime("now", ...
            "Format", "yyyyMMdd'T'HHmmss"));
    end
    outputDir = fullfile(repo, "results", "cross_domain", ...
        "simuverity_public", "F90-XCOMM-05", "fixed_evidence", generationRunId);
else
    generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
end
if ~isfolder(outputDir)
    mkdir(outputDir);
end

cacheDir = string(getenv("SIMULINK_CACHE_FOLDER"));
codegenDir = string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cacheDir) > 0 && strlength(codegenDir) > 0, ...
    "SimuVerity:F90:XCOMM05:Isolation", ...
    "SIMULINK_CACHE_FOLDER and SIMULINK_CODEGEN_FOLDER are required.");
Simulink.fileGenControl("set", "CacheFolder", cacheDir, ...
    "CodeGenFolder", codegenDir, "createDir", true);

official = jsondecode(fileread(simuverity_official_scenarios_path()));
referenceBinding = "present";
modelBindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[modelDir, modelName] = fileparts(modelPath);
addpath(modelDir, "-begin");
cleanupPath = onCleanup(@() rmpath(modelDir)); %#ok<NASGU>

evidence = struct( ...
    "schema", "simuverity.f90-xcomm05-evidence.v1", ...
    "task_id", "F90-XCOMM-05", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "model_file_presence_before", modelBindingBefore, ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "static_audit", struct(), ...
    "scenarios", [], ...
    "errors", {{}}, ...
    "started_at", localNow());

try
    load_system(modelPath);
    evidence.load_pass = true;
    set_param(modelName, "SimulationMode", "normal");
    if isReference
        localInstallReferenceTaps(modelName);
    end
    evidence.static_audit = localStaticAudit(modelName, isReference);
    localApplyScenario(modelName, official.scenarios(1), isReference);
    set_param(modelName, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(modelName, [], [], [], "compile");
    feval(modelName, [], [], [], "term");
    evidence.compile_pass = true;

    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.requested_inputs = rmfield(scenario, 'id');
        try
            rng(double(scenario.seed), "twister");
            localApplyScenario(modelName, scenario, isReference);
            out = sim(modelName, "ReturnWorkspaceOutputs", "on", ...
                "StopTime", "10", "SimulationMode", "normal");
            signals = localReadOutputs(out, isReference);
            row.metrics = localMetrics(signals, scenario);
            row.output_contract = localOutputContract(signals);
            row.simulation_pass = true;
            row.valid = all(structfun(@(value) logical(value), row.output_contract));
            if ~row.valid
                row.error = struct("identifier", "SimuVerity:F90:XCOMM05:OutputContract", ...
                    "message", "One or more required output contracts failed.");
            end
        catch exception
            row.error = localError(exception);
        end
        rows(index) = row;
    end
    evidence.scenarios = rows;
catch exception
    evidence.errors{end + 1} = localError(exception);
    try
        feval(modelName, [], [], [], "term");
    catch
    end
end

try
    close_system(modelName, 0);
catch
end
evidence.model_file_presence_after = localFilePresence(modelPath);
evidence.reference_binding_preserved = (~isReference) || ...
    evidence.model_file_presence_after == referenceBinding;
evidence.model_closed_without_save = true;
evidence.finished_at = localNow();
evidence.runtime = struct( ...
    "matlab_release", string(version("-release")), ...
    "generation_run_id", generationRunId, ...
    "matlab_prefdir", string(prefdir), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")));

evidencePath = fullfile(outputDir, "evidence.json");
localWriteJson(evidencePath, evidence);
result = evidence;
validCount = 0;
if isstruct(evidence.scenarios) && ~isempty(evidence.scenarios) && ...
        isfield(evidence.scenarios, "valid")
    validCount = sum([evidence.scenarios.valid]);
end
fprintf("F90_XCOMM05_EVIDENCE load=%d update=%d compile=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    validCount, numel(evidence.scenarios), evidencePath);
end

function localInstallReferenceTaps(model)
mapping = {
    "TxSymbols", model + "/Rectangular QAM" + newline + "Modulator" + newline + "Baseband", 1, 1;
    "RxSymbols", model + "/Rx BB Combiner", 1, 1;
    "ChannelMatrix", model + "/From4", 1, 100;
    "TxDigitalWeights", model + "/From2", 1, 100;
    "TxAnalogAngles", model + "/From3", 1, 100;
    "RxDigitalWeights", model + "/From1", 1, 100;
    "RxAnalogAngles", model + "/From", 1, 100;
    "ChannelUpdateFlag", model + "/From5", 1, 1
};
for index = 1:size(mapping, 1)
    variable = string(mapping{index, 1});
    source = string(mapping{index, 2});
    sourcePort = double(mapping{index, 3});
    decimation = double(mapping{index, 4});
    assert(getSimulinkBlockHandle(source) > 0, ...
        "SimuVerity:F90:XCOMM05:ReferenceLocator", "Missing reference signal source %s.", source);
    tap = model + "/__F90_" + variable;
    if getSimulinkBlockHandle(tap) < 0
        add_block("simulink/Sinks/To Workspace", tap, ...
            "VariableName", "F90_" + variable, ...
            "SaveFormat", "Timeseries", ...
            "MaxDataPoints", "inf", ...
            "Decimation", string(decimation), ...
            "Position", [900, 500 + 45 * index, 1040, 525 + 45 * index]);
        sourceHandles = get_param(source, "PortHandles");
        tapHandles = get_param(tap, "PortHandles");
        add_line(model, sourceHandles.Outport(sourcePort), ...
            tapHandles.Inport(1), "autorouting", "on");
    end
end
end

function audit = localStaticAudit(model, isReference)
audit = struct( ...
    "two_stream_source_present", false, ...
    "tx_digital_stage_present", false, ...
    "tx_analog_stage_present", false, ...
    "time_varying_channel_present", false, ...
    "rx_analog_stage_present", false, ...
    "rx_digital_stage_present", false, ...
    "channel_to_weight_adaptation_present", false, ...
    "core_path_qualified", false);
if isReference
    names = [
        model + "/Random Integer" + newline + "Generator";
        model + "/Tx BB Precoder";
        model + "/Tx RF Precoder";
        model + "/MIMO Scattering Channel";
        model + "/Rx RF Combiner";
        model + "/Rx BB Combiner";
        model + "/Hybrid Weights Calculation"
    ];
    exists = arrayfun(@(path) getSimulinkBlockHandle(path) > 0, names);
    audit.two_stream_source_present = exists(1);
    audit.tx_digital_stage_present = exists(2);
    audit.tx_analog_stage_present = exists(3);
    audit.time_varying_channel_present = exists(4);
    audit.rx_analog_stage_present = exists(5);
    audit.rx_digital_stage_present = exists(6);
    audit.channel_to_weight_adaptation_present = exists(7);
    audit.core_path_qualified = all(exists);
else
    requiredOutputs = ["TxSymbols","RxSymbols","ChannelMatrix", ...
        "TxDigitalWeights","TxAnalogAngles","RxDigitalWeights", ...
        "RxAnalogAngles","ChannelUpdateFlag"];
    connected = arrayfun(@(name) ...
        localPublicSinkConnected(model,name),requiredOutputs);
    audit.two_stream_source_present = all(connected(1:2));
    audit.time_varying_channel_present = connected(3) && connected(8);
    audit.tx_digital_stage_present = connected(4);
    audit.tx_analog_stage_present = connected(5);
    audit.rx_digital_stage_present = connected(6);
    audit.rx_analog_stage_present = connected(7);
    audit.channel_to_weight_adaptation_present = all(connected(3:8));
    audit.core_path_qualified = all(connected);
    audit.public_output_connections = struct( ...
        "names",requiredOutputs,"connected",logical(connected));
    audit.basis = "live upstream connections at every declared public evidence sink; causal behavior is checked from official-scenario evidence";
end
end

function connected = localPublicSinkConnected(model, variable)
connected = false;
sinks = find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "BlockType","ToWorkspace","VariableName",char(variable));
for index = 1:numel(sinks)
    try
        ports = get_param(sinks{index},"PortHandles");
        line = get_param(ports.Inport(1),"Line");
        if line > 0 && get_param(line,"SrcBlockHandle") > 0
            connected = true;
            return;
        end
    catch
    end
end
end

function localApplyScenario(model, scenario, isReference)
assignin("base", "ChannelSNR_dB", double(scenario.ChannelSNR_dB));
assignin("base", "ChannelCoherenceSymbols", double(scenario.ChannelCoherenceSymbols));
assignin("base", "PhaseGridPointsPerAxis", double(scenario.PhaseGridPointsPerAxis));
assignin("base", "BeamformingAlgorithm", string(scenario.BeamformingAlgorithm));
if ~isReference
    return;
end
param = helperslexHybridBeamformingParam;
param.SNR = 10.^(double(scenario.ChannelSNR_dB) / 10);
param.NTxSym = double(scenario.ChannelCoherenceSymbols);
[param.TxAngF, param.RxAngW] = localAngleGrids( ...
    double(scenario.PhaseGridPointsPerAxis));
assignin("base", "paramHybridBF", param);
set_param(model + "/Hybrid Weights Calculation", ...
    "Algorithm", char(string(scenario.BeamformingAlgorithm)));
set_param(model + "/Receiver Preamp", "Seed", string(double(scenario.seed)));
set_param(model, "SimulationCommand", "update");
end

function [tx, rx] = localAngleGrids(points)
assert(points >= 5 && points <= 9 && mod(points, 2) == 1, ...
    "SimuVerity:F90:XCOMM05:Grid", "PhaseGridPointsPerAxis must be 5, 7, or 9.");
txAz = linspace(-40, 40, points);
txEl = linspace(-20, 20, points);
rxAz = linspace(-60, 60, points);
rxEl = linspace(-40, 40, points);
tx = zeros(2, points^2);
rx = zeros(2, points^2);
cursor = 1;
for first = 1:points
    for second = 1:points
        tx(:, cursor) = [txAz(first); txEl(second)];
        rx(:, cursor) = [rxAz(first); rxEl(second)];
        cursor = cursor + 1;
    end
end
end

function signals = localReadOutputs(out, isReference)
names = ["TxSymbols", "RxSymbols", "ChannelMatrix", ...
    "TxDigitalWeights", "TxAnalogAngles", "RxDigitalWeights", ...
    "RxAnalogAngles", "ChannelUpdateFlag"];
signals = struct();
for index = 1:numel(names)
    name = names(index);
    candidates = name;
    if isReference
        candidates = ["F90_" + name, name];
    end
    value = [];
    for candidate = candidates
        try
            value = out.get(candidate);
            if ~isempty(value)
                break;
            end
        catch
        end
        try
            value = evalin("base", candidate);
            if ~isempty(value)
                break;
            end
        catch
        end
    end
    if ~isReference
        value = simuverity_public_output_compatibility( ...
            out,name,[],AllowBaseWorkspace=true);
    end
    assert(isa(value, "timeseries"), "SimuVerity:F90:XCOMM05:MissingTimeseries", ...
        "Required output %s is not a Timeseries.", name);
    [time, matrix, sampleShape] = localFlatten(value);
    signals.(name) = struct( ...
        "time", time, "matrix", matrix, "sample_shape", sampleShape);
end
end

function contract = localOutputContract(signals)
contract = struct( ...
    "tx_two_complex_streams", localSignalContract(signals.TxSymbols, 2), ...
    "rx_two_complex_streams", localSignalContract(signals.RxSymbols, 2), ...
    "channel_16_by_64", localSignalContract(signals.ChannelMatrix, 1024), ...
    "tx_digital_4_by_2", localSignalContract(signals.TxDigitalWeights, 8), ...
    "tx_analog_angles_2_by_4", localSignalContract(signals.TxAnalogAngles, 8), ...
    "rx_digital_2_by_4", localSignalContract(signals.RxDigitalWeights, 8), ...
    "rx_analog_angles_2_by_4", localSignalContract(signals.RxAnalogAngles, 8), ...
    "channel_update_scalar", localSignalContract(signals.ChannelUpdateFlag, 1));
end

function valid = localSignalContract(signal, width)
valid = ~isempty(signal.time) && signal.time(1) <= 1e-9 && ...
    signal.time(end) >= 9.9 && size(signal.matrix, 2) == width && ...
    all(isfinite(real(signal.matrix)), "all") && ...
    all(isfinite(imag(signal.matrix)), "all");
end

function metrics = localMetrics(signals, scenario)
[tx, rx, time] = localAlignedStreams(signals.TxSymbols, signals.RxSymbols);
steady = time >= 1.0;
tx = tx(steady, :);
rx = rx(steady, :);
time = time(steady);
stream = repmat(struct("evm_rms", 0, "correlation", 0, ...
    "best_lag_samples", 0, "complex_gain_magnitude", 0), 2, 1);
alignedTx = cell(2, 1);
alignedRx = cell(2, 1);
for index = 1:2
    [stream(index), alignedTx{index}, alignedRx{index}] = ...
        localStreamFit(tx(:, index), rx(:, index));
end
leakage = zeros(2, 1);
for index = 1:2
    other = 3 - index;
    count = min(numel(alignedTx{other}), numel(alignedRx{index}));
    leakage(index) = localCorrelation( ...
        alignedTx{other}(1:count), alignedRx{index}(1:count)) / ...
        max(stream(index).correlation, 1e-12);
end

windowEvm = localWindowEvm(time, tx, rx, 0.5);
h = signals.ChannelMatrix.matrix;
fbb = signals.TxDigitalWeights.matrix;
frf = real(signals.TxAnalogAngles.matrix);
wbb = signals.RxDigitalWeights.matrix;
wrf = real(signals.RxAnalogAngles.matrix);
[txGrid, rxGrid] = localAngleGrids(double(scenario.PhaseGridPointsPerAxis));
hChange = localChangeProfile(h);
fChange = localChangeProfile([fbb, frf]);
wChange = localChangeProfile([wbb, wrf]);
count = min([numel(hChange), numel(fChange), numel(wChange)]);
if count > 0
    hEvent = hChange(1:count) > 1e-6;
    weightEvent = max(fChange(1:count), wChange(1:count)) > 1e-6;
    cochange = sum(hEvent & weightEvent) / max(sum(hEvent), 1);
else
    cochange = 0;
end

metrics = struct( ...
    "stream", stream, ...
    "mean_evm_rms", mean([stream.evm_rms]), ...
    "worst_stream_evm_rms", max([stream.evm_rms]), ...
    "minimum_stream_correlation", min([stream.correlation]), ...
    "worst_interstream_leakage_ratio", max(leakage), ...
    "window_evm_rms", windowEvm, ...
    "worst_window_evm_rms", max(windowEvm), ...
    "tail_window_evm_rms", mean(windowEvm(max(1, end - 2):end)), ...
    "channel_change_fraction", mean(hChange > 1e-6), ...
    "tx_weight_change_fraction", mean(fChange > 1e-6), ...
    "rx_weight_change_fraction", mean(wChange > 1e-6), ...
    "channel_weight_cochange_fraction", cochange, ...
    "tx_phase_grid_max_error_deg", localGridError(frf, txGrid), ...
    "rx_phase_grid_max_error_deg", localGridError(wrf, rxGrid), ...
    "tx_digital_nonzero_fraction", mean(abs(fbb) > 1e-10, "all"), ...
    "rx_digital_nonzero_fraction", mean(abs(wbb) > 1e-10, "all"), ...
    "rx_source_exact_fraction", mean(abs(rx - tx) < 1e-12, "all"), ...
    "channel_update_fraction", mean(real(signals.ChannelUpdateFlag.matrix) > 0.5, "all"), ...
    "tx_stream_count", size(tx, 2), ...
    "rx_stream_count", size(rx, 2), ...
    "channel_width", size(h, 2), ...
    "tx_digital_width", size(fbb, 2), ...
    "tx_analog_width", size(frf, 2), ...
    "rx_digital_width", size(wbb, 2), ...
    "rx_analog_width", size(wrf, 2));
end

function [tx, rx, time] = localAlignedStreams(txSignal, rxSignal)
time = rxSignal.time;
rx = rxSignal.matrix;
tx = localInterpolateComplex(txSignal.time, txSignal.matrix, time);
count = min(size(tx, 1), size(rx, 1));
time = time(1:count);
tx = tx(1:count, :);
rx = rx(1:count, :);
end

function output = localInterpolateComplex(sourceTime, source, targetTime)
if isequal(sourceTime, targetTime)
    output = source;
    return;
end
output = complex(zeros(numel(targetTime), size(source, 2)));
for index = 1:size(source, 2)
    output(:, index) = interp1(sourceTime, source(:, index), ...
        targetTime, "nearest", "extrap");
end
end

function [fit, xBest, yBest] = localStreamFit(x, y)
best = -inf;
xBest = x;
yBest = y;
bestLag = 0;
for lag = -20:20
    if lag >= 0
        xa = x(1:end-lag);
        ya = y(1+lag:end);
    else
        xa = x(1-lag:end);
        ya = y(1:end+lag);
    end
    score = localCorrelation(xa, ya);
    if score > best
        best = score;
        xBest = xa;
        yBest = ya;
        bestLag = lag;
    end
end
gain = (xBest' * yBest) / max(real(xBest' * xBest), 1e-12);
reference = gain * xBest;
evm = sqrt(mean(abs(yBest - reference).^2) / ...
    max(mean(abs(reference).^2), 1e-12));
fit = struct( ...
    "evm_rms", double(evm), ...
    "correlation", double(best), ...
    "best_lag_samples", double(bestLag), ...
    "complex_gain_magnitude", double(abs(gain)));
end

function value = localCorrelation(x, y)
value = abs(x' * y) / max(norm(x) * norm(y), 1e-12);
value = double(value);
end

function values = localWindowEvm(time, tx, rx, width)
edges = time(1):width:time(end);
values = zeros(max(numel(edges) - 1, 1), 1);
if numel(edges) < 2
    values(1) = localStreamFit(tx(:, 1), rx(:, 1)).evm_rms;
    return;
end
for window = 1:numel(edges) - 1
    indices = time >= edges(window) & time < edges(window + 1);
    if sum(indices) < 20
        values(window) = NaN;
        continue;
    end
    first = localStreamFit(tx(indices, 1), rx(indices, 1));
    second = localStreamFit(tx(indices, 2), rx(indices, 2));
    values(window) = max(first.evm_rms, second.evm_rms);
end
values = values(isfinite(values));
end

function values = localChangeProfile(matrix)
if size(matrix, 1) < 2
    values = 0;
    return;
end
delta = diff(matrix, 1, 1);
denominator = max(vecnorm(matrix(1:end-1, :), 2, 2), 1e-12);
values = vecnorm(delta, 2, 2) ./ denominator;
end

function errorValue = localGridError(angleMatrix, grid)
if isempty(angleMatrix)
    errorValue = inf;
    return;
end
errorValue = 0;
for row = 1:size(angleMatrix, 1)
    angles = reshape(angleMatrix(row, :), 2, []);
    for column = 1:size(angles, 2)
        distances = vecnorm(grid - angles(:, column), 2, 1);
        errorValue = max(errorValue, min(distances));
    end
end
errorValue = double(errorValue);
end

function [time, matrix, sampleShape] = localFlatten(series)
time = double(series.Time(:));
data = series.Data;
dimensions = size(data);
if dimensions(1) == numel(time)
    matrix = reshape(data, numel(time), []);
    sampleShape = dimensions(2:end);
elseif dimensions(end) == numel(time)
    order = [ndims(data), 1:ndims(data)-1];
    data = permute(data, order);
    matrix = reshape(data, numel(time), []);
    sampleShape = dimensions(1:end-1);
elseif numel(time) == 1
    matrix = reshape(data, 1, []);
    sampleShape = dimensions;
else
    error("SimuVerity:F90:XCOMM05:SignalShape", ...
        "Timeseries data dimensions do not align with the time vector.");
end
matrix = double(matrix);
sampleShape = double(sampleShape);
end

function row = localEmptyScenario
row = struct( ...
    "id", "", ...
    "requested_inputs", struct(), ...
    "simulation_pass", false, ...
    "valid", false, ...
    "output_contract", struct(), ...
    "metrics", struct(), ...
    "error", struct());
end

function value = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
value = "present";
end

function value = localNow
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function output = localError(exception)
output = struct( ...
    "identifier", string(exception.identifier), ...
    "message", string(exception.message), ...
    "report", string(getReport(exception, "extended", "hyperlinks", "off")));
end

function localWriteJson(path, value)
fid = fopen(path, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XCOMM05:Write");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s", jsonencode(value));
end
