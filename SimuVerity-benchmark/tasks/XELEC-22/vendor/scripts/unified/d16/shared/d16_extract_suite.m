function suite = d16_extract_suite(spec, modelPath, mode)
%D16_EXTRACT_SUITE Run every declared scenario and retain raw evidence.
%
% No direct scorer is reachable from this function.  Witness predicates and
% D-specific structural/causal checks are retained as evaluator evidence.

if nargin < 3 || isempty(mode), mode = "agent"; end
scenarioIds = {"nominal"};
scenarioRows = {struct("id", "nominal", "required", true)};
if isfield(spec, "scenarios") && ~isempty(spec.scenarios)
    for i = 1:numel_any(spec.scenarios)
        scenario = elem(spec.scenarios, i);
        scenarioIds{end + 1} = string(scenario.id); %#ok<AGROW>
        scenarioRows{end + 1} = scenario; %#ok<AGROW>
    end
end

results = cell(1, numel(scenarioIds));
for i = 1:numel(scenarioIds)
    scenario = scenarioRows{i};
    modelName = "";
    try
        load_system(modelPath);
        modelName = bdroot_from_path(modelPath);
        apply_defaults(spec);
        if i > 1, apply_scenario(modelName, scenario, mode); end
        results{i} = d16_extract_scenario( ...
            spec, modelName, mode, scenarioIds{i});
    catch e
        results{i} = failed_scenario(spec, scenarioIds{i}, e);
    end
    if strlength(modelName) > 0
        try, close_system(modelName, 0); catch, end
    end
end

nominal = results{1};
requiredOk = true;
allWitnessesOk = true;
for i = 2:numel(results)
    scenario = scenarioRows{i};
    row = results{i};
    [witnessOk, witnessReports] = evaluate_witnesses( ...
        nominal, row, scenario);
    row.witness_ok = witnessOk;
    row.witness_reports = witnessReports;
    results{i} = row;
    required = getbool(scenario, "required", true);
    if required && (~getbool(row, "qualification_ok", false) || ...
            ~witnessOk)
        requiredOk = false;
    end
    allWitnessesOk = allWitnessesOk && (~required || witnessOk);
end

suite = struct( ...
    "schema", "simuverity.d16-suite-evidence.v1", ...
    "id", string(spec.id), ...
    "mode", string(mode), ...
    "nominal", nominal, ...
    "scenario_results", {results(2:end)}, ...
    "required_scenarios_ok", requiredOk, ...
    "required_witnesses_ok", allWitnessesOk, ...
    "task_oracle_reports", empty_task_reports(), ...
    "direct_scorer_called", false, ...
    "score_total_present", false);
suite.task_oracle_reports = sat_eval_task_specific_suite(spec, suite);
for i = 1:numel(suite.task_oracle_reports)
    report = suite.task_oracle_reports(i);
    if report.mandatory && ~(report.evaluated && report.valid && report.ok)
        requiredOk = false;
        allWitnessesOk = false;
    end
end
suite.required_scenarios_ok = requiredOk;
suite.required_witnesses_ok = allWitnessesOk;
end

function row = failed_scenario(spec, scenarioId, errorValue)
identifier = string(errorValue.identifier);
if strlength(identifier) == 0, identifier = "UNCLASSIFIED"; end
row = struct( ...
    "schema", "simuverity.d16-scenario-evidence.v1", ...
    "id", string(spec.id), ...
    "mode", "agent", ...
    "scenario", string(scenarioId), ...
    "stage", "suite_error", ...
    "topology_ok", false, ...
    "input_ok", false, ...
    "tap_ok", false, ...
    "core_ok", false, ...
    "provenance_ok", false, ...
    "contract_ok", false, ...
    "qualification_ok", false, ...
    "nominal_evidence_ok", false, ...
    "robustness_evidence_ok", false, ...
    "failure_stage", "suite", ...
    "error_identifier", identifier, ...
    "error_message", string(strtrim(errorValue.message)), ...
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
    "detail", "SUITE_ERROR:" + identifier);
end

function [ok, reports] = evaluate_witnesses(nominal, scenario, declaration)
reports = struct( ...
    "id", {}, "nominal_band", {}, "scenario_band", {}, ...
    "relation", {}, "nominal_value", {}, "scenario_value", {}, ...
    "observed", {}, "threshold", {}, "ok", {}, "valid", {}, ...
    "evaluated", {}, "kind", {}, "message", {});
if ~isfield(declaration, "witnesses") || isempty(declaration.witnesses)
    ok = false;
    reports(1) = witness_row( ...
        "missing", "", "", "required", NaN, NaN, NaN, NaN, ...
        false, false, "NO_INTERVENTION_WITNESS");
    return;
end
rows = declaration.witnesses;
ok = true;
for i = 1:numel_any(rows)
    witness = elem(rows, i);
    id = getstr(witness, "id", sprintf("w%d", i));
    nominalBand = getstr(witness, "nominal_band", "");
    scenarioBand = getstr(witness, "scenario_band", "");
    relation = lower(getstr(witness, "relation", "relative_change_min"));
    threshold = getnum(witness, "threshold", NaN);
    [nominalValue, nominalOk] = band_value(nominal, nominalBand);
    [scenarioValue, scenarioOk] = band_value(scenario, scenarioBand);
    observed = NaN;
    passed = false;
    valid = nominalOk && scenarioOk;
    message = "BAND_MISSING_OR_INVALID";
    if valid
        denominator = max(abs(nominalValue), ...
            getnum(witness, "denominator_floor", 1e-9));
        switch relation
            case "relative_change_min"
                observed = abs(scenarioValue - nominalValue) / denominator;
                passed = isfinite(threshold) && observed >= threshold;
            case "increase_frac_min"
                observed = (scenarioValue - nominalValue) / denominator;
                passed = isfinite(threshold) && observed >= threshold;
            case "decrease_frac_min"
                observed = (nominalValue - scenarioValue) / denominator;
                passed = isfinite(threshold) && observed >= threshold;
            case "absolute_delta_min"
                observed = abs(scenarioValue - nominalValue);
                passed = isfinite(threshold) && observed >= threshold;
            case "ratio_range"
                observed = scenarioValue / nominalValue;
                low = getnum(witness, "min_ratio", NaN);
                high = getnum(witness, "max_ratio", NaN);
                threshold = low;
                passed = isfinite(observed) && isfinite(low) && ...
                    isfinite(high) && observed >= low && observed <= high;
            otherwise
                message = "UNKNOWN_RELATION:" + relation;
        end
        if ~startsWith(message, "UNKNOWN_")
            if passed, message = "OK"; else, message = "WITNESS_THRESHOLD_FAIL"; end
        end
    end
    reports(end + 1) = witness_row( ... %#ok<AGROW>
        id, nominalBand, scenarioBand, relation, nominalValue, ...
        scenarioValue, observed, threshold, passed, valid, message);
    ok = ok && passed;
end
end

function [value, ok] = band_value(row, id)
value = NaN;
ok = false;
if ~isstruct(row) || ~isfield(row, "band_measurements") || ...
        isempty(row.band_measurements)
    return;
end
index = find(strcmp(string({row.band_measurements.id}), string(id)), 1);
if isempty(index), return; end
measurement = row.band_measurements(index);
value = measurement.value;
ok = measurement.valid && isfinite(value);
end

function row = witness_row(id, nominalBand, scenarioBand, relation, ...
        nominalValue, scenarioValue, observed, threshold, passed, valid, message)
row = struct( ...
    "id", string(id), ...
    "nominal_band", string(nominalBand), ...
    "scenario_band", string(scenarioBand), ...
    "relation", string(relation), ...
    "nominal_value", nominalValue, ...
    "scenario_value", scenarioValue, ...
    "observed", observed, ...
    "threshold", threshold, ...
    "ok", logical(passed), ...
    "valid", logical(valid), ...
    "evaluated", logical(valid), ...
    "kind", "witness", ...
    "message", string(message));
end

function apply_defaults(spec)
if ~isfield(spec, "input_contract") || isempty(spec.input_contract), return; end
names = fieldnames(spec.input_contract);
for i = 1:numel(names)
    value = spec.input_contract.(names{i});
    if isstruct(value) && isfield(value, "default")
        assignin("base", names{i}, value.default);
    elseif isnumeric(value)
        assignin("base", names{i}, value);
    end
end
end

function apply_scenario(modelName, scenario, mode)
if isfield(scenario, "agent_variables") && ~isempty(scenario.agent_variables)
    names = fieldnames(scenario.agent_variables);
    for i = 1:numel(names)
        assignin("base", names{i}, scenario.agent_variables.(names{i}));
    end
end
if strcmpi(mode, "golden") && isfield(scenario, "golden_set_param") && ...
        ~isempty(scenario.golden_set_param)
    rows = scenario.golden_set_param;
    for i = 1:numel_any(rows)
        row = elem(rows, i);
        if isfield(row, "path_regex")
            pattern = char(string(row.path_regex));
            blocks = find_system(modelName, "LookUnderMasks", "on", ...
                "FollowLinks", "on", "Type", "Block");
            hits = {};
            for q = 1:numel(blocks)
                relative = extractAfter(string(blocks{q}), ...
                    strlength(string(modelName)) + 1);
                if ~isempty(regexpi(relative, pattern, "once"))
                    hits{end + 1} = blocks{q}; %#ok<AGROW>
                end
            end
            if numel(hits) ~= 1
                error("SimuVerity:UnifiedD16:ScenarioPath", ...
                    "scenario path_regex matched %d blocks", numel(hits));
            end
            pathValue = hits{1};
        else
            pathValue = char(string(row.path));
            if ~startsWith(string(pathValue), string(modelName) + "/")
                pathValue = [modelName "/" pathValue];
            end
        end
        parameter = getstr(row, "parameter", getstr(row, "param", ""));
        if isfield(row, "value")
            value = row.value;
            if isnumeric(value), value = num2str(value, "%.17g");
            else, value = char(string(value));
            end
        elseif isfield(row, "scale")
            old = get_param(pathValue, parameter);
            if parameter_already_uses_scenario_variable(old, scenario)
                value = old;
            else
                value = sprintf("(%s)*%.17g", old, double(row.scale));
            end
        else
            error("SimuVerity:UnifiedD16:ScenarioMutation", ...
                "scenario set_param row needs value or scale");
        end
        set_param(pathValue, parameter, value);
    end
end
end

function yes = parameter_already_uses_scenario_variable(expression, scenario)
yes = false;
if ~isfield(scenario, "agent_variables") || ...
        isempty(scenario.agent_variables)
    return;
end
names = fieldnames(scenario.agent_variables);
text = char(string(expression));
for i = 1:numel(names)
    token = ["(?<![A-Za-z0-9_])" ...
        regexptranslate("escape", names{i}) "(?![A-Za-z0-9_])"];
    if ~isempty(regexp(text, token, "once"))
        yes = true;
        return;
    end
end
end

function name = bdroot_from_path(pathValue)
[~, name, ~] = fileparts(char(string(pathValue)));
name = string(name);
end
function rows = empty_task_reports()
rows = struct( ...
    "task", {}, "id", {}, "kind", {}, "semantic_kind", {}, ...
    "scenario", {}, "layer", {}, "evaluated", {}, "mandatory", {}, ...
    "ok", {}, "valid", {}, "score", {}, "detail", {}, "evidence", {});
end
function rows = empty_band_measurements()
rows = struct( ...
    "id", {}, "scenario", {}, "group", {}, "criticality", {}, ...
    "metric", {}, "signals", {}, "valid", {}, "value", {}, ...
    "weight", {}, "detail", {}, "band_contract", {});
end
function n = numel_any(value), n = numel(value); end
function value = elem(values, index)
if iscell(values), value = values{index}; else, value = values(index); end
end
function value = getnum(row, field, default)
value = default;
if isfield(row, field) && ~isempty(row.(field)) && isnumeric(row.(field))
    value = double(row.(field));
end
end
function value = getstr(row, field, default)
value = default;
if isfield(row, field) && ~isempty(row.(field))
    value = char(string(row.(field)));
end
end
function value = getbool(row, field, default)
value = default;
if isstruct(row) && isfield(row, field) && ~isempty(row.(field))
    value = logical(row.(field));
end
end
