function evidence = f90_xrobo01_extract_evidence_core(modelPath, outDir)
%f90_xrobo01_extract_evidence_core Current trusted-network extraction.
% Dynamic scenarios and measurement semantics use the bundled implementation. Static
% qualification is deferred to the offline SCORING_CORE policy so an invalid structure
% cannot suppress otherwise useful fixed simulation evidence.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

taskDir = fileparts(mfilename("fullpath"));
projectRoot = fileparts(fileparts(fileparts(fileparts(taskDir))));
addpath(taskDir, "-begin");
dispatcher = fullfile(taskDir, "f90_xrobo01_measurement_compatibility.m");
staticAudit = fullfile(taskDir, "f90_xrobo01_static_audit.m");
writer = fullfile(projectRoot, "scripts", "formal90", ...
    "formal90_write_evidence.m");
assert(all(isfile([dispatcher, staticAudit, writer])), ...
    "SimuVerity:F90:XROBO01:DependencyMissing", ...
    "A bundled evaluator dependency is missing.");

execute = @(varargin) f90_xrobo01_measurement_compatibility( ...
    "execute_scenarios", varargin{:});
def = f90_xrobo01_definition;
source = f90_xrobo01_source_setup;
facts = struct("platform_valid", false, "score_inputs_valid", false, ...
    "diagnostics_valid", false, "gate_reasons", strings(0, 1), ...
    "static_audit", struct, "scenario_rows", struct([]), ...
    "runs", struct([]), ...
    "offline_structure_decision_required", true);
try
    assert(string(version("-release")) == "2025a", ...
        "SimuVerity:F90:XROBO01:WrongMatlabRelease");
    assert(isfile(source.model), ...
        "SimuVerity:F90:XROBO01:EvaluatorSourceMissing");
    assert(isfile(modelPath), "SimuVerity:F90:XROBO01:CandidateMissing");
    facts.platform_valid = true;
    audit = f90_xrobo01_static_audit(modelPath, ...
        fullfile(outDir, "static_audit.json"));

    [rows, runRows] = execute(modelPath, def);
    reasons = strings(0, 1);
    invalid = rows(~[rows.valid]);
    for index = 1:numel(invalid)
        reasons(end + 1, 1) = "scenario:" + string(invalid(index).id) + ...
            ": " + invalid(index).failure_reason; %#ok<AGROW>
    end
    facts.static_audit = audit;
    facts.scenario_rows = rows;
    facts.runs = runRows;
    facts.diagnostics_valid = true;
    facts.score_inputs_valid = isempty(reasons);
    facts.gate_reasons = reasons;
catch ME
    facts.platform_valid = false;
    facts.score_inputs_valid = false;
    facts.gate_reasons = "Evaluator/platform failure: " + ...
        string(ME.message);
    facts.error_identifier = string(ME.identifier);
    facts.error_message = string(ME.message);
end

evidence = formal90_write_evidence("F90-XROBO-01", modelPath, ...
    outDir, def.groups.weights, facts, dispatcher);
evidence.structure_evidence_schema = ...
    "simuverity.f90-xrobo01-trusted-port-network.v1";
evidence.current_score_formula_thresholds_weights_unchanged = true;
evidence.score_fields_present = false;
localWriteJsonReplace(fullfile(outDir, "evidence.json"), evidence);
end

function localWriteJsonReplace(pathValue, payload)
assert(isfile(pathValue), "SimuVerity:F90:XROBO01:EvidenceMissing", ...
    "Evidence writer did not publish evidence.json.");
temporary = pathValue + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XROBO01:JsonOpen", ...
    "Cannot stage SCORING_CORE evidence.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
clear cleanup
assert(movefile(temporary, pathValue, "f"), ...
    "SimuVerity:F90:XROBO01:JsonPublish", ...
    "Cannot atomically replace same-run evidence with SCORING_CORE evidence.");
end
