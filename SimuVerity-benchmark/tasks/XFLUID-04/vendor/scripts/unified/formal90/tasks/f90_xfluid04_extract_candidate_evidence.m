function evidence = f90_xfluid04_extract_candidate_evidence( ...
        modelPath, outDir)
%f90_xfluid04_extract_candidate_evidence Provider-owned evidence route.
%
% Current public extraction route.  The public nominal workspace values come
% from the current evaluator-owned remaining58 provider, so evaluation does
% not depend on the external source checkout.  Scenario definitions,
% measurements, facts, and the offline scoring formula remain unchanged.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

repoRoot = fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath"))))));
taskRoot = fullfile(repoRoot, "scripts", "formal90", "tasks", ...
    "f90_xfluid04");
providerRoot = fullfile(repoRoot, "scripts", "unified", ...
    "candidate_closure");
addpath(fullfile(repoRoot, "scripts", "formal90"), "-begin");
addpath(fullfile(repoRoot, "scripts", "xp9"), "-begin");
addpath(taskRoot, "-begin");
addpath(providerRoot, "-begin");

dependency = fullfile(taskRoot, "f90_xfluid04_measurement.m");
assert(strcmpi(xp9_file_presence_file(dependency), ...
    "present"), ...
    "SimuVerity:Formal90:XFLUID04:MeasurementDependencyBinding", ...
    "The declared XFLUID-04 measurement dependency changed.");
provider = fullfile(providerRoot, ...
    "simuverity_formal90_public_nominal_inputs.m");
assert(strcmpi(xp9_file_presence_file(provider), ...
    "present"), ...
    "SimuVerity:Formal90:XFLUID04:NominalProviderBinding", ...
    "The current evaluator-owned public nominal provider changed.");

runScenario = @(varargin) f90_xfluid04_measurement_compatibility( ...
    "run_scenario", varargin{:});
staticAudit = @(varargin) f90_xfluid04_measurement_compatibility( ...
    "static_audit", varargin{:});
emptyRow = @(varargin) f90_xfluid04_measurement_compatibility( ...
    "empty_row", varargin{:});
pairedFn = @(varargin) f90_xfluid04_measurement_compatibility( ...
    "paired_causality", varargin{:});
def = f90_xfluid04_definition;
facts = struct( ...
    "platform_valid", false, ...
    "score_inputs_valid", false, ...
    "diagnostics_valid", false, ...
    "gate_reasons", strings(0, 1), ...
    "static_audit", struct, ...
    "scenario_rows", struct([]), ...
    "paired_causality", struct);

try
    publicNames = string({def.public_inputs.name});
    nominal = simuverity_formal90_public_nominal_inputs( ...
        "F90-XFLUID-04", publicNames);
    names = fieldnames(nominal);
    for index = 1:numel(names)
        assignin("base", names{index}, nominal.(names{index}));
    end

    load_system(modelPath);
    [~, model] = fileparts(modelPath);
    set_param(model, "SimulationCommand", "update");
    audit = staticAudit(model, def);
    % A failed candidate qualification gate is score evidence, not an
    % evaluator/platform exception. Preserve the audit and let the offline
    % scorer emit the task-owned G=0 decision.
    facts.static_audit = audit;
    reasons = strings(0, 1);
    if ~audit.core_path_qualified
        reasons(end + 1) = ...
            "core hydraulic-mechanical-feedback topology was not qualified";
    end

    ids = ["nominal", string({def.scenarios.id})];
    values = cell(numel(ids), 1);
    values{1} = nominal;
    for index = 1:numel(def.scenarios)
        values{index + 1} = def.scenarios(index).values;
    end
    rows = repmat(emptyRow(), numel(ids), 1);
    for index = 1:numel(ids)
        try
            rows(index) = runScenario( ...
                model, ids(index), values{index}, def);
        catch ME
            rows(index).id = ids(index);
            rows(index).error = string(ME.message);
            reasons(end + 1) = ids(index) + ":" + ...
                string(ME.identifier); %#ok<AGROW>
        end
    end
    valid = all([rows.valid]);
    if ~valid
        reasons = ["required scenario or output contract failed"; reasons];
    end
    drop = find(ids == "pressure_drop_pair", 1);
    control = find(ids == "pressure_control_pair", 1);
    facts.platform_valid = true;
    facts.score_inputs_valid = valid;
    facts.diagnostics_valid = valid;
    facts.gate_reasons = reasons;
    facts.scenario_rows = rows;
    if valid
        facts.paired_causality = pairedFn(rows(drop), rows(control));
    end
catch ME
    facts.gate_reasons = ...
        "Evaluator/platform failure: " + string(ME.message);
    facts.error_identifier = string(ME.identifier);
    facts.error_message = string(ME.message);
end

evidence = formal90_write_evidence( ...
    "F90-XFLUID-04", modelPath, outDir, ...
    def.groups.weights, facts, dependency);
end
