function evidence = f90_xauto11_candidate_simulation( ...
        candidatePath, outputDir, spec)
%F90_XAUTO11_CANDIDATE_SIMULATION Apply each scenario on both paths.
%
% The sealed candidate's InitFcn reads xauto11_input with evalin('base',...).
% Simulink.SimulationInput.setVariable alone therefore does not prove that a
% official scenario reached this candidate.  This task-local runner installs
% the evaluator-owned value in the base workspace before every simulation,
% while the shared runner continues to install the same value through
% SimulationInput.  The pre-simulation base value is recorded outside
% the model workspace, verified after simulation, and restored on exit.
arguments
    candidatePath (1,1) string
    outputDir (1,1) string
    spec (1,1) struct
end

assert(isfield(spec, "input_builder") && ...
    isa(spec.input_builder, "function_handle"), ...
    "SimuVerity:F90:XAUTO11:Spec", "input_builder is required.");
assert(isfield(spec, "postprocess") && ...
    isa(spec.postprocess, "function_handle"), ...
    "SimuVerity:F90:XAUTO11:Spec", "postprocess is required.");

baseState = localCaptureBase("xauto11_input");
baseCleanup = onCleanup(@()localRestoreBase(baseState)); %#ok<NASGU>
receiptKey = string(matlab.lang.makeValidName( ...
    "F90_XAUTO11_RECEIPT_" + string(java.util.UUID.randomUUID)));
receiptCleanup = onCleanup(@()localRemoveReceiptStore(receiptKey)); %#ok<NASGU>

sourceBuilder = spec.input_builder;
sourcePostprocess = spec.postprocess;
spec.xauto11_receipt_key = receiptKey;
spec.input_builder = @(scenario, innerSpec) ...
    localInstallScenario(sourceBuilder, scenario, innerSpec);
spec.postprocess = @(row, outputs, scenario, innerSpec) ...
    localVerifyScenario(sourcePostprocess, row, outputs, scenario, innerSpec);

evidence = simuverity_run_candidate_evidence( ...
    candidatePath, outputDir, spec);
rows = evidence.scenarios;
applicationPass = ~isempty(rows) && ...
    all(arrayfun(@(row)localFieldTrue(row, "scenario_application_pass"), rows));
representations = strings(numel(rows), 1);
for index = 1:numel(rows)
    if isfield(rows(index), "offline_metrics") && ...
            isfield(rows(index).offline_metrics, ...
            "input_application_log") && ...
            isfield(rows(index).offline_metrics.input_application_log, ...
            "requested_input_file_presence")
        applicationLog = ...
            rows(index).offline_metrics.input_application_log;
        representations(index) = string( ...
            applicationLog.requested_input_file_presence);
    end
end
representationsUnique = ~isempty(representations) && ...
    all(strlength(representations) > 0) && ...
    numel(unique(representations)) == numel(representations);

evidence.input_application_contract = ...
    "xauto11-base-and-simulationinput";
evidence.input_application_all_pass = logical(applicationPass);
evidence.input_application_representations_unique = ...
    logical(representationsUnique);
evidence.input_application_representations = representations;
evidence.base_workspace_restored_by_cleanup = true;
evidence.score_inputs_valid = logical(evidence.score_inputs_valid && ...
    applicationPass && representationsUnique);
evidence.diagnostics_valid = evidence.score_inputs_valid;
evidence.evidence_freeze_candidate = evidence.score_inputs_valid;

assert(evidence.score_inputs_valid, ...
    "SimuVerity:F90:XAUTO11:ScenarioApplication", ...
    ["Every XAUTO-11 scenario must be applied through both the base " ...
     "workspace and SimulationInput with a distinct verified representation."]);
end

function inputs = localInstallScenario(builder, scenario, spec)
inputs = builder(scenario, spec);
assert(isstruct(inputs) && isscalar(inputs) && ...
    isfield(inputs, "xauto11_input"), ...
    "SimuVerity:F90:XAUTO11:PublicInput", ...
    "input_builder must return scalar xauto11_input.");
requested = localPlainValue(inputs.xauto11_input);
assignin("base", "xauto11_input", requested);
observed = localPlainValue(evalin("base", "xauto11_input"));
requestedBinding = localStructFilePresence(requested);
observedBinding = localStructFilePresence(observed);
receipt = struct( ...
    "scenario_id", string(scenario.id), ...
    "requested_parameters", requested, ...
    "requested_input_file_presence", requestedBinding, ...
    "base_value_before_simulation_file_presence", observedBinding, ...
    "base_value_before_simulation_matches_requested", ...
        isequaln(requested, observed), ...
    "simulationinput_value_file_presence", requestedBinding, ...
    "simulationinput_and_base_match", requestedBinding == observedBinding);
store = localReceiptStore(spec.xauto11_receipt_key);
store.(localScenarioField(scenario.id)) = receipt;
setappdata(0, char(spec.xauto11_receipt_key), store);
inputs.xauto11_input = requested;
end

function row = localVerifyScenario(postprocess, row, outputs, scenario, spec)
row = postprocess(row, outputs, scenario, spec);
store = localReceiptStore(spec.xauto11_receipt_key);
field = localScenarioField(scenario.id);
assert(isfield(store, field), ...
    "SimuVerity:F90:XAUTO11:MissingApplicationReceipt", ...
    "Missing pre-simulation application receipt for %s.", string(scenario.id));
receipt = store.(field);
observedAfter = localPlainValue(evalin("base", "xauto11_input"));
afterBinding = localStructFilePresence(observedAfter);
receipt.base_value_after_simulation_file_presence = afterBinding;
receipt.base_value_after_simulation_matches_requested = ...
    isequaln(receipt.requested_parameters, observedAfter);
receipt.pass = logical( ...
    receipt.base_value_before_simulation_matches_requested && ...
    receipt.simulationinput_and_base_match && ...
    receipt.base_value_after_simulation_matches_requested && ...
    receipt.requested_input_file_presence == ...
        receipt.base_value_before_simulation_file_presence && ...
    receipt.requested_input_file_presence == ...
        receipt.simulationinput_value_file_presence && ...
    receipt.requested_input_file_presence == ...
        receipt.base_value_after_simulation_file_presence);
row.applied_parameters = observedAfter;
row.offline_metrics.input_application_log = receipt;
row.scenario_application_pass = receipt.pass;
row.valid = logical(row.valid && receipt.pass);
end

function state = localCaptureBase(name)
escaped = replace(string(name), "'", "''");
state = struct("name", string(name), "existed", ...
    logical(evalin("base", "exist('" + escaped + "','var') == 1")), ...
    "value", []);
if state.existed
    state.value = evalin("base", char(name));
end
end

function localRestoreBase(state)
if state.existed
    assignin("base", char(state.name), state.value);
else
    escaped = replace(state.name, "'", "''");
    evalin("base", "if exist('" + escaped + ...
        "','var'), clear('" + escaped + "'); end");
end
end

function store = localReceiptStore(key)
if isappdata(0, char(key))
    store = getappdata(0, char(key));
else
    store = struct;
end
end

function localRemoveReceiptStore(key)
if isappdata(0, char(key)), rmappdata(0, char(key)); end
end

function field = localScenarioField(identifier)
field = matlab.lang.makeValidName("scenario_" + string(identifier));
end

function value = localPlainValue(value)
if isa(value, "Simulink.Parameter"), value = value.Value; end
assert(isstruct(value) && isscalar(value), ...
    "SimuVerity:F90:XAUTO11:PublicInput", ...
    "xauto11_input must resolve to one scalar struct.");
end

function binding = localStructFilePresence(value)
binding = string(jsonencode(value));
end

function pass = localFieldTrue(value, field)
pass = isfield(value, field) && isscalar(value.(field)) && ...
    logical(value.(field));
end
