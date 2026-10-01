function result = d16_write_d014_evidence( ...
    runLabel, attemptLabel, candidatePath, outputRoot) %#ok<INUSD>
%D16_WRITE_D014_EVIDENCE Extract current D014 public evidence.

taskId = "D014";
policyId = "simuverity-101-v1:d014:scoring";
candidatePath = string(candidatePath);
outputRoot = string(outputRoot);
assert(isfile(candidatePath), "SimuVerity:UnifiedD16:CandidateMissing", ...
    "Candidate artifact is missing.");
assert(isfolder(outputRoot), "SimuVerity:UnifiedD16:OutputRoot", ...
    "Output root must already exist.");

sharedRoot = string(fileparts(mfilename("fullpath")));
d16Root = string(fileparts(sharedRoot));
unifiedRoot = string(fileparts(d16Root));
scriptsRoot = string(fileparts(unifiedRoot));
repoRoot = string(fileparts(scriptsRoot));
engineRoot = fullfile(repoRoot, "engine");
specPath = fullfile(repoRoot, "data", "specs", "D014_sps_average_vsc_policy.json");
assert(isfile(specPath), "SimuVerity:UnifiedD16:SpecMissing", ...
    "D014 task spec is missing.");

oldPath = path;
cleanupPath = onCleanup(@() path(oldPath)); %#ok<NASGU>
restoredefaultpath;
addpath(engineRoot, "-begin");
addpath(sharedRoot, "-begin");

spec = jsondecode(fileread(specPath));
assert(string(spec.id) == taskId, "SimuVerity:UnifiedD16:D014SpecIdentity", ...
    "D014 task spec identity mismatch.");
spec.evaluation_policy_id = policyId;
if isfield(spec, "policy_status"), spec.policy_status = "CURRENT"; end
baseSuite = d16_extract_suite(spec, candidatePath, "agent");
fallbackUsed = false;
try
    suite = apply_average_vsc_compatibility(baseSuite, candidatePath, spec);
catch errorValue
    assert(is_missing_structure_row(baseSuite), ...
        "SimuVerity:UnifiedD16:D014UnexpectedExtractionFailure", ...
        "D014 extraction failed outside the supported fail-closed case.");
    suite = baseSuite;
    fallbackUsed = true;
end

evidencePath = fullfile(outputRoot, "candidate_evidence.json");
evidence = struct( ...
    "schema", "simuverity.unified-d16-candidate-evidence.v1", ...
    "contract_id", "simuverity_d16_p9_evidence_contract", ...
    "collection_id", "d16", ...
    "benchmark_task_id", taskId, ...
    "evaluation_policy_id", policyId, ...
    "candidate_path", canonical_path(candidatePath), ...
    "task_spec_path", canonical_path(specPath), ...
    "task_spec", spec, ...
    "suite", suite, ...
    "extraction_only", true, ...
    "direct_scorer_called", false, ...
    "offline_scoring_started", false, ...
    "generated_at", nowz());
evidence.fail_closed_empty_structure_fallback_used = logical(fallbackUsed);
write_json_exclusive(evidencePath, evidence);

result = struct( ...
    "schema", "simuverity.unified-extractor-result.v1", ...
    "contract_id", "simuverity_d16_p9_evidence_contract", ...
    "collection_id", "d16", ...
    "benchmark_task_id", taskId, ...
    "evaluation_policy_id", policyId, ...
    "candidate_path", canonical_path(candidatePath), ...
    "status", "EVIDENCE_READY", ...
    "failure_attribution", "", ...
    "failure_reasons", strings(0, 1), ...
    "extraction_only", true, ...
    "direct_scorer_called", false, ...
    "evidence_path", canonical_path(evidencePath), ...
    "offline_scoring_started", false, ...
    "generated_at", nowz());
write_json_exclusive(fullfile(outputRoot, "extractor_result.json"), result);
end

function value = is_missing_structure_row(suite)
value = false;
if ~isstruct(suite) || ~isfield(suite, "nominal"), return; end
row = suite.nominal;
notSimulated = ~isfield(row, "stage") || string(row.stage) ~= "simulated";
missingReports = ~isfield(row, "struct_reports") || ...
    isempty(row.struct_reports) || ~isfield(row.struct_reports, "id");
value = logical(notSimulated && missingReports);
end

function suite = apply_average_vsc_compatibility(suite, candidatePath, spec)
assert(isstruct(suite) && isscalar(suite) && isfield(suite, "nominal"), ...
    "SimuVerity:UnifiedD16:D014SuiteSchema", "D014 suite is missing nominal evidence.");
[~, modelName] = fileparts(char(candidatePath));
load_system(char(candidatePath));
cleanupModel = onCleanup(@() close_if_loaded(modelName)); %#ok<NASGU>
[averageOk, averageEvidence] = trusted_average_stages(modelName);

suite.nominal = replace_power_stage_report( ...
    suite.nominal, averageOk, averageEvidence);
rows = suite.scenario_results;
for i = 1:numel(rows)
    row = get_item(rows, i);
    row = replace_power_stage_report(row, averageOk, averageEvidence);
    row = finalize_row(row, false);
    rows = set_item(rows, i, row);
end
suite.scenario_results = rows;

base = struct( ...
    "struct_reports", suite.nominal.struct_reports, ...
    "input_reports", suite.nominal.input_reports, ...
    "output_reports", suite.nominal.output_reports, ...
    "band_reports", struct([]));
state = struct("model_graph", struct(), "evidence", struct());
try, state.model_graph = sat_model_graph(modelName); catch, end
report = sat_check_D014_measured_power_path_ownership( ...
    modelName, spec, "nominal", [], [], base, state);
existing = suite.nominal.task_oracle_reports;
matches = find(string({existing.id}) == string(report.id));
assert(numel(matches) == 1, "SimuVerity:UnifiedD16:D014OracleReplacement", ...
    "Expected exactly one existing D014 oracle report.");
existing(matches) = report;
suite.nominal.task_oracle_reports = existing;
suite.nominal = finalize_row(suite.nominal, report_pass(report));
if isfield(suite.nominal, "task_extractor_diagnostics") && ...
        isstruct(suite.nominal.task_extractor_diagnostics)
    suite.nominal.task_extractor_diagnostics.strategy = ...
        "trusted_sps_continuous_average_vsc";
    suite.nominal.task_extractor_diagnostics.affects_offline_score = true;
end
[suite.required_scenarios_ok, suite.required_witnesses_ok] = ...
    required_suite_status(suite, spec);
end

function [ok, evidence] = trusted_average_stages(modelName)
ok = false;
matches = struct([]);
blocks = find_system(modelName, "LookUnderMasks", "on", ...
    "FollowLinks", "on", "Type", "Block");
for i = 1:numel(blocks)
    [hit, row] = sat_d014_is_trusted_continuous_average_vsc(blocks{i});
    if hit
        if isempty(matches), matches = row; else, matches(end + 1) = row; end %#ok<AGROW>
    end
end
ok = ~isempty(matches);
evidence = struct( ...
    "recognized", logical(ok), ...
    "required_mode", "continuous average model 3", ...
    "trusted_stage_count", numel(matches), ...
    "trusted_stages", matches);
end

function row = replace_power_stage_report(row, averageOk, averageEvidence)
reports = row.struct_reports;
matches = find(string({reports.id}) == "power_switching_stage");
assert(numel(matches) == 1, "SimuVerity:UnifiedD16:D014PowerStageReport", ...
    "Expected exactly one D014 power switching stage report.");
i = matches(1);
existingOk = logical(reports(i).ok);
reports(i).ok = existingOk || logical(averageOk);
reports(i).prim = "d014_controllable_power_stage";
reports(i).evidence = struct( ...
    "existing_has_power_device", existingOk, ...
    "trusted_sps_continuous_average_vsc", averageEvidence);
if existingOk
    reports(i).detail = "PASS:EXISTING_DISCRETE_POWER_DEVICE";
elseif averageOk
    reports(i).detail = "PASS:TRUSTED_SPS_CONTINUOUS_AVERAGE_MODEL_3";
else
    reports(i).detail = "FAIL:NO_TRUSTED_CONTROLLABLE_POWER_STAGE";
end
row.struct_reports = reports;
row.struct_detail = structural_detail(reports);
row.topology_ok = mandatory_structure_pass(reports);
end

function row = finalize_row(row, taskOracleOk)
row.topology_ok = mandatory_structure_pass(row.struct_reports) && ...
    logical(taskOracleOk || isempty(row.task_oracle_reports));
row.qualification_ok = string(row.stage) == "simulated" && ...
    logical(row.topology_ok) && logical(row.input_ok) && ...
    logical(row.contract_ok);
row.nominal_evidence_ok = logical(row.qualification_ok);
row.robustness_evidence_ok = logical(row.qualification_ok);
row.detail = gate_detail(row);
end

function [requiredOk, witnessesOk] = required_suite_status(suite, spec)
requiredOk = true;
witnessesOk = true;
rows = suite.scenario_results;
declarations = spec.scenarios;
for i = 1:numel(rows)
    row = get_item(rows, i);
    declaration = get_item(declarations, i);
    required = get_bool(declaration, "required", true);
    witnessOk = get_bool(row, "witness_ok", false);
    if required
        requiredOk = requiredOk && logical(row.qualification_ok) && witnessOk;
        witnessesOk = witnessesOk && witnessOk;
    end
end
for i = 1:numel(suite.task_oracle_reports)
    report = suite.task_oracle_reports(i);
    if get_bool(report, "mandatory", true) && ~report_pass(report)
        requiredOk = false;
        witnessesOk = false;
    end
end
end

function ok = mandatory_structure_pass(reports)
ok = true;
for i = 1:numel(reports)
    if get_bool(reports(i), "mandatory", false)
        ok = ok && get_bool(reports(i), "ok", false);
    end
end
end

function ok = report_pass(report)
ok = isstruct(report) && isscalar(report) && ...
    get_bool(report, "evaluated", false) && ...
    get_bool(report, "valid", false) && get_bool(report, "ok", false);
end

function detail = structural_detail(reports)
parts = strings(1, numel(reports));
for i = 1:numel(reports)
    suffix = "-"; if logical(reports(i).ok), suffix = "+"; end
    parts(i) = string(reports(i).id) + ":" + ...
        string(reports(i).prim) + suffix;
end
detail = strjoin(parts, ",");
end

function detail = gate_detail(row)
issues = strings(0, 1);
if ~logical(row.topology_ok), issues(end + 1) = "topology"; end %#ok<AGROW>
if ~logical(row.input_ok), issues(end + 1) = "input_contract"; end %#ok<AGROW>
if ~logical(row.tap_ok), issues(end + 1) = "golden_tap"; end %#ok<AGROW>
if ~logical(row.core_ok), issues(end + 1) = "core_contract"; end %#ok<AGROW>
if ~logical(row.provenance_ok), issues(end + 1) = "provenance"; end %#ok<AGROW>
if isempty(issues), detail = "OK";
else, detail = "QUALIFICATION_FAIL:" + strjoin(issues, "+"); end
end

function value = get_item(collection, index)
if iscell(collection), value = collection{index}; else, value = collection(index); end
end
function collection = set_item(collection, index, value)
if iscell(collection), collection{index} = value; else, collection(index) = value; end
end
function value = get_bool(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name) && isscalar(s.(name))
    value = logical(s.(name));
end
end
function close_if_loaded(modelName)
if bdIsLoaded(modelName), close_system(modelName, 0); end
end
function value = canonical_path(pathValue)
value = string(java.io.File(char(pathValue)).getCanonicalPath());
end
function write_json_exclusive(file, value)
assert(java.io.File(char(file)).createNewFile(), ...
    "SimuVerity:UnifiedD16:ImmutableOutput", "Output already exists.");
fid = fopen(file, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:UnifiedD16:JsonOpen", "Cannot open JSON output.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end
function value = nowz()
value = string(datetime("now", TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
