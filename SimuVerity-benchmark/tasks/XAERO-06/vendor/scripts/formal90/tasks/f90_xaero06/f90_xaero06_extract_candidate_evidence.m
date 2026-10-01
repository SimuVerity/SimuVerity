function evidence = f90_xaero06_extract_candidate_evidence( ...
        modelPath, outDir, officialScenarios, evaluatorAssetRoot)
%F90_XAERO06_EXTRACT_CANDIDATE_EVIDENCE Separate technical
% evidence validity from scored flight performance.
%
% The predecessor extractor remains the sole simulation/measurement engine.
% This evaluator reclassifies its output after all requested
% scenarios have been attempted.  Output dynamics and terminal-motion
% thresholds are retained as scorer-owned performance diagnostics; they do
% not decide whether otherwise complete finite evidence can be accepted.

arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end

if strlength(officialScenarios) > 0 || strlength(evaluatorAssetRoot) > 0
    assert(strlength(officialScenarios) > 0 && ...
        strlength(evaluatorAssetRoot) > 0 && ...
        localEvaluationSubject() == "reference", ...
        "SimuVerity:F90:XAERO06:ReferenceBoundary", ...
        "The explicit native-reference boundary requires reference subject, scenarios and asset root.");
    evidence = f90_xaero06_extract_reference_evidence( ...
        modelPath, outDir, officialScenarios, evaluatorAssetRoot);
else
    evaluationSubject = localEvaluationSubject();
    evidence = f90_xaero06_extract_reference_evidence( ...
        modelPath, outDir, evaluationSubject);
end
assert(isstruct(evidence) && isscalar(evidence) && ...
    isfield(evidence, "task_id") && ...
    string(evidence.task_id) == "F90-XAERO-06", ...
    "SimuVerity:F90:XAERO06:PFQEvidenceShape", ...
    "The predecessor extractor did not return XAERO06 evidence.");

requiredIds = [ ...
    "nominal_autoland"
    "low_initial_energy"
    "high_initial_energy"
    "bank_angle_recovery"
    "upper_mass_boundary"
    "enhanced_native_wind"
];
technicalFields = [ ...
    "landing_state_nonempty"
    "landing_state_finite"
    "guidance_nonempty"
    "surface_command_nonempty"
    "surface_position_nonempty"
    "landing_state_width_16"
    "guidance_width_3"
    "surface_command_width_6"
    "surface_position_width_6"
    "all_required_timeseries_finite"
    "complete_run_starts_at_zero"
    "mission_horizon_present"
];
performanceFields = [ ...
    "position_and_altitude_dynamic"
    "airdata_dynamic"
    "guidance_dynamic"
    "surface_command_dynamic"
    "surface_position_dynamic"
];

rows = evidence.scenarios;
ids = strings(numel(rows), 1);
attempted = false(numel(rows), 1);
technicalValid = false(numel(rows), 1);
for index = 1:numel(rows)
    ids(index) = string(rows(index).id);
    hasStructuredFailure = localHasStructuredFailure(rows(index));
    attempted(index) = logical(rows(index).simulation_pass) || ...
        hasStructuredFailure;
    technicalValid(index) = logical(rows(index).simulation_pass) && ...
        localFieldsTrue(rows(index).output_contract, technicalFields);
    rows(index).execution_attempted = attempted(index);
    % localApplyCandidateScenario assigns exactly requested_inputs before the
    % predecessor calls sim.  Publish that evaluator-owned fact even when the
    % simulation later terminates numerically and therefore has no metrics.
    rows(index).applied_inputs = rows(index).requested_inputs;
    rows(index).technical_evidence_valid = technicalValid(index);
    rows(index).performance_contract = localSelectFields( ...
        rows(index).output_contract, performanceFields);
    rows(index).performance_failure_reasons = localFalseFieldReasons( ...
        rows(index).output_contract, performanceFields);
    if ~logical(rows(index).simulation_pass)
        rows(index).performance_failure_reasons(end + 1, 1) = ...
            "SCENARIO_SIMULATION_FAILED";
    end
end
evidence.scenarios = rows;

scenarioSetComplete = numel(ids) == numel(requiredIds) && ...
    numel(unique(ids)) == numel(requiredIds) && ...
    all(sort(ids) == sort(requiredIds));
nominalIndex = find(ids == "nominal_autoland", 1);
nominalTechnicalValid = ~isempty(nominalIndex) && ...
    technicalValid(nominalIndex);
corePathQualified = isfield(evidence, "static_audit") && ...
    isstruct(evidence.static_audit) && ...
    isfield(evidence.static_audit, "core_path_qualified") && ...
    logical(evidence.static_audit.core_path_qualified);
technicalGate = logical(evidence.load_pass) && ...
    logical(evidence.update_pass) && logical(evidence.compile_pass) && ...
    logical(evidence.nominal_smoke_pass) && corePathQualified && ...
    scenarioSetComplete && all(attempted) && nominalTechnicalValid;

evidence.schema = "simuverity.f90-xaero06-evidence.pfq.v1";
evidence.pfq_policy_id = ...
    "simuverity-101-v1:f90-xaero-06:scoring";
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
evidence.technical_gate = struct( ...
    "scenario_set_complete", scenarioSetComplete, ...
    "all_scenarios_attempted", all(attempted), ...
    "nominal_technical_output_valid", nominalTechnicalValid, ...
    "core_path_qualified", corePathQualified, ...
    "technical_output_fields", technicalFields, ...
    "performance_only_fields", performanceFields);
evidence.score_inputs_valid = technicalGate;
evidence.diagnostics_valid = technicalGate;
evidence.EVIDENCE_COMPLETE = technicalGate;
evidence.evidence_complete = evidence.EVIDENCE_COMPLETE;

evidencePath = fullfile(outDir, "evidence.json");
localAtomicWriteJson(evidencePath, evidence);
end

function subject = localEvaluationSubject()
subject = lower(strtrim(string(getenv( ...
    "SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject) == 0, subject = "candidate"; end
assert(any(subject == ["candidate", "reference"]), ...
    "SimuVerity:F90:XAERO06:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function value = localFieldsTrue(source, names)
value = isstruct(source) && isscalar(source);
if ~value, return, end
for name = names'
    if ~isfield(source, name) || ~isscalar(source.(name)) || ...
            ~logical(source.(name))
        value = false;
        return
    end
end
end

function value = localSelectFields(source, names)
value = struct;
if ~(isstruct(source) && isscalar(source)), return, end
for name = names'
    if isfield(source, name)
        value.(name) = logical(source.(name));
    end
end
end

function reasons = localFalseFieldReasons(source, names)
reasons = strings(0, 1);
for name = names'
    if isstruct(source) && isscalar(source) && isfield(source, name) && ...
            ~logical(source.(name))
        reasons(end + 1, 1) = ...
            "PERFORMANCE_CONTRACT_FAILED:" + name; %#ok<AGROW>
    end
end
end

function value = localHasStructuredFailure(row)
value = false;
if ~isfield(row, "error") || ~isstruct(row.error) || ...
        ~isscalar(row.error)
    return
end
for name = ["id", "message", "stage"]
    if isfield(row.error, name) && ...
            strlength(string(row.error.(name))) > 0
        value = true;
        return
    end
end
end

function localAtomicWriteJson(pathOut, value)
temporary = pathOut + ".pfq.tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAERO06:PFQEvidenceWrite", ...
    "Cannot write PFQ evidence: %s", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
clear cleanup
movefile(temporary, pathOut, "f");
end
