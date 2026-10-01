function result = f90_xcomm06_extract_candidate_evidence(modelPath, outputDir)
% Extract simulation evidence only. Scoring is deliberately offline.
repo = localProjectRoot();
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = fullfile(taskDir, "reference", "source", "commqpsktxrx.slx");
end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xcomm06_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(repo, "results", "cross_domain", ...
        "simuverity_public", "F90-XCOMM-06", "fixed_evidence", generationRunId);
end
if ~isfolder(outputDir), mkdir(outputDir); end

official = jsondecode(fileread(simuverity_official_scenarios_path()));
expectedBinding = "present";
bindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[modelDir, modelName] = fileparts(modelPath);
addpath(modelDir, "-begin");
cleanupPath = onCleanup(@() rmpath(modelDir)); %#ok<NASGU>
localConfigureFileGeneration();

evidence = struct( ...
    "schema", "simuverity.f90-xcomm06-evidence.v1", ...
    "task_id", "F90-XCOMM-06", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "model_file_presence_before", bindingBefore, ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "static_audit", struct(), ...
    "profile", struct(), ...
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
    evidence.profile = localCompactProfile(modelName);
    smoke = official.scenarios(1);
    localApplyScenario(modelName, smoke, isReference, 8);
    set_param(modelName, "SimulationCommand", "update");
    evidence.update_pass = true;
    feval(modelName, [], [], [], "compile");
    feval(modelName, [], [], [], "term");
    evidence.compile_pass = true;

    sim(modelName, "ReturnWorkspaceOutputs", "on", ...
        "StopTime", localStopTime(8), "SimulationMode", "normal");
    evidence.nominal_smoke_pass = true;

    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.requested_inputs = rmfield(scenario, "id");
        started = tic;
        try
            localClearOutputs();
            localApplyScenario(modelName, scenario, isReference, ...
                double(official.simulation.frames));
            out = sim(modelName, "ReturnWorkspaceOutputs", "on", ...
                "StopTime", localStopTime(double(official.simulation.frames)), ...
                "SimulationMode", "normal");
            signals = localReadOutputs(out, isReference);
            row.output_contract = localOutputContract(signals);
            row.metrics = localMetrics(signals, scenario);
            row.simulation_pass = true;
            row.valid = all(structfun(@(value) logical(value), ...
                row.output_contract));
            if ~row.valid
                row.error = struct("identifier", ...
                    "SimuVerity:F90:XCOMM06:OutputContract", ...
                    "message", ...
                    "One or more required output contracts failed.");
            end
        catch exception
            row.error = localError(exception);
        end
        row.wall_seconds = toc(started);
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
    evidence.model_file_presence_after == expectedBinding;
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
if ~isempty(evidence.scenarios)
    validCount = sum([evidence.scenarios.valid]);
end
fprintf("F90_XCOMM06_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, numel(evidence.scenarios), ...
    evidencePath);
end

function localInstallReferenceTaps(model)
channel = model + "/AWGN Channel with Frequency Offset & Variable Time Delay";
decoder = model + "/Receiver/Data Decoding";
mapping = {
    "TxWaveform", model + "/Transmitter", 1, model;
    "RxImpaired", channel, 1, model;
    "RxSynchronizedSymbols", model + "/Receiver/Frame Synchronizer", 1, model + "/Receiver";
    "FrameValid", model + "/Receiver/Frame Synchronizer", 2, model + "/Receiver";
    "TxBits", decoder + "/Signal From Workspace", 1, decoder;
    "RxBits", decoder + "/Descrambling", 1, decoder;
    "BERStats", model + "/Receiver", 1, model;
    "ChannelDelaySamples", channel + "/Delay Generator", 1, channel
};
for index = 1:size(mapping, 1)
    variable = string(mapping{index, 1});
    source = string(mapping{index, 2});
    sourcePort = double(mapping{index, 3});
    parent = string(mapping{index, 4});
    assert(getSimulinkBlockHandle(source) > 0, ...
        "SimuVerity:F90:XCOMM06:ReferenceLocator", ...
        "Missing reference signal source %s.", source);
    tap = parent + "/__F90_" + variable;
    if getSimulinkBlockHandle(tap) < 0
        add_block("simulink/Sinks/To Workspace", tap, ...
            "VariableName", "F90_" + variable, ...
            "SaveFormat", "Timeseries", ...
            "Save2DSignal", "3-D array (concatenate along third dimension)", ...
            "MaxDataPoints", "inf", ...
            "Position", [900, 450 + 42 * index, 1060, 475 + 42 * index]);
        sourceHandles = get_param(source, "PortHandles");
        tapHandles = get_param(tap, "PortHandles");
        add_line(parent, sourceHandles.Outport(sourcePort), ...
            tapHandles.Inport(1), "autorouting", "on");
    end
end
end

function audit = localStaticAudit(model, isReference)
audit = struct( ...
    "transmitter_present", false, ...
    "impaired_channel_present", false, ...
    "gain_stabilization_present", false, ...
    "carrier_synchronization_present", false, ...
    "timing_synchronization_present", false, ...
    "frame_acquisition_present", false, ...
    "payload_comparison_present", false, ...
    "public_outputs_bound", false, ...
    "core_path_qualified", false);
if isReference
    paths = [
        model + "/Transmitter";
        model + "/AWGN Channel with Frequency Offset & Variable Time Delay";
        model + "/Receiver/AGC";
        model + "/Receiver/Fine Frequency Compensation";
        model + "/Receiver/Timing Recovery";
        model + "/Receiver/Frame Synchronizer";
        model + "/Receiver/Data Decoding/Error Rate Calculation"
    ];
    exists = arrayfun(@(path) getSimulinkBlockHandle(path) > 0, paths);
    audit.transmitter_present = exists(1);
    audit.impaired_channel_present = exists(2);
    audit.gain_stabilization_present = exists(3);
    audit.carrier_synchronization_present = exists(4);
    audit.timing_synchronization_present = exists(5);
    audit.frame_acquisition_present = exists(6);
    audit.payload_comparison_present = exists(7);
    audit.public_outputs_bound = true;
    audit.core_path_qualified = all(exists);
    return;
end
names = ["TxWaveform", "RxImpaired", "RxSynchronizedSymbols", ...
    "FrameValid", "TxBits", "RxBits", "BERStats", "ChannelDelaySamples"];
bound = false(size(names));
for index = 1:numel(names)
    blocks = find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "BlockType", "ToWorkspace", ...
        "VariableName", names(index));
    bound(index) = ~isempty(blocks);
end
audit.public_outputs_bound = all(bound);
audit.transmitter_present = bound(1);
audit.impaired_channel_present = bound(2);
audit.carrier_synchronization_present = bound(3);
audit.timing_synchronization_present = bound(3) && bound(8);
audit.frame_acquisition_present = bound(4);
audit.payload_comparison_present = bound(5) && bound(6) && bound(7);
audit.gain_stabilization_present = bound(2) && bound(3);
audit.core_path_qualified = audit.public_outputs_bound;
end

function profile = localCompactProfile(model)
profile = struct( ...
    "block_count", numel(find_system(model, "Type", "Block")), ...
    "subsystem_count", numel(find_system(model, ...
        "BlockType", "SubSystem")), ...
    "stateflow_chart_count", numel(find_system(model, ...
        "MaskType", "Stateflow")), ...
    "causal_path", [ ...
        "framed payload generation"; ...
        "QPSK modulation and pulse shaping"; ...
        "noise, carrier, and variable-delay channel"; ...
        "gain, carrier, and timing synchronization"; ...
        "frame acquisition and phase-ambiguity correction"; ...
        "payload decoding and BER comparison"]);
end

function localApplyScenario(model, scenario, isReference, frames)
values = {
    "EbNo_dB", double(scenario.EbNo_dB);
    "CarrierOffset_Hz", double(scenario.CarrierOffset_Hz);
    "CarrierPhase_deg", double(scenario.CarrierPhase_deg);
    "TimingProfile", string(scenario.TimingProfile);
    "TimingStep_samples_per_frame", double(scenario.TimingStep_samples_per_frame);
    "TimingSpan_samples", double(scenario.TimingSpan_samples);
    "PayloadShift_bits", double(scenario.PayloadShift_bits)
};
for index = 1:size(values, 1)
    assignin("base", values{index, 1}, values{index, 2});
end
rng(double(scenario.seed), "twister");
if ~isReference
    set_param(model, "StopTime", localStopTime(frames));
    return;
end

mask = model + "/Model Parameters";
set_param(mask, ...
    "EbN0dB", string(double(scenario.EbNo_dB)), ...
    "FreqOffset", string(double(scenario.CarrierOffset_Hz)), ...
    "DelayCtrl", char(string(scenario.TimingProfile)), ...
    "DelayStep", string(double(scenario.TimingStep_samples_per_frame)), ...
    "MinDelay", "0", ...
    "MaxDelay", string(double(scenario.TimingSpan_samples)), ...
    "DelayStart", "0.1", ...
    "ShowRecvMsg", "off");

channel = model + "/AWGN Channel with Frequency Offset & Variable Time Delay";
phaseFrequency = channel + "/Phase// Frequency Offset";
set_param(phaseFrequency, ...
    "phaseOffset", string(double(scenario.CarrierPhase_deg)), ...
    "freqOffset", string(double(scenario.CarrierOffset_Hz)));
set_param(channel + "/AWGN Channel", "Seed", string(double(scenario.seed)));

payloadExpression = "circshift(qpsktxrx.MessageBits,PayloadShift_bits)";
set_param(model + "/Transmitter/Bit Generation/Signal From Workspace", ...
    "X", payloadExpression);
set_param(model + "/Receiver/Data Decoding/Signal From Workspace", ...
    "X", payloadExpression);
set_param(model, "StopTime", localStopTime(frames));
set_param(model, "SimulationCommand", "update");
end

function value = localStopTime(frames)
value = string(double(frames) * 0.02266);
end

function localClearOutputs
names = ["TxWaveform", "RxImpaired", "RxSynchronizedSymbols", ...
    "FrameValid", "TxBits", "RxBits", "BERStats", "ChannelDelaySamples"];
command = "clear";
for name = names
    command = command + " F90_" + name + " " + name;
end
evalin("base", command);
end

function signals = localReadOutputs(out, isReference)
names = ["TxWaveform", "RxImpaired", "RxSynchronizedSymbols", ...
    "FrameValid", "TxBits", "RxBits", "BERStats", "ChannelDelaySamples"];
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
            if ~isempty(value), break; end
        catch
        end
        try
            value = evalin("base", candidate);
            if ~isempty(value), break; end
        catch
        end
    end
    if ~isReference
        value = simuverity_public_output_compatibility( ...
            out,name,[],AllowBaseWorkspace=true);
    end
    assert(isa(value, "timeseries"), ...
        "SimuVerity:F90:XCOMM06:MissingTimeseries", ...
        "Required output %s is not a Timeseries.", name);
    [time, matrix, sampleShape] = localFlatten(value);
    signals.(name) = struct( ...
        "time", time, "matrix", matrix, "sample_shape", sampleShape);
end
end

function contract = localOutputContract(signals)
contract = struct( ...
    "tx_waveform_complex", localSignalContract( ...
        signals.TxWaveform, 1, true), ...
    "rx_impaired_complex", localSignalContract( ...
        signals.RxImpaired, 1, true), ...
    "rx_synchronized_complex", localSignalContract( ...
        signals.RxSynchronizedSymbols, 1, true), ...
    "frame_valid_scalar", localSignalContract( ...
        signals.FrameValid, 1, false), ...
    "tx_bits_nonempty", localSignalContract( ...
        signals.TxBits, 1, false), ...
    "rx_bits_nonempty", localSignalContract( ...
        signals.RxBits, 1, false), ...
    "ber_three_channels", localSignalContract( ...
        signals.BERStats, 3, false), ...
    "delay_signal_nonempty", localSignalContract( ...
        signals.ChannelDelaySamples, 1, false));
end

function valid = localSignalContract(signal, minimumWidth, requireComplex)
valid = ~isempty(signal.time) && size(signal.matrix, 2) >= minimumWidth && ...
    all(isfinite(real(signal.matrix)), "all") && ...
    all(isfinite(imag(signal.matrix)), "all");
if requireComplex
    valid = valid && any(abs(imag(signal.matrix)) > 1e-12, "all");
end
end

function metrics = localMetrics(signals, scenario)
txWave = signals.TxWaveform.matrix(:);
rxImpaired = signals.RxImpaired.matrix(:);
rxSync = signals.RxSynchronizedSymbols.matrix(:);
frameValid = real(signals.FrameValid.matrix(:)) > 0.5;
txBits = round(real(signals.TxBits.matrix(:)));
rxBits = round(real(signals.RxBits.matrix(:)));
ber = real(signals.BERStats.matrix);
delay = real(signals.ChannelDelaySamples.matrix(:));

bitCount = min(numel(txBits), numel(rxBits));
txBits = txBits(1:bitCount);
rxBits = rxBits(1:bitCount);
calculatedErrors = sum(txBits ~= rxBits);
calculatedBer = calculatedErrors / max(bitCount, 1);

berRows = reshape(ber, size(ber, 1), []);
assert(size(berRows, 2) >= 3, "SimuVerity:F90:XCOMM06:BERWidth");
finalBer = double(berRows(end, 1));
finalErrors = double(berRows(end, 2));
finalCompared = double(berRows(end, 3));
berConsistency = abs(finalBer - finalErrors / max(finalCompared, 1));

firstValid = find(frameValid, 1, "first");
if isempty(firstValid)
    acquisitionFraction = 1;
    postValidFraction = 0;
    longestInvalid = numel(frameValid);
else
    acquisitionFraction = (firstValid - 1) / max(numel(frameValid), 1);
    post = frameValid(firstValid:end);
    postValidFraction = mean(post);
    longestInvalid = localLongestRun(~post);
end

count = min(numel(txWave), numel(rxImpaired));
exactFraction = mean(abs(txWave(1:count) - rxImpaired(1:count)) < 1e-12);
normalizedDifference = rms(txWave(1:count) - rxImpaired(1:count)) / ...
    max(rms(txWave(1:count)), 1e-12);

constellation = localConstellationMetrics(rxSync);
delayMetrics = localDelayMetrics(delay, string(scenario.TimingProfile), ...
    double(scenario.TimingStep_samples_per_frame), ...
    double(scenario.TimingSpan_samples));

metrics = struct( ...
    "bit_accuracy", double(mean(txBits == rxBits)), ...
    "calculated_ber", double(calculatedBer), ...
    "calculated_error_count", double(calculatedErrors), ...
    "compared_bit_count_from_streams", double(bitCount), ...
    "reported_ber", finalBer, ...
    "reported_error_count", finalErrors, ...
    "reported_compared_bit_count", finalCompared, ...
    "ber_consistency_error", berConsistency, ...
    "frame_valid_fraction", double(mean(frameValid)), ...
    "post_acquisition_valid_fraction", double(postValidFraction), ...
    "acquisition_fraction", double(acquisitionFraction), ...
    "longest_post_acquisition_invalid_fraction", ...
        double(longestInvalid / max(numel(frameValid), 1)), ...
    "frame_valid_sample_count", double(numel(frameValid)), ...
    "channel_exact_copy_fraction", double(exactFraction), ...
    "channel_normalized_difference", double(normalizedDifference), ...
    "rx_synchronized_evm", constellation.evm, ...
    "rx_synchronized_power", constellation.power, ...
    "residual_cfo_hz", constellation.residual_cfo_hz, ...
    "residual_phase_span_deg", constellation.phase_span_deg, ...
    "payload_one_fraction", double(mean(rxBits)), ...
    "payload_transition_fraction", double(mean(abs(diff(rxBits)) > 0)), ...
    "tx_prefix_summary", localBitPrefixSummary(txBits), ...
    "rx_prefix_summary", localBitPrefixSummary(rxBits), ...
    "delay_min_samples", delayMetrics.minimum, ...
    "delay_max_samples", delayMetrics.maximum, ...
    "delay_span_samples", delayMetrics.span, ...
    "delay_step_median_samples", delayMetrics.step_median, ...
    "delay_turn_count", delayMetrics.turn_count, ...
    "delay_profile_match", delayMetrics.profile_match, ...
    "requested_payload_shift_bits", double(scenario.PayloadShift_bits));
end

function value = localBitPrefixSummary(bits)
count = min(numel(bits), 128);
if count == 0
    value = 0;
else
    value = double(sum((1:count)' .* double(bits(1:count))));
end
end

function value = localLongestRun(flags)
if isempty(flags)
    value = 0;
    return;
end
edges = diff([false; flags(:); false]);
starts = find(edges == 1);
stops = find(edges == -1);
if isempty(starts)
    value = 0;
else
    value = max(stops - starts);
end
end

function output = localConstellationMetrics(values)
values = values(isfinite(real(values)) & isfinite(imag(values)));
values = values(abs(values) > 1e-9);
if numel(values) > 200000
    indices = round(linspace(1, numel(values), 200000));
    values = values(indices);
end
power = mean(abs(values).^2);
normalized = values / sqrt(max(power, 1e-12));
ideal = [1+1i, 1-1i, -1+1i, -1-1i] / sqrt(2);
distance = abs(normalized - ideal);
evm = sqrt(mean(min(distance, [], 2).^2));

fourth = normalized.^4;
phase = unwrap(angle(fourth)) / 4;
indices = (0:numel(phase)-1)';
start = max(1, floor(numel(phase) / 2));
fit = polyfit(indices(start:end), phase(start:end), 1);
residualCfo = fit(1) * 50000 / (2 * pi);
detrended = phase - polyval(fit, indices);
phaseSpan = prctile(detrended, 99) - prctile(detrended, 1);
output = struct( ...
    "evm", double(evm), ...
    "power", double(power), ...
    "residual_cfo_hz", double(abs(residualCfo)), ...
    "phase_span_deg", double(rad2deg(phaseSpan)));
end

function output = localDelayMetrics(values, profile, requestedStep, requestedSpan)
values = values(isfinite(values));
if isempty(values)
    output = struct("minimum", NaN, "maximum", NaN, "span", NaN, ...
        "step_median", NaN, "turn_count", 0, "profile_match", 0);
    return;
end
if numel(values) > 1
    delta = diff(values);
    moving = delta(abs(delta) > 1e-9);
else
    moving = [];
end
if isempty(moving)
    stepMedian = 0;
    turnCount = 0;
else
    stepMedian = median(abs(moving));
    signs = sign(moving);
    turnCount = sum(abs(diff(signs)) > 1);
end
span = max(values) - min(values);
spanScore = max(0, 1 - abs(span - requestedSpan) / max(requestedSpan, 1e-9));
stepScore = max(0, 1 - abs(stepMedian - requestedStep) / ...
    max(requestedStep, 1e-9));
if profile == "Triangle"
    shapeScore = double(turnCount >= 1);
else
    shapeScore = double(turnCount == 0 && mean(diff(values)) >= -1e-9);
end
output = struct( ...
    "minimum", double(min(values)), ...
    "maximum", double(max(values)), ...
    "span", double(span), ...
    "step_median", double(stepMedian), ...
    "turn_count", double(turnCount), ...
    "profile_match", double(mean([spanScore, stepScore, shapeScore])));
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
    error("SimuVerity:F90:XCOMM06:SignalShape", ...
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
    "wall_seconds", 0, ...
    "error", struct());
end

function localConfigureFileGeneration
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
if strlength(cache) > 0 && strlength(codegen) > 0
    if ~isfolder(cache), mkdir(cache); end
    if ~isfolder(codegen), mkdir(codegen); end
    Simulink.fileGenControl("set", "CacheFolder", cache, ...
        "CodeGenFolder", codegen, "createDir", true);
end
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
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
assert(fid >= 0, "SimuVerity:F90:XCOMM06:Write");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
end
