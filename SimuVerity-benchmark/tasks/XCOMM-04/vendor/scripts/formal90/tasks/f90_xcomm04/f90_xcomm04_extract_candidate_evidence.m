function evidence = f90_xcomm04_extract_candidate_evidence(modelPath, outDir)
%F90_XCOMM04_EXTRACT_CANDIDATE_EVIDENCE Extract all official evidence in one session.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

def = f90_xcomm04_definition;
root = localProjectRoot;
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
assert(strlength(generationRunId) > 0, "SimuVerity:F90:XCOMM04:GenerationRunId", ...
    "SIMUVERITY_GENERATION_RUN_ID is required.");
if strlength(modelPath) == 0, modelPath = def.reference_model; end
assert(isfile(modelPath), "SimuVerity:F90:XCOMM04:ModelMissing", ...
    "Model under evaluation is missing: %s", modelPath);
if strlength(outDir) == 0
    outDir = fullfile(root, "results", "cross_domain", ...
        "simuverity_public", def.formal_id, "fixed_evidence", generationRunId);
end
if ~isfolder(outDir), mkdir(outDir); end
evidencePath = fullfile(outDir, "evidence.json");
assert(~isfile(evidencePath), "SimuVerity:F90:XCOMM04:OutputReuse", ...
    "Evidence already exists for GenerationRunId %s.", generationRunId);

localConfigureIsolation;
modelPresence = localFilePresence(modelPath);
evaluationSubject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(evaluationSubject) == 0, evaluationSubject = "candidate"; end
assert(any(evaluationSubject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XCOMM04:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
isReference = evaluationSubject == "reference" && ...
    modelPresence == def.reference_file_presence;
if evaluationSubject == "reference"
    assert(isReference, "SimuVerity:F90:XCOMM04:ReferenceIdentity", ...
        "Reference-subject model file presence differs from the task binding.");
end
[modelDir, model] = fileparts(modelPath);
pathBefore = path;
pwdBefore = string(pwd);
cleanup = onCleanup(@() localCleanup(model, pwdBefore, pathBefore)); %#ok<NASGU>
addpath(modelDir, "-begin");

evidence = struct;
evidence.schema = "simuverity.f90-xcomm04-evidence.v1";
evidence.task_id = def.formal_id;
evidence.generation_run_id = generationRunId;
evidence.model_path = modelPath;
evidence.model_file_presence = modelPresence;
evidence.reference_subject = logical(isReference);
evidence.adapter = ternary(isReference, ...
    "reference_native_signal_taps", ...
    "public_timeseries_contract");
evidence.reference_substantive_modifications = 0;
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.load_pass = false;
evidence.update_pass = false;
evidence.compile_pass = false;
evidence.scenarios = struct([]);
evidence.static_audit = struct;
evidence.errors = struct([]);
evidence.model_closed_without_save = false;
evidence.reference_binding_preserved = false;
evidence.started_at = localNow;
evidence.runtime = struct( ...
    "matlab_start_count", 1, ...
    "generation_run_id", generationRunId, ...
    "one_session_all_scenarios", true, ...
    "evidence_is_current_after_success", true);

fatal = [];
try
    cd(modelDir);
    load_system(modelPath);
    evidence.load_pass = true;
    originalInitFcn = string(get_param(model, "InitFcn"));
    originalStopFcn = string(get_param(model, "StopFcn"));
    originalMode = string(get_param(model, "SimulationMode"));
    set_param(model, ...
        "SimulationMode", "normal", ...
        "ReturnWorkspaceOutputs", "on", ...
        "SignalLogging", "on", ...
        "SignalLoggingName", "logsout", ...
        "LimitDataPoints", "off");
    if isReference
        set_param(model, "StopFcn", "");
        localInstallReferenceAdapter(model);
    end

    localApplyInputs(def.scenarios(1), isReference, struct);
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    if isReference
        native = localCaptureNativeWorkspace;
        set_param(model, "InitFcn", "");
    else
        native = struct;
    end
    feval(model, [], [], [], "compile");
    feval(model, [], [], [], "term");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model, isReference);

    rows = repmat(localEmptyRow, 0, 1);
    for index = 1:numel(def.scenarios)
        scenario = def.scenarios(index);
        row = localEmptyRow;
        row.id = string(scenario.id);
        row.requested_inputs = scenario;
        scenarioDir = fullfile(outDir, string(scenario.id));
        if ~isfolder(scenarioDir), mkdir(scenarioDir); end
        try
            cd(scenarioDir);
            localApplyInputs(scenario, isReference, native);
            localClearPublicOutputs(isReference, def.required_outputs);
            simIn = Simulink.SimulationInput(model);
            if isReference
                scenarioTx = localReferenceWaveform(native, scenario);
                scenarioStopTime = ...
                    (numel(scenarioTx) + double(native.DPDLatency)) * ...
                    double(native.Tstep);
                simIn = simIn.setVariable("txOutData", scenarioTx);
                simIn = simIn.setVariable("C_init", native.C_init);
                simIn = simIn.setVariable("fitCoefMat", ...
                    localReferencePaCoefficients(native, scenario));
                simIn = simIn.setVariable("stopTime", scenarioStopTime);
                simIn = simIn.setModelParameter( ...
                    "SimulationMode", "normal", ...
                    "SignalLogging", "on", ...
                    "SignalLoggingName", "logsout", ...
                    "ReturnWorkspaceOutputs", "on", ...
                    "LimitDataPoints", "off");
            else
                simIn = simIn.setModelParameter( ...
                    "SimulationMode", "normal", ...
                    "SignalLogging", "on", ...
                    "SignalLoggingName", "logsout", ...
                    "ReturnWorkspaceOutputs", "on", ...
                    "LimitDataPoints", "off");
            end
            timer = tic;
            simOut = sim(simIn);
            row.wall_seconds = toc(timer);
            row.simulation_pass = true;
            signals = localCollectSignals(simOut, scenario, ...
                isReference, native, def.required_outputs);
            row.raw_metrics = localRawMetrics(signals, ...
                def.sample_rate_hz, scenario);
            row.outputs_valid = localSignalsValid(signals, row.raw_metrics);
            artifact = fullfile(scenarioDir, "signals.mat");
            save(artifact, "-struct", "signals", "-v7");
            row.signal_artifact = localRelativePath(artifact, outDir);
            row.signal_file_presence = localFilePresence(artifact);
        catch ME
            row.error = localError(ME);
        end
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
    evidence.scenarios = rows;
    if isReference
        set_param(model, "InitFcn", originalInitFcn, ...
            "StopFcn", originalStopFcn, ...
            "SimulationMode", originalMode);
    end
catch ME
    fatal = ME;
    evidence.errors = localError(ME);
    try, feval(model, [], [], [], "term"); catch, end
end

try
    if bdIsLoaded(model)
        close_system(model, 0);
        evidence.model_closed_without_save = true;
    end
catch ME
    evidence.model_close_error = localError(ME);
end
evidence.reference_binding_preserved = ...
    (~isReference) || localFilePresence(modelPath) == def.reference_file_presence;
evidence.finished_at = localNow;
localWriteJson(evidencePath, evidence);
if ~isempty(fatal), rethrow(fatal); end
end

function native = localCaptureNativeWorkspace
names = [ ...
    "txOutData", "C_init", "fitCoefMat", "stopTime", ...
    "frameLen", "DPDLatency", "Tstep"];
for name = names
    assert(evalin("base", "exist('" + name + "','var')") == 1, ...
        "SimuVerity:F90:XCOMM04:NativeVariable", ...
        "Reference initialization did not create %s.", name);
    native.(name) = evalin("base", name);
end
end

function localInstallReferenceAdapter(model)
blocks = [ ...
    model + "/Baseband OFDM Transmitter", ...
    model + "/Switch", ...
    model + "/RF Subsystem", ...
    model + "/HDL DPD with LMS/DPD_LMS/LMS Coefficient Estimator", ...
    model + "/HDL DPD with LMS/DPD_LMS/LMS Coefficient Estimator/Add"];
ports = [1, 1, 1, 1, 1];
names = [ ...
    "f90_xcomm04_tx_native", ...
    "f90_xcomm04_dpd_drive", ...
    "f90_xcomm04_pa_output", ...
    "f90_xcomm04_coefficients", ...
    "f90_xcomm04_adaptation_error"];
for index = 1:numel(blocks)
    assert(getSimulinkBlockHandle(blocks(index), false) > 0, ...
        "SimuVerity:F90:XCOMM04:ReferenceLocator", ...
        "Required native signal source is missing: %s", blocks(index));
    handles = get_param(blocks(index), "PortHandles");
    assert(numel(handles.Outport) >= ports(index), ...
        "SimuVerity:F90:XCOMM04:ReferencePort", ...
        "Required output port is missing: %s/%d", ...
        blocks(index), ports(index));
    set_param(handles.Outport(ports(index)), ...
        "DataLogging", "on", ...
        "DataLoggingNameMode", "Custom", ...
        "DataLoggingName", names(index));
end
end

function localApplyInputs(scenario, isReference, native)
assignin("base", "InputScale", double(scenario.InputScale));
assignin("base", "PaNonlinearityScale", ...
    double(scenario.PaNonlinearityScale));
if ~isReference || isempty(fieldnames(native)), return, end
scenarioTx = localReferenceWaveform(native, scenario);
assignin("base", "txOutData", scenarioTx);
assignin("base", "C_init", native.C_init);
assignin("base", "fitCoefMat", ...
    localReferencePaCoefficients(native, scenario));
assignin("base", "stopTime", ...
    (numel(scenarioTx) + double(native.DPDLatency)) * double(native.Tstep));
end

function localClearPublicOutputs(isReference, names)
if isReference, return, end
for name = names
    evalin("base", "if exist('" + name + "','var'), clear " + name + "; end");
end
end

function signals = localCollectSignals(simOut, scenario, ...
    isReference, native, outputNames)
signals = struct;
signals.scenario_id = string(scenario.id);
signals.requested_input_scale = double(scenario.InputScale);
signals.requested_pa_nonlinearity_scale = ...
    double(scenario.PaNonlinearityScale);
if isReference
    logs = simOut.logsout;
    [signals.dpd_time, signals.dpd_drive] = ...
        localDatasetSignal(logs, "f90_xcomm04_dpd_drive");
    [signals.pa_time, signals.pa_output] = ...
        localDatasetSignal(logs, "f90_xcomm04_pa_output");
    [signals.coefficient_time, signals.adaptive_coefficients] = ...
        localDatasetSignal(logs, "f90_xcomm04_coefficients");
    [signals.error_time, signals.adaptation_error] = ...
        localDatasetSignal(logs, "f90_xcomm04_adaptation_error");
    signals.tx_baseband = localReferenceWaveform(native, scenario);
    signals.tx_time = (0:numel(signals.tx_baseband)-1)' / 15360000;
else
    values = cell(1, numel(outputNames));
    for index = 1:numel(outputNames)
        values{index} = localPublicOutput(simOut, outputNames(index));
    end
    [signals.tx_time, signals.tx_baseband] = localTimeseries(values{1});
    [signals.dpd_time, signals.dpd_drive] = localTimeseries(values{2});
    [signals.pa_time, signals.pa_output] = localTimeseries(values{3});
    [signals.coefficient_time, signals.adaptive_coefficients] = ...
        localTimeseries(values{4});
    [signals.error_time, signals.adaptation_error] = ...
        localTimeseries(values{5});
end
signals.tx_baseband = localVector(signals.tx_baseband);
signals.dpd_drive = localVector(signals.dpd_drive);
signals.pa_output = localVector(signals.pa_output);
signals.adaptation_error = localVector(signals.adaptation_error);
signals.adaptive_coefficients = localCoefficientMatrix( ...
    signals.adaptive_coefficients, numel(signals.coefficient_time));
end

function waveform = localReferenceWaveform(native, scenario)
sampleCount = min(numel(native.txOutData), 3 * double(native.frameLen));
waveform = native.txOutData(1:sampleCount);
waveform = waveform(:) * double(scenario.InputScale);
end

function coefficients = localReferencePaCoefficients(native, scenario)
coefficients = native.fitCoefMat;
scale = double(scenario.PaNonlinearityScale);
if numel(coefficients) > 1
    nonlinear = true(size(coefficients));
    nonlinear(1) = false;
    coefficients(nonlinear) = coefficients(nonlinear) * scale;
end
end

function value = localPublicOutput(simOut, name)
value = simuverity_public_output_compatibility( ...
    simOut,string(name),[],AllowBaseWorkspace=true);
end

function [time, data] = localDatasetSignal(logs, name)
assert(isa(logs, "Simulink.SimulationData.Dataset"), ...
    "SimuVerity:F90:XCOMM04:LogsoutType", "logsout is not a Dataset.");
element = logs.getElement(name);
assert(~isempty(element), "SimuVerity:F90:XCOMM04:LoggedSignal", ...
    "Required logged signal is missing: %s", name);
[time, data] = localTimeseries(element.Values);
end

function [time, data] = localTimeseries(value)
assert(isa(value, "timeseries"), "SimuVerity:F90:XCOMM04:Timeseries", ...
    "Required output is not a MATLAB Timeseries.");
time = double(value.Time(:));
data = double(value.Data);
assert(~isempty(time) && ~isempty(data), "SimuVerity:F90:XCOMM04:EmptyTimeseries");
end

function metrics = localRawMetrics(signals, sampleRate, scenario)
[txPa, pa, delayPa] = localAlign(signals.tx_baseband, ...
    signals.pa_output, 4096);
[txDrive, drive, delayDrive] = localAlign(signals.tx_baseband, ...
    signals.dpd_drive, 4096);
[drivePa, paForDrive, delayDrivePa] = localAlign( ...
    signals.dpd_drive, signals.pa_output, 4096);

[paNmseDb, paEvmPercent, paCorrelation, paGain] = ...
    localPairMetrics(txPa, pa);
[driveNmseDb, ~, driveCorrelation, driveGain] = ...
    localPairMetrics(txDrive, drive);
[~, ~, drivePaCorrelation, ~] = ...
    localPairMetrics(drivePa, paForDrive);

coeff = signals.adaptive_coefficients;
coeffFinite = all(isfinite(real(coeff)) & isfinite(imag(coeff)), 2);
coeff = coeff(coeffFinite, :);
if size(coeff, 1) >= 4
    split = max(1, floor(size(coeff, 1) * 0.2));
    firstCoeff = mean(coeff(1:split, :), 1);
    lastCoeff = mean(coeff(end-split+1:end, :), 1);
    coeffChange = norm(lastCoeff - firstCoeff) / ...
        max(norm(firstCoeff), 1e-9);
    coefficientDelta = diff(coeff, 1, 1);
    coeffUpdateRms = sqrt(mean(abs(coefficientDelta).^2, "all"));
    updateSplit = max(1, floor(size(coefficientDelta, 1) * 0.25));
    coeffEarlyUpdateRms = sqrt(mean( ...
        abs(coefficientDelta(1:updateSplit, :)).^2, "all"));
    coeffLateUpdateRms = sqrt(mean( ...
        abs(coefficientDelta(end-updateSplit+1:end, :)).^2, "all"));
    coeffSettlingRatio = coeffLateUpdateRms / ...
        max(coeffEarlyUpdateRms, 1e-15);
    coeffMax = max(abs(coeff), [], "all");
else
    coeffChange = NaN;
    coeffUpdateRms = NaN;
    coeffEarlyUpdateRms = NaN;
    coeffLateUpdateRms = NaN;
    coeffSettlingRatio = NaN;
    coeffMax = NaN;
end

err = signals.adaptation_error;
err = err(isfinite(real(err)) & isfinite(imag(err)));
active = abs(err) > max(1e-12, 1e-9 * max(abs(err), [], "omitnan"));
if nnz(active) >= 20, err = err(active); end
if numel(err) >= 20
    section = max(5, floor(numel(err) * 0.2));
    earlyRms = sqrt(mean(abs(err(1:section)).^2));
    lateRms = sqrt(mean(abs(err(end-section+1:end)).^2));
    errorReductionDb = 20 * log10(max(earlyRms, 1e-15) / ...
        max(lateRms, 1e-15));
else
    earlyRms = NaN;
    lateRms = NaN;
    errorReductionDb = NaN;
end

metrics = struct;
metrics.sample_count = struct( ...
    "tx", numel(signals.tx_baseband), ...
    "dpd_drive", numel(signals.dpd_drive), ...
    "pa_output", numel(signals.pa_output), ...
    "adaptive_coefficients", size(signals.adaptive_coefficients, 1), ...
    "adaptation_error", numel(signals.adaptation_error));
metrics.aligned_sample_count = numel(txPa);
metrics.alignment_delay_samples = struct( ...
    "tx_to_pa", delayPa, ...
    "tx_to_dpd", delayDrive, ...
    "dpd_to_pa", delayDrivePa);
metrics.pa_nmse_db = paNmseDb;
metrics.pa_evm_percent = paEvmPercent;
metrics.pa_correlation = paCorrelation;
metrics.pa_complex_gain_abs = abs(paGain);
metrics.pa_complex_gain_phase_deg = rad2deg(angle(paGain));
metrics.dpd_relative_error_db = driveNmseDb;
metrics.dpd_correlation_to_tx = driveCorrelation;
metrics.dpd_complex_gain_abs = abs(driveGain);
metrics.dpd_to_pa_correlation = drivePaCorrelation;
metrics.pa_aclr_db = localAclr(signals.pa_output, sampleRate);
metrics.tx_aclr_db = localAclr(signals.tx_baseband, sampleRate);
metrics.coefficient_change_norm = coeffChange;
metrics.coefficient_update_rms = coeffUpdateRms;
metrics.coefficient_early_update_rms = coeffEarlyUpdateRms;
metrics.coefficient_late_update_rms = coeffLateUpdateRms;
metrics.coefficient_settling_ratio = coeffSettlingRatio;
metrics.coefficient_max_abs = coeffMax;
metrics.error_early_rms = earlyRms;
metrics.error_late_rms = lateRms;
metrics.error_reduction_db = errorReductionDb;
metrics.requested_input_scale = double(scenario.InputScale);
metrics.requested_pa_nonlinearity_scale = ...
    double(scenario.PaNonlinearityScale);
metrics.observed_tx_rms = sqrt(mean(abs(signals.tx_baseband).^2));
metrics.observed_pa_rms = sqrt(mean(abs(signals.pa_output).^2));
metrics.finite_fraction = localFiniteFraction(signals);
end

function valid = localSignalsValid(signals, metrics)
counts = [ ...
    metrics.sample_count.tx, ...
    metrics.sample_count.dpd_drive, ...
    metrics.sample_count.pa_output, ...
    metrics.sample_count.adaptive_coefficients, ...
    metrics.sample_count.adaptation_error];
valid = all(counts >= 20) && ...
    metrics.aligned_sample_count >= 100 && ...
    metrics.finite_fraction >= 0.999999 && ...
    numel(signals.tx_time) >= 20 && ...
    numel(signals.pa_time) >= 20 && ...
    size(signals.adaptive_coefficients, 2) >= 1;
end

function [x, y, delay] = localAlign(x, y, maxLag)
x = localVector(x);
y = localVector(y);
x = x(isfinite(real(x)) & isfinite(imag(x)));
y = y(isfinite(real(y)) & isfinite(imag(y)));
assert(numel(x) >= 100 && numel(y) >= 100, ...
    "SimuVerity:F90:XCOMM04:AlignmentSamples");
maxLag = min([maxLag, numel(x)-2, numel(y)-2]);
delay = finddelay(x, y, maxLag);
if delay >= 0
    count = min(numel(x), numel(y)-delay);
    x = x(1:count);
    y = y(1+delay:delay+count);
else
    shift = -delay;
    count = min(numel(x)-shift, numel(y));
    x = x(1+shift:shift+count);
    y = y(1:count);
end
startIndex = max(1, floor(numel(x) * 0.30));
x = x(startIndex:end);
y = y(startIndex:end);
active = abs(x) > max(1e-12, 1e-8 * max(abs(x), [], "omitnan"));
if nnz(active) >= 100
    x = x(active);
    y = y(active);
end
end

function [nmseDb, evmPercent, correlation, gain] = localPairMetrics(x, y)
den = x' * x;
assert(abs(den) > 0, "SimuVerity:F90:XCOMM04:PairEnergy");
gain = (x' * y) / den;
reference = gain * x;
residual = y - reference;
ratio = sum(abs(residual).^2) / max(sum(abs(reference).^2), 1e-30);
nmseDb = 10 * log10(max(ratio, 1e-30));
evmPercent = 100 * sqrt(max(ratio, 0));
correlation = abs(x' * y) / ...
    max(sqrt(sum(abs(x).^2) * sum(abs(y).^2)), 1e-30);
end

function value = localAclr(signal, sampleRate)
signal = localVector(signal);
signal = signal(isfinite(real(signal)) & isfinite(imag(signal)));
if numel(signal) < 512
    value = NaN;
    return
end
signal = signal(max(1, floor(numel(signal) * 0.30)):end);
signal = signal - mean(signal);
n = numel(signal);
window = 0.5 - 0.5 * cos(2*pi*(0:n-1)'/max(n-1, 1));
nfft = 2^nextpow2(n);
spectrum = abs(fftshift(fft(signal .* window, nfft))).^2;
frequency = ((-nfft/2):(nfft/2-1))' * sampleRate / nfft;
inband = abs(frequency) <= 0.95e6;
adjacent = abs(frequency) >= 1.15e6 & abs(frequency) <= 3.05e6;
pin = sum(spectrum(inband));
padj = sum(spectrum(adjacent)) / 2;
value = 10 * log10(max(pin, 1e-30) / max(padj, 1e-30));
end

function fraction = localFiniteFraction(signals)
values = {signals.tx_baseband, signals.dpd_drive, signals.pa_output, ...
    signals.adaptive_coefficients, signals.adaptation_error};
finiteCount = 0;
totalCount = 0;
for index = 1:numel(values)
    value = values{index};
    totalCount = totalCount + numel(value);
    finiteCount = finiteCount + nnz( ...
        isfinite(real(value)) & isfinite(imag(value)));
end
fraction = finiteCount / max(totalCount, 1);
end

function audit = localStaticAudit(model, isReference)
audit = struct;
audit.model_block_count = numel(find_system(model, ...
    "LookUnderMasks", "all", "FollowLinks", "on", "Type", "Block"));
if isReference
    root = model + "/";
    adaptive = model + "/HDL DPD with LMS/DPD_LMS/";
    audit.tx_path_connected = localDirectConnection( ...
        root + "Baseband OFDM Transmitter", 1, ...
        root + "Data Type Conversion", 1);
    audit.dpd_to_pa_connected = localDirectConnection( ...
        root + "Switch", 1, root + "RF Subsystem", 1);
    audit.pa_observation_connected = localDirectConnection( ...
        root + "RF Subsystem", 1, root + "Data Type Conversion2", 1);
    audit.coefficient_recirculation_connected = localDirectConnection( ...
        adaptive + "LMS Coefficient Estimator", 1, ...
        adaptive + "Digital Predistorter", 3);
    audit.closed_loop_adaptive_path = audit.tx_path_connected && ...
        audit.dpd_to_pa_connected && audit.pa_observation_connected && ...
        audit.coefficient_recirculation_connected;
else
    blocks = find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "BlockType", "ToWorkspace");
    variables = strings(numel(blocks), 1);
    for index = 1:numel(blocks)
        variables(index) = string(get_param(blocks{index}, "VariableName"));
    end
    required = ["TxBaseband", "PredistortedDrive", "PaOutput", ...
        "AdaptiveCoefficients", "AdaptationError"];
    audit.public_output_sink_count = nnz(ismember(required, variables));
    audit.distinct_public_output_sinks = ...
        numel(unique(variables(ismember(variables, required))));
    audit.closed_loop_adaptive_path = ...
        audit.distinct_public_output_sinks == numel(required);
end
end

function connected = localDirectConnection(src, srcPort, dst, dstPort)
srcHandles = get_param(src, "PortHandles");
dstHandles = get_param(dst, "PortHandles");
line = get_param(srcHandles.Outport(srcPort), "Line");
connected = false;
if line <= 0, return, end
destinationPorts = get_param(line, "DstPortHandle");
connected = any(destinationPorts == dstHandles.Inport(dstPort));
end

function row = localEmptyRow
row = struct( ...
    "id", "", ...
    "requested_inputs", struct, ...
    "simulation_pass", false, ...
    "outputs_valid", false, ...
    "wall_seconds", NaN, ...
    "raw_metrics", struct, ...
    "signal_artifact", "", ...
    "signal_file_presence", "", ...
    "error", struct);
end

function matrix = localCoefficientMatrix(value, timeCount)
value = squeeze(double(value));
if isvector(value)
    matrix = value(:);
    return
end
dimensions = size(value);
if dimensions(1) == timeCount
    matrix = reshape(value, timeCount, []);
elseif dimensions(end) == timeCount
    order = [ndims(value), 1:ndims(value)-1];
    value = permute(value, order);
    matrix = reshape(value, timeCount, []);
else
    matrix = reshape(value, dimensions(1), []);
end
end

function value = localVector(value)
value = squeeze(double(value));
if isvector(value)
    value = value(:);
elseif size(value, 2) == 1
    value = value(:, 1);
else
    value = value(:);
end
end

function relative = localRelativePath(pathValue, root)
relative = replace(string(pathValue), string(root) + filesep, "");
relative = replace(relative, "\", "/");
end

function localConfigureIsolation
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
if strlength(cache) > 0 && strlength(codegen) > 0
    Simulink.fileGenControl("set", ...
        "CacheFolder", cache, ...
        "CodeGenFolder", codegen, ...
        "createDir", true);
end
set(groot, "defaultFigureVisible", "off");
end

function localCleanup(model, oldDir, oldPath)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch
end
try, cd(oldDir); catch, end
path(oldPath);
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function value = localNow
value = string(datetime("now", "TimeZone", "local", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function value = localError(ME)
value = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message));
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XCOMM04:JsonOpen", ...
    "Cannot write evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function value = ternary(condition, yes, no)
if condition, value = yes; else, value = no; end
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
