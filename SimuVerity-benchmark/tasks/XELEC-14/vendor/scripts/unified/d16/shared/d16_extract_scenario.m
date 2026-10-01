function r = d16_extract_scenario(spec, modelName, mode, scenarioId)
%D16_EXTRACT_SCENARIO Simulation and raw measurement extraction only.
%
% This path performs load/update/simulate and evidence extraction only. Band
% utilities, group aggregation and total-score calculation remain in Python.

if nargin < 3 || isempty(mode), mode = "agent"; end
if nargin < 4 || isempty(scenarioId), scenarioId = "nominal"; end
scenarioId = char(string(scenarioId));
r = empty_result(spec, mode, scenarioId);

try
    set_param(modelName, "StopTime", ...
        num2str(double(spec.sim.stop), "%.17g"));
    solver = getstr(spec.sim, "solver", "");
    if ~isempty(solver) && ~strcmpi(solver, "null")
        set_param(modelName, "Solver", solver);
    end
    if isfield(spec.sim, "max_step") && isnumeric(spec.sim.max_step) && ...
            isscalar(spec.sim.max_step) && isfinite(spec.sim.max_step) && ...
            spec.sim.max_step > 0
        set_param(modelName, "MaxStep", ...
            num2str(double(spec.sim.max_step), "%.17g"));
    end
    try, set_param(modelName, "StopFcn", ""); catch, end
catch e
    r.failure_stage = "configuration";
    r.error_identifier = safe_identifier(e);
    r.error_message = string(strtrim(e.message));
    r.detail = "CONFIG_FAIL:" + safe_identifier(e);
    return;
end

r.task_prepare_state = sat_prepare_task_specific( ...
    modelName, spec, scenarioId);
try
    set_param(modelName, "SimulationCommand", "update");
    r.stage = "compiled";
catch e
    r.failure_stage = "compile";
    r.error_identifier = safe_identifier(e);
    r.error_message = string(strtrim(e.message));
    r.detail = "COMPILE_FAIL:" + safe_identifier(e);
    return;
end

if strcmpi(mode, "golden")
    r.tap_reports = sat_prepare_golden(modelName, spec);
    r.tap_ok = core_taps_ok(spec, r.tap_reports);
else
    r.tap_ok = true;
end

[r.topology_ok, ~, r.struct_detail, r.struct_reports] = ...
    sat_eval_struct(modelName, spec.structural);
[r.input_ok, r.input_reports] = sat_input_contract( ...
    modelName, spec, mode);

try
    simOut = sim(modelName, "ReturnWorkspaceOutputs", "on");
    r.stage = "simulated";
catch e
    r.failure_stage = "simulation";
    r.error_identifier = safe_identifier(e);
    r.error_message = string(strtrim(e.message));
    r.detail = "SIM_FAIL:" + safe_identifier(e);
    return;
end

[sig, r.core_ok, r.provenance_ok, r.output_reports] = ...
    sat_output_contract(simOut, modelName, spec);
r.contract_ok = r.core_ok && r.provenance_ok && r.tap_ok;

if isfield(spec, "behavioral") && ~isempty(spec.behavioral)
    declaredBands = spec.behavioral;
    for i = 1:numel_any(declaredBands)
        band = elem(declaredBands, i);
        band = apply_task_steady_policy(band, spec);
        bandScenario = getstr(band, "scenario", "nominal");
        if ~strcmpi(bandScenario, scenarioId) && ...
                ~strcmpi(bandScenario, "all")
            continue;
        end
        [signals, got, label] = resolve_signals(sig, band);
        metricName = getstr(band, "metric", "");
        value = NaN;
        valid = false;
        metricDetail = "SIGNAL_MISSING";
        if got
            [value, valid, metricDetail] = sat_metrics( ...
                metricName, signals, band);
        end
        group = lower(getstr(band, "group", ...
            tern(strcmpi(scenarioId, "nominal"), ...
            "nominal", "robustness")));
        criticality = lower(getstr(band, "criticality", "quality"));
        weight = getnum(band, "weight", 1);
        if strcmp(criticality, "diagnostic"), weight = 0; end
        r.band_measurements(end + 1) = struct( ... %#ok<AGROW>
            "id", string(getstr(band, "id", sprintf("b%d", i))), ...
            "scenario", string(bandScenario), ...
            "group", string(group), ...
            "criticality", string(criticality), ...
            "metric", string(metricName), ...
            "signals", string(label), ...
            "valid", logical(valid), ...
            "value", value, ...
            "weight", weight, ...
            "detail", string(metricDetail), ...
            "band_contract", band);
    end
end

% Existing D-specific checks are semantic/physical evidence extractors.  Their
% report.score fields are never consumed by the SimuVerity offline scorers;
% the raw report evidence plus evaluated/valid/ok predicates are retained.
baseReports = struct( ...
    "struct_reports", r.struct_reports, ...
    "input_reports", r.input_reports, ...
    "output_reports", r.output_reports, ...
    "band_reports", compatibility_band_reports(r.band_measurements));
[r.task_oracle_reports, r.task_extractor_diagnostics] = ...
    d16_eval_task_specific( ...
    modelName, spec, scenarioId, simOut, sig, baseReports, ...
    r.task_prepare_state);
r.task_measurements = task_measurements(sig, spec, scenarioId);
[r.topology_ok, taskNominalOk, taskRobustOk] = fold_task_reports( ...
    r.task_oracle_reports, r.topology_ok);
r.qualification_ok = r.stage == "simulated" && r.topology_ok && ...
    r.input_ok && r.contract_ok;
r.nominal_evidence_ok = r.qualification_ok && taskNominalOk;
r.robustness_evidence_ok = r.qualification_ok && taskRobustOk;
r.detail = gate_detail(r);
end

function r = empty_result(spec, mode, scenario)
r = struct( ...
    "schema", "simuverity.d16-scenario-evidence.v1", ...
    "id", string(spec.id), ...
    "mode", string(mode), ...
    "scenario", string(scenario), ...
    "stage", "loaded", ...
    "topology_ok", false, ...
    "input_ok", false, ...
    "tap_ok", false, ...
    "core_ok", false, ...
    "provenance_ok", false, ...
    "contract_ok", false, ...
    "qualification_ok", false, ...
    "nominal_evidence_ok", false, ...
    "robustness_evidence_ok", false, ...
    "failure_stage", "", ...
    "error_identifier", "", ...
    "error_message", "", ...
    "tap_reports", struct([]), ...
    "input_reports", struct([]), ...
    "output_reports", struct([]), ...
    "struct_reports", struct([]), ...
    "struct_detail", "", ...
    "task_prepare_state", struct(), ...
    "task_oracle_reports", empty_task_reports(), ...
    "task_extractor_diagnostics", struct(), ...
    "task_measurements", struct(), ...
    "band_measurements", empty_band_measurements(), ...
    "detail", "UNINITIALIZED");
end

function rows = empty_band_measurements()
rows = struct( ...
    "id", {}, "scenario", {}, "group", {}, "criticality", {}, ...
    "metric", {}, "signals", {}, "valid", {}, "value", {}, ...
    "weight", {}, "detail", {}, "band_contract", {});
end

function rows = compatibility_band_reports(measurements)
rows = struct( ...
    "id", {}, "scenario", {}, "group", {}, "criticality", {}, ...
    "metric", {}, "signals", {}, "valid", {}, "value", {}, ...
    "score", {}, "weight", {}, "detail", {});
for i = 1:numel(measurements)
    m = measurements(i);
    rows(end + 1) = struct( ... %#ok<AGROW>
        "id", m.id, "scenario", m.scenario, "group", m.group, ...
        "criticality", m.criticality, "metric", m.metric, ...
        "signals", m.signals, "valid", m.valid, "value", m.value, ...
        "score", 0, "weight", m.weight, "detail", m.detail);
end
end

function metrics = task_measurements(sig, spec, scenarioId)
metrics = struct();
if ~isfield(spec, "id"), return; end
switch upper(string(spec.id))
    case "D006"
        metrics = sat_d006_measure(sig, spec, scenarioId);
    case "D007"
        metrics = sat_d007_measure(sig, spec, scenarioId);
    case "D008"
        metrics = sat_d008_measure(sig, spec, scenarioId);
    case "D011"
        metrics = sat_d011_measure(sig, spec, scenarioId);
    case "D012"
        metrics = sat_d012_measure(sig, spec, scenarioId);
    case "D014"
        metrics = sat_d014_measure(sig, spec, scenarioId);
    case "D022"
        metrics = sat_d022_measure(sig, spec, scenarioId);
    case "D023"
        metrics = sat_d023_measure(sig, spec, scenarioId);
    case "D025"
        metrics = sat_d025_measure(sig, spec, scenarioId);
    case "D027"
        metrics = sat_d027_measure(sig, spec, scenarioId);
    case "D028"
        metrics = sat_d028_measure(sig, spec, scenarioId);
end
end

function [topologyOk, nominalOk, robustnessOk] = ...
        fold_task_reports(reports, topologyOk)
nominalOk = true;
robustnessOk = true;
for i = 1:numel(reports)
    row = reports(i);
    if ~row.mandatory, continue; end
    passed = row.evaluated && row.valid && row.ok;
    semantic = lower(string(row.semantic_kind));
    layer = lower(string(row.layer));
    if semantic == "structure" || layer == "qualification"
        topologyOk = topologyOk && passed;
    elseif layer == "nominal"
        nominalOk = nominalOk && passed;
    elseif layer == "robustness"
        robustnessOk = robustnessOk && passed;
    end
end
end

function rows = empty_task_reports()
rows = struct( ...
    "task", {}, "id", {}, "kind", {}, "semantic_kind", {}, ...
    "scenario", {}, "layer", {}, "evaluated", {}, "mandatory", {}, ...
    "ok", {}, "valid", {}, "score", {}, "detail", {}, "evidence", {});
end

function ok = core_taps_ok(spec, reports)
ok = true;
for i = 1:numel_any(spec.outputs)
    output = elem(spec.outputs, i);
    if ~strcmpi(getstr(output, "role", "core"), "core"), continue; end
    name = string(output.name);
    index = find([reports.name] == name, 1);
    if isempty(index) || ~reports(index).ok
        ok = false;
        return;
    end
end
end

function [signals, got, label] = resolve_signals(sig, band)
signals = {};
got = true;
if isfield(band, "signals") && ~isempty(band.signals)
    names = band.signals;
    if ~iscell(names), names = cellstr(string(names)); end
else
    names = {getstr(band, "signal", "")};
end
label = strjoin(cellstr(string(names)), ",");
for i = 1:numel(names)
    key = matlab.lang.makeValidName(char(string(names{i})));
    if isempty(key) || ~isfield(sig, key)
        got = false;
        return;
    end
    signals{end + 1} = sig.(key); %#ok<AGROW>
end
end

function detail = gate_detail(r)
issues = strings(0, 1);
if ~r.topology_ok, issues(end + 1) = "topology"; end %#ok<AGROW>
if ~r.input_ok, issues(end + 1) = "input_contract"; end %#ok<AGROW>
if ~r.tap_ok, issues(end + 1) = "golden_tap"; end %#ok<AGROW>
if ~r.core_ok, issues(end + 1) = "core_contract"; end %#ok<AGROW>
if ~r.provenance_ok, issues(end + 1) = "provenance"; end %#ok<AGROW>
if isempty(issues), detail = "OK";
else, detail = "QUALIFICATION_FAIL:" + strjoin(issues, "+");
end
end

function band = apply_task_steady_policy(band, spec)
if ~isstruct(spec) || ~isfield(spec, "steady_state_policy") || ...
        ~isstruct(spec.steady_state_policy)
    return;
end
policy = spec.steady_state_policy;
names = fieldnames(policy);
for i = 1:numel(names)
    if ~isfield(band, names{i}), band.(names{i}) = policy.(names{i}); end
end
end

function value = safe_identifier(errorValue)
value = string(errorValue.identifier);
if strlength(value) == 0, value = "UNCLASSIFIED"; end
end
function n = numel_any(value), n = numel(value); end
function value = elem(values, index)
if iscell(values), value = values{index}; else, value = values(index); end
end
function value = getnum(row, field, default)
value = default;
if isfield(row, field) && ~isempty(row.(field)) && ...
        isnumeric(row.(field)) && isscalar(row.(field))
    value = double(row.(field));
end
end
function value = getstr(row, field, default)
% Always return char, including for an empty default.  A MATLAB empty
% string scalar ("") is not isempty, which previously caused solver=[]
% specs to reach set_param(...,"Solver","") and fail every D16 route.
value = char(string(default));
if isfield(row, field) && ~isempty(row.(field))
    value = char(string(row.(field)));
end
end
function value = tern(condition, yes, no)
if condition, value = yes; else, value = no; end
end
