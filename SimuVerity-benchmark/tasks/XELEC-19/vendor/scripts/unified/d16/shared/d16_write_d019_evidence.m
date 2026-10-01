function result = d16_write_d019_evidence( ...
    runLabel, attemptLabel, candidatePath, outputRoot) %#ok<INUSD>
%D16_WRITE_D019_EVIDENCE Extract current D019 public evidence.

taskId = "D019";
policyId = "simuverity-101-v1:d019:scoring";
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
specPath = fullfile(repoRoot, "data", "specs", "D019.json");
assert(isfile(specPath), "SimuVerity:UnifiedD16:SpecMissing", ...
    "D019 task spec is missing.");

oldPath = path;
cleanupPath = onCleanup(@() path(oldPath)); %#ok<NASGU>
restoredefaultpath;
addpath(engineRoot, "-begin");
addpath(sharedRoot, "-begin");

spec = jsondecode(fileread(specPath));
assert(string(spec.id) == taskId, "SimuVerity:UnifiedD16:D019SpecIdentity", ...
    "D019 task spec identity mismatch.");
alternativeA = struct( ...
    "required_block_any", {{"load|rlc|resist|100 w"}}, ...
    "required_parameter_any", {{"activepower|resistance|value"}}, ...
    "min_bindings", 1);
alternativeB = struct( ...
    "required_block_any", {{".*"}}, ...
    "required_reference_any", ...
        {{"^fl_lib/electrical/electrical elements/resistor$"}}, ...
    "required_parameter_any", {{"^r$"}}, ...
    "require_connected", true, ...
    "require_conserving_connection", true, ...
    "min_bindings", 1, "min_distinct_blocks", 1);
spec.input_contract.P_load = struct( ...
    "default", 500, "required", true, "min_bindings", 1, ...
    "binding_alternatives", {{alternativeA, alternativeB}});
spec.evaluation_policy_id = policyId;
if isfield(spec, "policy_status"), spec.policy_status = "CURRENT"; end
suite = d16_extract_suite(spec, candidatePath, "agent");
suite = apply_ideal_switch_compatibility(suite, candidatePath, spec);

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

function suite = apply_ideal_switch_compatibility(suite,candidatePath,spec)
assert(isstruct(suite) && isscalar(suite) && isfield(suite,"nominal"), ...
    "SimuVerity:UnifiedD16:D019SuiteSchema","D019 suite is missing nominal evidence.");
[~,modelName] = fileparts(char(candidatePath));
load_system(char(candidatePath));
cleanupModel = onCleanup(@() close_if_loaded(modelName)); %#ok<NASGU>
base = struct( ...
    "struct_reports",suite.nominal.struct_reports, ...
    "input_reports",suite.nominal.input_reports, ...
    "output_reports",suite.nominal.output_reports, ...
    "band_reports",struct([]));
[compatibilityOk,compatibilityEvidence,compatibilityReason] = ...
    sat_d019_ideal_semiconductor_stage(modelName,base);

suite.nominal = replace_structure_reports(suite.nominal, ...
    compatibilityOk,compatibilityEvidence,compatibilityReason);
rows = suite.scenario_results;
for i = 1:numel(rows)
    row = get_item(rows,i);
    row = replace_structure_reports(row,compatibilityOk, ...
        compatibilityEvidence,compatibilityReason);
    row = finalize_row(row);
    rows = set_item(rows,i,row);
end
suite.scenario_results = rows;

if compatibilityOk
    report = collect_vout_level_report(modelName,spec,compatibilityEvidence);
    existing = suite.nominal.task_oracle_reports;
    matches = find(string({existing.id}) == string(report.id));
    assert(numel(matches) == 1,"SimuVerity:UnifiedD16:D019OracleReplacement", ...
        "Expected exactly one existing D019 level report.");
    existing(matches) = report;
    suite.nominal.task_oracle_reports = existing;
end
suite.nominal = finalize_row(suite.nominal);
if isfield(suite.nominal,"task_extractor_diagnostics") && ...
        isstruct(suite.nominal.task_extractor_diagnostics)
    suite.nominal.task_extractor_diagnostics.strategy = ...
        "exact_ideal_semiconductor_stage";
    suite.nominal.task_extractor_diagnostics.affects_offline_score = true;
end
[suite.required_scenarios_ok,suite.required_witnesses_ok] = ...
    required_suite_status(suite,spec);
end

function report = collect_vout_level_report(modelName,spec,stageEvidence)
try
    assignin("base","P_load",double(spec.input_contract.P_load.default));
    set_param(modelName,"StopTime",num2str(double(spec.sim.stop),"%.17g"));
    try, set_param(modelName,"StopFcn",""); catch, end
    simOut = sim(modelName,"ReturnWorkspaceOutputs","on");
    report = sat_check_D019_physical_vout_level_count( ...
        spec,"nominal",simOut,true,stageEvidence);
catch errorValue
    report = failed_level_report(errorValue);
end
end

function report = failed_level_report(errorValue)
identifier = string(errorValue.identifier);
if strlength(identifier) == 0, identifier = "UNCLASSIFIED"; end
report = struct( ...
    "task","D019","id","D019.internal_multilevel_stage_level_count", ...
    "kind","task_specific","semantic_kind","band", ...
    "scenario","nominal","layer","nominal", ...
    "evaluated",false,"mandatory",true,"ok",false,"valid",false, ...
    "score",0,"detail","VOUT_LEVEL_SIMULATION_FAIL:"+identifier, ...
    "evidence",struct("error_identifier",identifier));
end

function row = replace_structure_reports(row,compatibilityOk,evidence,reason)
if ~isfield(row,"struct_reports") || isempty(row.struct_reports), return; end
reports = row.struct_reports;
ids = ["discrete_controllable_stage","three_phase_stage", ...
    "dc_source_switches_load"];
for id = ids
    match = find(string({reports.id}) == id);
    assert(numel(match) == 1,"SimuVerity:UnifiedD16:D019StructureReport", ...
        "Expected one existing D019 structure report: %s",id);
    index = match(1); existingOk = logical(reports(index).ok);
    reports(index).ok = existingOk || logical(compatibilityOk);
    reports(index).prim = "d019_ideal_semiconductor_stage";
    reports(index).evidence = struct( ...
        "existing_ok",existingOk, ...
        "exact_ideal_semiconductor_compatibility",evidence);
    if existingOk
        reports(index).detail = "PASS:EXISTING_RECOGNIZER";
    elseif compatibilityOk
        reports(index).detail = "PASS:EXACT_IDEAL_SEMICONDUCTOR_STAGE";
    else
        reports(index).detail = "FAIL:" + string(reason);
    end
end
% no_universal_bridge is intentionally neither replaced nor rewritten.
universal = find(string({reports.id}) == "no_universal_bridge");
assert(numel(universal) == 1,"SimuVerity:UnifiedD16:D019UniversalBridgeReport", ...
    "The unchanged Universal Bridge prohibition report is missing.");
row.struct_reports = reports;
row.struct_detail = structural_detail(reports);
row.topology_ok = mandatory_structure_pass(reports);
end

function row = finalize_row(row)
row.topology_ok = mandatory_structure_pass(row.struct_reports);
row.qualification_ok = string(row.stage) == "simulated" && ...
    logical(row.topology_ok) && logical(row.input_ok) && ...
    logical(row.contract_ok);
taskNominalOk = true;
if isfield(row,"task_oracle_reports")
    for i = 1:numel(row.task_oracle_reports)
        report = row.task_oracle_reports(i);
        if get_bool(report,"mandatory",true) && ...
                lower(string(report.layer)) == "nominal"
            taskNominalOk = taskNominalOk && report_pass(report);
        end
    end
end
row.nominal_evidence_ok = logical(row.qualification_ok) && taskNominalOk;
row.robustness_evidence_ok = logical(row.qualification_ok);
row.detail = gate_detail(row);
end

function [requiredOk,witnessesOk] = required_suite_status(suite,spec)
requiredOk = true; witnessesOk = true;
rows = suite.scenario_results; declarations = spec.scenarios;
for i = 1:numel(rows)
    row = get_item(rows,i); declaration = get_item(declarations,i);
    required = get_bool(declaration,"required",true);
    witnessOk = get_bool(row,"witness_ok",false);
    if required
        requiredOk = requiredOk && logical(row.qualification_ok) && witnessOk;
        witnessesOk = witnessesOk && witnessOk;
    end
end
end

function ok = mandatory_structure_pass(reports)
ok = true;
for i = 1:numel(reports)
    if get_bool(reports(i),"mandatory",false)
        ok = ok && get_bool(reports(i),"ok",false);
    end
end
end
function ok = report_pass(report)
ok = isstruct(report) && isscalar(report) && ...
    get_bool(report,"evaluated",false) && ...
    get_bool(report,"valid",false) && get_bool(report,"ok",false);
end
function detail = structural_detail(reports)
parts = strings(1,numel(reports));
for i = 1:numel(reports)
    suffix = "-"; if logical(reports(i).ok), suffix = "+"; end
    parts(i) = string(reports(i).id)+":"+string(reports(i).prim)+suffix;
end
detail = strjoin(parts,",");
end
function detail = gate_detail(row)
issues = strings(0,1);
if ~logical(row.topology_ok), issues(end+1) = "topology"; end %#ok<AGROW>
if ~logical(row.input_ok), issues(end+1) = "input_contract"; end %#ok<AGROW>
if ~logical(row.tap_ok), issues(end+1) = "golden_tap"; end %#ok<AGROW>
if ~logical(row.core_ok), issues(end+1) = "core_contract"; end %#ok<AGROW>
if ~logical(row.provenance_ok), issues(end+1) = "provenance"; end %#ok<AGROW>
if isempty(issues), detail = "OK";
else, detail = "QUALIFICATION_FAIL:"+strjoin(issues,"+"); end
end
function value = get_item(collection,index)
if iscell(collection), value = collection{index}; else, value = collection(index); end
end
function collection = set_item(collection,index,value)
if iscell(collection), collection{index} = value; else, collection(index) = value; end
end
function value = get_bool(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && isscalar(s.(name)), value = logical(s.(name)); end
end
function close_if_loaded(modelName)
if bdIsLoaded(modelName), close_system(modelName,0); end
end
function value = canonical_path(pathValue)
value = string(java.io.File(char(pathValue)).getCanonicalPath());
end
function write_json_exclusive(file,value)
assert(java.io.File(char(file)).createNewFile(), ...
    "SimuVerity:UnifiedD16:ImmutableOutput","Output already exists.");
fid = fopen(file,"w","n","UTF-8");
assert(fid >= 0,"SimuVerity:UnifiedD16:JsonOpen","Cannot open JSON output.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),"char");
end
function value = nowz()
value = string(datetime("now",TimeZone="UTC", ...
    Format="yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end
