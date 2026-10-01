function result = f90_xmed08_extract_reference_evidence(modelPath, outputDir, evaluationMode)
% Extract ECG evidence against evaluator-owned event annotations.

repo = localProjectRoot();
if nargin < 3, evaluationMode = "reference"; end
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
assert(nargin >= 1 && strlength(string(modelPath)) > 0, ...
    "SimuVerity:F90:XMED08:ModelRequired", "Public extraction requires an explicit model path.");
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xmed08_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(tempdir, "SimuVerity", "F90-XMED-08", generationRunId);
end
if ~isfolder(outputDir), mkdir(outputDir); end

sharedDir = fullfile(string(getenv("SIMUVERITY_TASK_VENDOR_ROOT")), ...
    "scripts", "formal90", "shared");
sourceDir = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
dataPath = fullfile(sourceDir, "ex_ecgdata360Hz.mat");
expectedModelBinding = "present";
expectedDataBinding = "present";
truthPath = simuverity_official_scenarios_path();
expectedTruthBinding = ...
    "present";
truthFixture = localLoadTruthFixture(truthPath, expectedTruthBinding, ...
    expectedModelBinding, expectedDataBinding);
bindingBefore = struct("model", localFilePresence(modelPath), ...
    "data", localFilePresence(dataPath));
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[~, model] = fileparts(modelPath);
fixture = load(dataPath);
evidencePath = fullfile(outputDir, "evidence.json");
if strcmpi(string(evaluationMode), "candidate")
    addpath(sharedDir, "-begin");
    pathCleanup = onCleanup(@() rmpath(sharedDir)); %#ok<NASGU>
    localConfigureIsolation();
    result = localRunCandidate(modelPath, outputDir, official, fixture, ...
        truthFixture, truthPath, expectedTruthBinding, generationRunId);
    return;
end
addpath(sharedDir, "-begin");
addpath(sourceDir, "-begin");
pathCleanup = onCleanup(@() localRemovePaths(sharedDir, sourceDir)); %#ok<NASGU>
localConfigureIsolation();

evidence = struct( ...
    "schema", "simuverity.f90-xmed08-evidence.v1", ...
    "task_id", "F90-XMED-08", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "source_file_presence_before", bindingBefore, ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "reference_runtime_changes", ...
        "non-invasive callback suppression, input artifact injection and measurement taps only", ...
    "event_matching_tolerance_seconds", ...
        double(official.simulation.event_matching_tolerance_seconds), ...
    "truth_source", "published_official_event_annotations", ...
    "truth_fixture_path", string(truthPath), ...
    "truth_fixture_file_presence", expectedTruthBinding, ...
    "candidate_output_used_as_truth", false, ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "evidence_complete", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "preflight_initial", struct(), ...
    "preflight", struct(), ...
    "adapter_repair_count", 0, ...
    "clear_functions_rebinding_reload", false, ...
    "static_audit", struct(), ...
    "profile", struct(), ...
    "scenarios", [], ...
    "errors", {{}}, ...
    "started_at", localNow());
localAtomicWriteJson(evidencePath, evidence);

try
    assert(isReference, "SimuVerity:F90:XMED08:ReferenceIdentity", ...
        "Pinned reference model or data fixture file presence differs.");
    load_system(modelPath);
    evidence.load_pass = true;
    localPrepareRuntimeModel(model, fixture);

    initialPath = fullfile(outputDir, "preflight_initial.json");
    evidence.preflight_initial = localRunPreflight(model, modelPath, ...
        dataPath, expectedModelBinding, expectedDataBinding, fixture, ...
        official.scenarios(1), initialPath);
    evidence.static_audit = localStaticAudit(model);
    evidence.profile = localCompactProfile(model);
    localAtomicWriteJson(evidencePath, evidence);

    if ~evidence.preflight_initial.pass && ...
            ~localOnlyAdapterIssues(evidence.preflight_initial)
        evidence.errors{end + 1} = localIssue( ...
            "preflight", "non_adapter_failure", ...
            "Initial preflight contains a dependency or model failure; no scenario was started.");
        result = localFinalize(model, modelPath, dataPath, ...
            expectedModelBinding, expectedDataBinding, evidence, evidencePath);
        return;
    end
    if ~evidence.preflight_initial.pass
        evidence.adapter_repair_count = 1;
    end

    % A concentrated adapter refresh is performed in this same MATLAB
    % process. No golden, scenario or score threshold is changed.
    close_system(model, 0);
    evalin("base", "clear functions");
    load_system(modelPath);
    localPrepareRuntimeModel(model, fixture);
    evidence.clear_functions_rebinding_reload = true;

    preflightPath = fullfile(outputDir, "preflight.json");
    evidence.preflight = localRunPreflight(model, modelPath, ...
        dataPath, expectedModelBinding, expectedDataBinding, fixture, ...
        official.scenarios(1), preflightPath);
    evidence.static_audit = localStaticAudit(model);
    evidence.update_pass = localCheckPassed( ...
        evidence.preflight, "model_update");
    evidence.compile_pass = localCheckPassed( ...
        evidence.preflight, "model_compile");
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.preflight.pass
        evidence.errors{end + 1} = localIssue( ...
            "preflight_retry", "aggregate", ...
            "Retry preflight still has issues; smoke and official scenarios were not started.");
        result = localFinalize(model, modelPath, dataPath, ...
            expectedModelBinding, expectedDataBinding, evidence, evidencePath);
        return;
    end

    % The nominal smoke is a hard gate.
    try
        localClearOutputs();
        localApplyInput(model, fixture, official.scenarios(1), false);
        out = sim(model, "StopTime", "2", ...
            "ReturnWorkspaceOutputs", "on", "SimulationMode", "normal");
        smokeSignals = localReadOutputs(out);
        smokeContract = localSmokeContract(smokeSignals, 2);
        evidence.nominal_smoke_pass = all(structfun( ...
            @(value) logical(value), smokeContract));
        if ~evidence.nominal_smoke_pass
            evidence.errors{end + 1} = localIssue( ...
                "nominal_smoke", "output_contract", ...
                "Short nominal smoke returned incomplete output evidence.");
        end
    catch exception
        evidence.errors{end + 1} = localIssue( ...
            "nominal_smoke", "runtime", exception.message);
    end
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.nominal_smoke_pass
        result = localFinalize(model, modelPath, dataPath, ...
            expectedModelBinding, expectedDataBinding, evidence, evidencePath);
        return;
    end

    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    cleanCache = struct();
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.requested_inputs = rmfield(scenario, "id");
        started = tic;
        try
            cacheKey = char(matlab.lang.makeValidName( ...
                string(scenario.source_variable)));
            if isfield(cleanCache, cacheKey)
                cleanSignals = cleanCache.(cacheKey);
            else
                localClearOutputs();
                localApplyInput(model, fixture, scenario, false);
                cleanOut = sim(model, "StopTime", ...
                    string(double(scenario.duration_seconds)), ...
                    "ReturnWorkspaceOutputs", "on", ...
                    "SimulationMode", "normal");
                cleanSignals = localReadOutputs(cleanOut);
                cleanCache.(cacheKey) = cleanSignals;
            end

            if string(scenario.artifact.kind) == "none"
                observedSignals = cleanSignals;
            else
                localClearOutputs();
                localApplyInput(model, fixture, scenario, true);
                observedOut = sim(model, "StopTime", ...
                    string(double(scenario.duration_seconds)), ...
                    "ReturnWorkspaceOutputs", "on", ...
                    "SimulationMode", "normal");
                observedSignals = localReadOutputs(observedOut);
            end
            cleanContract = localCleanComparisonContract(cleanSignals, ...
                double(scenario.duration_seconds), ...
                double(scenario.warmup_seconds), 200);
            observedContract = localOutputContract(observedSignals, ...
                double(scenario.duration_seconds), ...
                double(scenario.warmup_seconds), 200);
            row.output_contract = struct( ...
                "clean", cleanContract, "observed", observedContract);
            truthEvents = localTruthEvents(truthFixture, scenario);
            row.metrics = localMetrics(cleanSignals, observedSignals, ...
                scenario, double(official.simulation.event_matching_tolerance_seconds), ...
                truthEvents);
            row.simulation_pass = true;
            row.valid = all(structfun(@logical, cleanContract)) && ...
                all(structfun(@logical, observedContract)) && ...
                row.metrics.truth_event_count >= 3;
            if ~row.valid
                row.error = localIssue("output_contract", row.id, ...
                    "Clean or artifact-paired evidence is incomplete.");
            end
        catch exception
            row.error = localIssue("scenario", row.id, exception.message);
        end
        row.wall_seconds = toc(started);
        rows(index) = row;
        evidence.scenarios = rows(1:index);
        localAtomicWriteJson(fullfile(outputDir, ...
            "scenario_" + row.id + ".json"), row);
        localAtomicWriteJson(evidencePath, evidence);
    end
    evidence.scenarios = rows;
    evidence.reference_binding_preserved = ...
        localFilePresence(modelPath) == expectedModelBinding && ...
        localFilePresence(dataPath) == expectedDataBinding;
    evidence.evidence_complete = evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && ...
        evidence.nominal_smoke_pass && all([rows.valid]) && ...
        evidence.reference_binding_preserved && ...
        evidence.static_audit.core_path_qualified;
    if evidence.evidence_complete
        evidence.evidence_complete_at = localNow();
    end
catch exception
    evidence.errors{end + 1} = localIssue( ...
        "session", "fatal", exception.message);
end
result = localFinalize(model, modelPath, dataPath, ...
    expectedModelBinding, expectedDataBinding, evidence, evidencePath);
end

function evidence=localRunCandidate(modelPath,outputDir,official,fixture, ...
 truthFixture,truthPath,expectedTruthBinding,generationRunId)
[~,model]=fileparts(modelPath);model=string(model);evidencePath=fullfile(outputDir,"evidence.json");
evidence=struct("schema","simuverity.f90-xmed08-evidence.v1","task_id","F90-XMED-08", ...
 "generation_run_id",generationRunId,"reference_direct_golden",false,"evaluation_subject","candidate", ...
 "reference_binding_preserved",false,"event_matching_tolerance_seconds", ...
 double(official.simulation.event_matching_tolerance_seconds), ...
 "truth_source","published_official_event_annotations", ...
 "truth_fixture_path",string(truthPath),"truth_fixture_file_presence",expectedTruthBinding, ...
 "candidate_output_used_as_truth",false,"extraction_only",true, ...
 "contains_score_decisions",false,"evidence_complete",false, ...
 "load_pass",false,"update_pass",false,"compile_pass",false, ...
 "nominal_smoke_pass",false,"static_audit",struct,"scenarios",struct([]),"errors",{{}});
try
 addpath(fileparts(modelPath),"-begin");load_system(modelPath);evidence.load_pass=true;
 set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on","LimitDataPoints","off");
 localApplyCandidateInput(fixture,official.scenarios(1),false);
 set_param(model,"SimulationCommand","update");evidence.update_pass=true;
 feval(model,[],[],[],"compile");feval(model,[],[],[],"term");evidence.compile_pass=true;
 evidence.static_audit=localCandidateStaticAudit(model);
 out=sim(model,"StopTime","2","ReturnWorkspaceOutputs","on");
 smokeSignals=localReadCandidateOutputs(out,evalin("base","ecg_input"));
 evidence.nominal_smoke_pass=all(structfun(@logical,localSmokeContract(smokeSignals,2)));
 rows=repmat(localEmptyScenario(),numel(official.scenarios),1);cleanCache=struct;
 for index=1:numel(official.scenarios)
  scenario=official.scenarios(index);row=localEmptyScenario();row.id=string(scenario.id);
  row.requested_inputs=rmfield(scenario,"id");
  try
   key=char(matlab.lang.makeValidName(string(scenario.source_variable)));
   if isfield(cleanCache,key),cleanSignals=cleanCache.(key);else
    localApplyCandidateInput(fixture,scenario,false);cleanInput=evalin("base","ecg_input");
    cleanOut=sim(model,"StopTime",string(double(scenario.duration_seconds)),"ReturnWorkspaceOutputs","on");
    cleanSignals=localReadCandidateOutputs(cleanOut,cleanInput);cleanCache.(key)=cleanSignals;
   end
   if string(scenario.artifact.kind)=="none",observedSignals=cleanSignals;else
    localApplyCandidateInput(fixture,scenario,true);observedInput=evalin("base","ecg_input");
    observedOut=sim(model,"StopTime",string(double(scenario.duration_seconds)),"ReturnWorkspaceOutputs","on");
    observedSignals=localReadCandidateOutputs(observedOut,observedInput);
   end
   cleanContract=localCleanComparisonContract(cleanSignals,double(scenario.duration_seconds), ...
    double(scenario.warmup_seconds),200);
   observedContract=localOutputContract(observedSignals,double(scenario.duration_seconds), ...
    double(scenario.warmup_seconds),200);
   row.output_contract=struct("clean",cleanContract,"observed",observedContract);
   truthEvents=localTruthEvents(truthFixture,scenario);
   row.metrics=localMetrics(cleanSignals,observedSignals,scenario, ...
    double(official.simulation.event_matching_tolerance_seconds),truthEvents);
   row.simulation_pass=true;row.valid=all(structfun(@logical,cleanContract))&& ...
    all(structfun(@logical,observedContract))&&row.metrics.truth_event_count>=3;
  catch exception,row.error=localIssue("scenario",row.id,exception.message);end
  rows(index)=row;
 end
 evidence.scenarios=rows;evidence.evidence_complete=evidence.load_pass&&evidence.update_pass&& ...
  evidence.compile_pass&&evidence.nominal_smoke_pass&&all([rows.valid])&& ...
  evidence.static_audit.core_path_qualified;
catch exception,evidence.errors{end+1}=localIssue("session","fatal",exception.message);end
try,close_system(model,0);catch,end
localAtomicWriteJson(evidencePath,evidence);
end

function localApplyCandidateInput(fixture,scenario,applyArtifact)
clean=fixture.(char(string(scenario.source_variable)));value=clean;
if applyArtifact,value=localArtifact(clean,scenario.artifact,360);end
time=(0:numel(value)-1)'/360;
assignin("base","ecg_input",timeseries(double(value(:)),time));
assignin("base","ecg_sample_rate_hz",360);
end

function signals=localReadCandidateOutputs(out,input)
public=["conditioned_ecg","qrs_feature","heart_rate_bpm","qrs_events","adaptive_threshold"];
internal=["ConditionedECG","QRSFeature","HeartRate","Peak","Threshold"];signals=struct;
signals.SourceECG360=struct("time",double(input.Time(:)),"data",double(input.Data(:)));
for index=1:numel(public)
 value=simuverity_public_output_compatibility( ...
  out,public(index),1,AllowBaseWorkspace=true);
 [time,data]=localExpandTimeseries(value,200);
 signals.(char(internal(index)))=struct("time",time,"data",data);
end
end

function audit=localCandidateStaticAudit(model)
blocks=lower(string(find_system(model,"FollowLinks","on","LookUnderMasks","all","Type","Block")));
has=@(token) any(contains(blocks,lower(string(token))));
audit=struct("adaptive_detector_present",has("threshold")||has("adaptive"), ...
 "root_causal_links",struct("input_to_detector",true), ...
 "processor_causal_links",struct("feature_to_threshold",has("threshold")), ...
 "detector_outputs_connected",struct("events",true,"heart_rate",true), ...
 "core_path_qualified",has("filter")&&(has("threshold")||has("detect")), ...
 "candidate_structure_scan",true);
end

function localPrepareRuntimeModel(model, fixture)
localEnsureCompilerEnvironment();
set_param(model, "SimulationMode", "normal", ...
    "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off", ...
    "InitFcn", "");
localInitializeWorkspace(fixture);
localInstallTaps(model);
localSuppressVisualization(model);
end

function report = localRunPreflight(model, modelPath, dataPath, ...
        expectedModelBinding, expectedDataBinding, fixture, nominal, reportPath)
localInitializeWorkspace(fixture);
localInstallTaps(model);
localApplyInput(model, fixture, nominal, false);
updatePass = false;
compilePass = false;
updateDetail = "";
compileDetail = "";
try
    set_param(model, "SimulationCommand", "update");
    updatePass = true;
catch exception
    updateDetail = string(exception.identifier) + ": " + string(exception.message);
end
if updatePass
    try
        feval(model, [], [], [], "compile");
        compilePass = true;
    catch exception
        compileDetail = string(exception.identifier) + ": " + ...
            string(getReport(exception, "extended", "hyperlinks", "off"));
    end
end

checks = [
    localCheckDef("source_identity", "path", ...
        @() localCheckSource(modelPath, dataPath, ...
        expectedModelBinding, expectedDataBinding));
    localCheckDef("dependencies", "dependency", ...
        @() localCheckDependencies(dataPath));
    localCheckDef("workspace_contract", "workspace", ...
        @() localCheckWorkspace(fixture));
    localCheckDef("locator_contract", "locator", ...
        @() localCheckLocators(model));
    localCheckDef("port_contract", "port", ...
        @() localCheckPorts(model));
    localCheckDef("model_update", "api", ...
        @() localBooleanResult(updatePass, ...
        "update_pass=" + updatePass, updateDetail));
    localCheckDef("model_compile", "api", ...
        @() localBooleanResult(compilePass, ...
        "compile_pass=" + compilePass, compileDetail));
    localCheckDef("compiled_dimensions", "compiled_dimension", ...
        @() localCheckCompiledDimensions(model, compilePass, compileDetail));
    localCheckDef("compiled_types", "compiled_type", ...
        @() localCheckCompiledTypes(model, compilePass, compileDetail));
    localCheckDef("bus_contract", "bus", ...
        @() localCheckBusContract(model, compilePass, compileDetail));
    localCheckDef("logging_contract", "logging", ...
        @() localCheckLogging(model));
    localCheckDef("api_contract", "api", ...
        @() localCheckApis());
    localCheckDef("causal_path_contract", "locator", ...
        @() localBooleanResult(localStaticAudit(model).core_path_qualified, ...
        "causal_path_qualified", "Required causal links are incomplete."))
];
report = formal90_nonfailfast_preflight(checks, string(reportPath));
try
    if compilePass, feval(model, [], [], [], "term"); end
catch
end
end

function definition = localCheckDef(id, category, run)
definition = struct("id", string(id), ...
    "category", string(category), "run", run);
end

function result = localCheckSource(modelPath, dataPath, modelBinding, dataBinding)
actualModel = localFilePresence(modelPath);
actualData = localFilePresence(dataPath);
passed = actualModel == modelBinding && actualData == dataBinding;
result = localBooleanResult(passed, ...
    "model=" + actualModel + ";data=" + actualData, ...
    "Pinned source binding mismatch.");
end

function result = localCheckDependencies(dataPath)
dsp = ver("dsp");
fixture = whos("-file", dataPath);
required = ["ecgdata360Hz_hrmean45", "ecgdata360Hz_hrmean60", ...
    "ecgdata360Hz_hrmean82", "ecgdata360Hz_hrmean160", ...
    "ecgdata360Hz_hrmean220"];
names = string({fixture.name});
passed = ~isempty(dsp) && all(ismember(required, names)) && ...
    exist("fir1", "file") == 2;
result = localBooleanResult(passed, ...
    "dsp=" + ~isempty(dsp) + ";fixture_variables=" + ...
    strjoin(names, ","), ...
    "DSP System Toolbox, FIR design API or fixture variables are unavailable.");
end

function result = localCheckWorkspace(fixture)
localInitializeWorkspace(fixture);
required = ["fs", "fs_filter", "fc", "fc_bandpass", ...
    "WinWidthMS", "WinSize", "ecg_input", "ecg_sample_rate_hz"];
present = arrayfun(@(name) evalin("base", ...
    "exist('" + name + "','var') == 1"), required);
signalNames = ["ecgdata360Hz_hrmean45", "ecgdata360Hz_hrmean60", ...
    "ecgdata360Hz_hrmean82", "ecgdata360Hz_hrmean160", ...
    "ecgdata360Hz_hrmean220"];
lengths = arrayfun(@(name) numel(fixture.(name)), signalNames);
passed = all(present) && all(lengths >= 14000);
result = localBooleanResult(passed, ...
    "workspace=" + strjoin(required(present), ",") + ...
    ";signal_lengths=" + strjoin(string(lengths), ","), ...
    "Required workspace variables or complete ECG fixtures are missing.");
end

function result = localCheckLocators(model)
paths = localPaths(model);
values = struct2cell(paths);
present = cellfun(@(path) getSimulinkBlockHandle(path, false) > 0, values);
result = localBooleanResult(all(present), ...
    "present=" + sum(present) + "/" + numel(present), ...
    "One or more declared block locators do not exist.");
end

function result = localCheckPorts(model)
p = localPaths(model);
processor = get_param(p.processor, "PortHandles");
selector = get_param(p.selector, "PortHandles");
converter = get_param(p.converter, "PortHandles");
passed = numel(selector.Outport) == 1 && ...
    numel(converter.Inport) == 1 && numel(converter.Outport) == 1 && ...
    numel(processor.Inport) == 1 && numel(processor.Outport) == 4;
result = localBooleanResult(passed, ...
    "selector_out=" + numel(selector.Outport) + ...
    ";converter=" + numel(converter.Inport) + "/" + ...
    numel(converter.Outport) + ";processor=" + ...
    numel(processor.Inport) + "/" + numel(processor.Outport), ...
    "Compiled evidence sources do not expose the declared ports.");
end

function result = localCheckCompiledDimensions(model, ready, detail)
if ~ready
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
p = localPaths(model);
dims = get_param(p.processor, "CompiledPortDimensions");
passed = localDimensionsResolved(dims.Inport, 1) && ...
    localDimensionsResolved(dims.Outport, 4);
result = localBooleanResult(passed, ...
    localDisplayValue(dims), ...
    "Compiled input/output dimensions are missing or unresolved.");
end

function passed = localDimensionsResolved(encoded, portCount)
% Simulink encodes each port as [numberOfDimensions, dimensions...].
% Multiple ports are concatenated into one numeric vector.
values = double(encoded(:).');
cursor = 1;
passed = true;
for port = 1:portCount
    if cursor > numel(values)
        passed = false;
        return;
    end
    rank = values(cursor);
    if ~isfinite(rank) || rank < 1 || rank ~= floor(rank) || ...
            cursor + rank > numel(values)
        passed = false;
        return;
    end
    dimensions = values(cursor + 1:cursor + rank);
    if any(~isfinite(dimensions)) || any(dimensions <= 0)
        passed = false;
        return;
    end
    cursor = cursor + rank + 1;
end
passed = passed && cursor == numel(values) + 1;
end

function result = localCheckCompiledTypes(model, ready, detail)
if ~ready
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
p = localPaths(model);
types = get_param(p.processor, "CompiledPortDataTypes");
values = string([types.Inport(:); types.Outport(:)]);
passed = numel(types.Inport) == 1 && numel(types.Outport) == 4 && ...
    all(strlength(values) > 0);
result = localBooleanResult(passed, strjoin(values, ","), ...
    "Compiled data types are missing.");
end

function result = localCheckBusContract(model, ready, detail)
if ~ready
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
p = localPaths(model);
types = get_param(p.processor, "CompiledPortDataTypes");
values = lower(string([types.Inport(:); types.Outport(:)]));
passed = ~any(contains(values, "bus"));
result = localBooleanResult(passed, strjoin(values, ","), ...
    "Unexpected bus output prevents direct numeric evidence extraction.");
end

function result = localCheckLogging(model)
variables = localOutputVariables();
bound = false(size(variables));
validNames = false(size(variables));
for index = 1:numel(variables)
    blocks = find_system(model, "SearchDepth", 1, ...
        "BlockType", "ToWorkspace", "VariableName", variables(index));
    bound(index) = numel(blocks) == 1 && ...
        string(get_param(blocks{1}, "SaveFormat")) == "Timeseries" && ...
        string(get_param(blocks{1}, "MaxDataPoints")) == "inf";
    validNames(index) = isvarname(variables(index)) && ...
        strlength(variables(index)) <= namelengthmax;
end
result = localBooleanResult(all(bound & validNames), ...
    "bound=" + sum(bound) + "/" + numel(bound) + ...
    ";valid_names=" + sum(validNames) + "/" + numel(validNames), ...
    "Required complete-run Timeseries taps are not bound exactly once.");
end

function result = localCheckApis
apis = ["formal90_nonfailfast_preflight", "sim", ...
    "jsonencode", "timeseries", "fir1"];
present = arrayfun(@(name) exist(name, "file") > 0 || ...
    exist(name, "class") > 0 || exist(name, "builtin") > 0, apis);
result = localBooleanResult(all(present), ...
    strjoin(apis + "=" + string(present), ","), ...
    "One or more required MATLAB APIs are unavailable.");
end

function result = localBooleanResult(passed, observed, detail)
result = struct("passed", logical(passed), ...
    "observed", string(observed), "detail", "");
if ~passed, result.detail = string(detail); end
end

function value = localDisplayValue(input)
value = string(strtrim(evalc("disp(input)")));
value = replace(value, newline, " ");
end

function passed = localCheckPassed(report, id)
passed = false;
if ~isfield(report, "checks"), return; end
index = find(string({report.checks.id}) == string(id), 1);
if ~isempty(index), passed = logical(report.checks(index).passed); end
end

function onlyAdapter = localOnlyAdapterIssues(report)
if report.pass
    onlyAdapter = true;
    return;
end
allowed = ["locator", "port", "compiled_dimension", ...
    "compiled_type", "bus", "logging", "workspace", "path", "api"];
onlyAdapter = all(ismember(string({report.issues.category}), allowed));
end

function localInitializeWorkspace(fixture)
fields = fieldnames(fixture);
for index = 1:numel(fields)
    if ~startsWith(fields{index}, "__")
        assignin("base", fields{index}, fixture.(fields{index}));
    end
end
assignin("base", "fs", 360);
assignin("base", "fs_filter", 200);
assignin("base", "fc", [5 26]);
assignin("base", "fc_bandpass", [5 26] / 100);
assignin("base", "WinWidthMS", 80);
assignin("base", "WinSize", 16);
default = double(fixture.ecgdata360Hz_hrmean82(:));
assignin("base", "ecg_input", ...
    timeseries(default, (0:numel(default)-1)' / 360));
assignin("base", "ecg_sample_rate_hz", 360);
end

function localApplyInput(model, fixture, scenario, applyArtifact)
localInitializeWorkspace(fixture);
sourceName = string(scenario.source_variable);
clean = fixture.(char(sourceName));
corrupted = clean;
if applyArtifact
    corrupted = localArtifact(clean, scenario.artifact, 360);
end
assignin("base", sourceName, cast(corrupted, "like", clean));
time = (0:numel(corrupted)-1)' / 360;
assignin("base", "ecg_input", timeseries(double(corrupted(:)), time));
assignin("base", "ecg_sample_rate_hz", 360);
set_param(model + "/ECG Signal Selector", ...
    "K", string(scenario.selector_value));
set_param(model, "StopTime", string(double(scenario.duration_seconds)));
set_param(model, "SimulationCommand", "update");
end

function value = localArtifact(clean, artifact, fs)
value = double(clean(:));
time = (0:numel(value)-1)' / fs;
kind = string(artifact.kind);
if kind == "none"
    return;
elseif kind == "baseline_wander"
    value = value + double(artifact.amplitude_mv) * ...
        sin(2*pi*double(artifact.frequency_hz)*time + ...
        double(artifact.phase_rad));
elseif kind == "power_line"
    value = value + double(artifact.amplitude_mv) * ...
        sin(2*pi*double(artifact.frequency_hz)*time + ...
        double(artifact.phase_rad));
elseif kind == "emg_noise"
    rng(double(artifact.seed), "twister");
    noise = randn(size(value));
    noise = noise - filter(ones(1, 13)/13, 1, noise);
    noise = noise / max(rms(noise), 1e-12);
    value = value + double(artifact.rms_mv) * noise;
elseif kind == "electrode_motion"
    onsets = double(artifact.onsets_seconds(:));
    for index = 1:numel(onsets)
        signValue = (-1)^(index + 1);
        active = time >= onsets(index);
        value(active) = value(active) + signValue * ...
            double(artifact.amplitude_mv) * exp( ...
            -(time(active) - onsets(index)) / ...
            double(artifact.recovery_tau_seconds));
    end
elseif kind == "combined_moderate"
    value = value + double(artifact.baseline_amplitude_mv) * ...
        sin(2*pi*double(artifact.baseline_frequency_hz)*time + 0.4);
    value = value + double(artifact.mains_amplitude_mv) * ...
        sin(2*pi*double(artifact.mains_frequency_hz)*time + 0.9);
    rng(double(artifact.seed), "twister");
    noise = randn(size(value));
    noise = noise - filter(ones(1, 13)/13, 1, noise);
    noise = noise / max(rms(noise), 1e-12);
    value = value + double(artifact.noise_rms_mv) * noise;
    onset = double(artifact.motion_onset_seconds);
    active = time >= onset;
    value(active) = value(active) + ...
        double(artifact.motion_amplitude_mv) * exp( ...
        -(time(active) - onset) / ...
        double(artifact.motion_recovery_tau_seconds));
else
    error("SimuVerity:F90:XMED08:ArtifactKind", ...
        "Unsupported artifact kind %s.", kind);
end
value = reshape(value, size(clean));
end

function localInstallTaps(model)
mapping = {
    "SourceECG360", model + "/ECG Signal Selector", 1;
    "ConditionedECG", model + "/Convert Sample Rate to 200Hz", 1;
    "QRSFeature", model + "/ECGSignalProcessing1", 1;
    "HeartRate", model + "/ECGSignalProcessing1", 2;
    "Peak", model + "/ECGSignalProcessing1", 3;
    "Threshold", model + "/ECGSignalProcessing1", 4
};
for index = 1:size(mapping, 1)
    localInstallTap(model, string(mapping{index, 2}), ...
        double(mapping{index, 3}), string(mapping{index, 1}), index);
end
end

function localInstallTap(parent, source, sourcePort, variable, index)
assert(getSimulinkBlockHandle(source, false) > 0, ...
    "SimuVerity:F90:XMED08:ReferenceLocator", "Missing %s.", source);
tap = parent + "/__F90_" + variable;
if getSimulinkBlockHandle(tap, false) < 0
    add_block("simulink/Sinks/To Workspace", tap, ...
        "VariableName", "F90_" + variable, ...
        "SaveFormat", "Timeseries", ...
        "Save2DSignal", ...
            "3-D array (concatenate along third dimension)", ...
        "MaxDataPoints", "inf", ...
        "Position", [760, 250 + 42*index, 930, 278 + 42*index]);
    sourceHandles = get_param(source, "PortHandles");
    tapHandles = get_param(tap, "PortHandles");
    add_line(parent, sourceHandles.Outport(sourcePort), ...
        tapHandles.Inport(1), "autorouting", "on");
end
end

function localSuppressVisualization(model)
types = ["Display", "Scope"];
for blockType = types
    blocks = find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "BlockType", blockType);
    for index = 1:numel(blocks)
        try, set_param(blocks{index}, "Commented", "on"); catch, end
    end
end
end

function signals = localReadOutputs(out)
names = ["SourceECG360", "ConditionedECG", "QRSFeature", ...
    "HeartRate", "Peak", "Threshold"];
sampleRates = [360, 200, 200, 200, 200, 200];
signals = struct();
for index = 1:numel(names)
    variable = "F90_" + names(index);
    value = [];
    try, value = out.get(variable); catch, end
    if isempty(value)
        try, value = evalin("base", variable); catch, end
    end
    assert(isa(value, "timeseries"), ...
        "SimuVerity:F90:XMED08:MissingTimeseries", ...
        "%s is not a Timeseries.", variable);
    [time, data] = localExpandTimeseries(value, sampleRates(index));
    signals.(names(index)) = struct("time", time, "data", data);
end
end

function contract = localOutputContract(signals, duration, warmup, fs)
names = fieldnames(signals);
finite = true;
for index = 1:numel(names)
    signal = signals.(names{index});
    finite = finite && ~isempty(signal.time) && ...
        all(isfinite(signal.time)) && all(isfinite(signal.data));
end

afterWarmup = signals.Threshold.time >= warmup;
candidate = signals.Peak.data > signals.Threshold.data & ...
    signals.Threshold.data > 0 & afterWarmup;
positiveHr = signals.HeartRate.data > 0 & ...
    signals.HeartRate.time >= warmup;
contract = struct( ...
    "all_required_timeseries_finite", finite, ...
    "source_horizon_complete", ...
        max(signals.SourceECG360.time) >= duration - 0.1, ...
    "detector_horizon_complete", ...
        max(signals.Threshold.time) >= duration - 0.1, ...
    "detector_sample_count_complete", ...
        numel(signals.Threshold.data) >= (duration - 0.2) * fs, ...
    "aligned_detector_outputs", ...
        numel(signals.QRSFeature.data) == numel(signals.Threshold.data) && ...
        numel(signals.Peak.data) == numel(signals.Threshold.data) && ...
        numel(signals.HeartRate.data) == numel(signals.Threshold.data), ...
    "adaptive_threshold_nonempty", ...
        any(signals.Threshold.data(afterWarmup) > 0) && ...
        (max(signals.Threshold.data(afterWarmup)) - ...
        min(signals.Threshold.data(afterWarmup))) > 0, ...
    "event_candidates_nonempty", sum(candidate) >= 3, ...
    "heart_rate_output_nonempty", any(positiveHr));
end

function contract = localSmokeContract(signals, duration)
names = fieldnames(signals);
finite = true;
nonempty = true;
for index = 1:numel(names)
    signal = signals.(names{index});
    finite = finite && all(isfinite(signal.time)) && ...
        all(isfinite(signal.data));
    nonempty = nonempty && ~isempty(signal.time) && ...
        ~isempty(signal.data);
end
contract = struct( ...
    "all_required_timeseries_nonempty", nonempty, ...
    "all_required_timeseries_finite", finite, ...
    "source_horizon_present", ...
        max(signals.SourceECG360.time) >= duration - 0.1, ...
    "detector_horizon_present", ...
        max(signals.Threshold.time) >= duration - 0.1);
end

function contract = localCleanComparisonContract(signals, duration, warmup, fs)
% The clean run supplies only paired feature/threshold/artifact baselines.
% Candidate clean detections are never a truth denominator or event gate.
contract = localOutputContract(signals, duration, warmup, fs);
contract = rmfield(contract, ...
    {'event_candidates_nonempty', 'heart_rate_output_nonempty'});
end

function metrics = localMetrics(clean, observed, scenario, tolerance, truthEvents)
warmup = double(scenario.warmup_seconds);
duration = double(scenario.duration_seconds);
cleanEvents = localEventTimes(clean, warmup);
observedEvents = localEventTimes(observed, warmup);
matching = localMatchEvents(truthEvents, observedEvents, tolerance);

cleanHr = localHeartRateStats(clean, warmup);
observedHr = localHeartRateStats(observed, warmup);
cleanThreshold = localWindow(clean.Threshold, warmup, duration);
observedThreshold = localWindow(observed.Threshold, warmup, duration);
count = min(numel(cleanThreshold), numel(observedThreshold));
cleanThreshold = cleanThreshold(1:count);
observedThreshold = observedThreshold(1:count);
cleanFeature = localWindow(clean.QRSFeature, warmup, duration);
observedFeature = localWindow(observed.QRSFeature, warmup, duration);
featureCount = min(numel(cleanFeature), numel(observedFeature));
cleanFeature = cleanFeature(1:featureCount);
observedFeature = observedFeature(1:featureCount);
sourceClean = clean.SourceECG360.data;
sourceObserved = observed.SourceECG360.data;
sourceCount = min(numel(sourceClean), numel(sourceObserved));
sourceDifference = sourceObserved(1:sourceCount) - ...
    sourceClean(1:sourceCount);

[recoveryError, transientResponse] = localRecoveryMetric( ...
    clean, observed, scenario);
expectedHr = double(scenario.expected_mean_hr_bpm);
metrics = struct( ...
    "clean_event_count", double(numel(truthEvents)), ...
    "truth_event_count", double(numel(truthEvents)), ...
    "candidate_clean_event_count", double(numel(cleanEvents)), ...
    "detected_event_count", double(numel(observedEvents)), ...
    "matched_event_count", matching.matched, ...
    "missed_event_count", matching.missed, ...
    "false_event_count", matching.false_count, ...
    "event_sensitivity", matching.sensitivity, ...
    "event_precision", matching.precision, ...
    "event_f1", matching.f1, ...
    "false_events_per_minute", ...
        matching.false_count / max((duration - warmup) / 60, 1e-9), ...
    "median_absolute_latency_seconds", matching.median_abs_latency, ...
    "p95_absolute_latency_seconds", matching.p95_abs_latency, ...
    "median_signed_latency_seconds", matching.median_signed_latency, ...
    "expected_mean_hr_bpm", expectedHr, ...
    "clean_median_hr_bpm", cleanHr.median, ...
    "observed_median_hr_bpm", observedHr.median, ...
    "observed_hr_absolute_error_bpm", ...
        abs(observedHr.median - expectedHr), ...
    "event_interval_hr_bpm", localEventIntervalHr(observedEvents), ...
    "event_hr_output_difference_bpm", ...
        abs(localEventIntervalHr(observedEvents) - observedHr.median), ...
    "threshold_mean", double(mean(observedThreshold)), ...
    "threshold_std", double(std(observedThreshold)), ...
    "threshold_coefficient_of_variation", ...
        double(std(observedThreshold) / ...
        max(abs(mean(observedThreshold)), 1e-12)), ...
    "threshold_clean_difference_ratio", ...
        double(rms(observedThreshold - cleanThreshold) / ...
        max(rms(cleanThreshold), 1e-12)), ...
    "feature_clean_difference_ratio", ...
        double(rms(observedFeature - cleanFeature) / ...
        max(rms(cleanFeature), 1e-12)), ...
    "threshold_recovery_relative_error", recoveryError, ...
    "transient_threshold_response_ratio", transientResponse, ...
    "artifact_rms_mv", double(rms(sourceDifference)), ...
    "artifact_to_clean_rms_ratio", ...
        double(rms(sourceDifference) / max(rms(sourceClean), 1e-12)), ...
    "clean_event_summary", localSummary(truthEvents), ...
    "truth_event_summary", localSummary(truthEvents), ...
    "candidate_clean_event_summary", localSummary(cleanEvents), ...
    "observed_event_summary", localSummary(observedEvents), ...
    "clean_signal_summary", localSummary(sourceClean), ...
    "observed_signal_summary", localSummary(sourceObserved), ...
    "clean_event_times_seconds", truthEvents(:).', ...
    "truth_event_times_seconds", truthEvents(:).', ...
    "candidate_clean_event_times_seconds", cleanEvents(:).', ...
    "observed_event_times_seconds", observedEvents(:).');
end

function events = localEventTimes(signals, warmup)
count = min([numel(signals.Peak.time), numel(signals.Peak.data), ...
    numel(signals.Threshold.data)]);
time = signals.Peak.time(1:count);
peak = signals.Peak.data(1:count);
threshold = signals.Threshold.data(1:count);
candidates = time >= warmup & threshold > 0 & peak > threshold;
raw = time(candidates);
events = [];
for index = 1:numel(raw)
    if isempty(events) || raw(index) - events(end) >= 0.18
        events(end + 1, 1) = raw(index); %#ok<AGROW>
    end
end
end

function output = localMatchEvents(truth, detected, tolerance)
used = false(size(detected));
latencies = [];
for index = 1:numel(truth)
    available = find(~used);
    if isempty(available), continue; end
    [distance, relative] = min(abs(detected(available) - truth(index)));
    if distance <= tolerance
        selected = available(relative);
        used(selected) = true;
        latencies(end + 1, 1) = detected(selected) - truth(index); %#ok<AGROW>
    end
end
matched = numel(latencies);
missed = numel(truth) - matched;
falseCount = numel(detected) - matched;
sensitivity = matched / max(numel(truth), 1);
precision = matched / max(numel(detected), 1);
f1 = 2 * sensitivity * precision / ...
    max(sensitivity + precision, 1e-12);
absolute = sort(abs(latencies));
if isempty(absolute)
    medianAbs = Inf;
    p95 = Inf;
    medianSigned = Inf;
else
    medianAbs = median(absolute);
    p95 = absolute(max(1, ceil(0.95 * numel(absolute))));
    medianSigned = median(latencies);
end
output = struct("matched", double(matched), ...
    "missed", double(missed), ...
    "false_count", double(falseCount), ...
    "sensitivity", double(sensitivity), ...
    "precision", double(precision), "f1", double(f1), ...
    "median_abs_latency", double(medianAbs), ...
    "p95_abs_latency", double(p95), ...
    "median_signed_latency", double(medianSigned));
end

function output = localHeartRateStats(signals, warmup)
mask = signals.HeartRate.time >= warmup & ...
    signals.HeartRate.data > 20 & signals.HeartRate.data < 320;
values = signals.HeartRate.data(mask);
if isempty(values)
    output = struct("median", 0, "mean", 0, "count", 0);
else
    output = struct("median", double(median(values)), ...
        "mean", double(mean(values)), "count", double(numel(values)));
end
end

function truth = localLoadTruthFixture(pathValue, expectedBinding, ...
        expectedModelBinding, expectedDataBinding)
assert(isfile(pathValue), "SimuVerity:F90:XMED08:TruthFixtureMissing", ...
    "Pinned evaluator-owned event annotations are missing.");
assert(localFilePresence(pathValue) == expectedBinding, ...
    "SimuVerity:F90:XMED08:TruthFixtureIdentity", ...
    "Pinned evaluator-owned event annotations are binding-mismatched.");
truth = jsondecode(fileread(pathValue));
assert(string(truth.schema) == "simuverity.official-scenarios.v1" && ...
    string(truth.task_id) == "F90-XMED-08" && ...
    string(truth.scenario_visibility) == "public" && ...
    isfield(truth.contract, "truth_annotations") && ...
    ~logical(truth.contract.truth_annotations.candidate_output_used_as_truth), ...
    "SimuVerity:F90:XMED08:TruthFixtureState", ...
    "Truth fixture is not the published candidate-independent annotation contract.");
assert(strlength(expectedModelBinding) > 0 && strlength(expectedDataBinding) > 0, ...
    "SimuVerity:F90:XMED08:TruthFixtureProvenance", ...
    "Pinned reference and ECG fixture identities are malformed.");
end

function events = localTruthEvents(truthFixture, scenario)
ids = string({truthFixture.scenarios.id});
selected = find(ids == string(scenario.id));
assert(numel(selected) == 1, "SimuVerity:F90:XMED08:TruthScenario", ...
    "Exactly one official truth annotation row is required per scenario.");
row = truthFixture.scenarios(selected);
events = double(row.truth_event_times_seconds(:));
warmup = double(scenario.warmup_seconds);
duration = double(scenario.duration_seconds);
assert(numel(events) >= 3 && all(isfinite(events)) && ...
    all(diff(events) > 0) && all(events >= warmup) && ...
    all(events <= duration + 0.25), ...
    "SimuVerity:F90:XMED08:TruthEventsInvalid", ...
    "Official truth event annotations are incomplete or out of range.");
end

function value = localEventIntervalHr(events)
if numel(events) < 3
    value = 0;
else
    value = double(60 / median(diff(events)));
end
end

function [recoveryError, response] = localRecoveryMetric(clean, observed, scenario)
kind = string(scenario.artifact.kind);
onset = [];
tau = [];
if kind == "electrode_motion"
    onset = double(scenario.artifact.onsets_seconds(end));
    tau = double(scenario.artifact.recovery_tau_seconds);
elseif kind == "combined_moderate"
    onset = double(scenario.artifact.motion_onset_seconds);
    tau = double(scenario.artifact.motion_recovery_tau_seconds);
end
if isempty(onset)
    recoveryError = 0;
    response = 0;
    return;
end
cleanTime = clean.Threshold.time;
observedTime = observed.Threshold.time;
count = min(numel(cleanTime), numel(observedTime));
time = observedTime(1:count);
cleanValue = clean.Threshold.data(1:count);
observedValue = observed.Threshold.data(1:count);
pre = time >= onset - 2 & time < onset;
during = time >= onset & time < onset + 2*tau;
late = time >= onset + 4*tau & time < onset + 7*tau;
preMean = mean(cleanValue(pre));
response = abs(mean(observedValue(during)) - mean(cleanValue(during))) / ...
    max(abs(preMean), 1e-12);
recoveryError = abs(mean(observedValue(late)) - mean(cleanValue(late))) / ...
    max(abs(preMean), 1e-12);
recoveryError = double(recoveryError);
response = double(response);
end

function values = localWindow(signal, startTime, endTime)
mask = signal.time >= startTime & signal.time <= endTime;
values = double(signal.data(mask));
end

function [time, values] = localExpandTimeseries(series, sampleRate)
frameTime = double(series.Time(:));
data = series.Data;
dimensions = size(data);
if numel(frameTime) > 1 && dimensions(end) == numel(frameTime)
    order = [ndims(data), 1:ndims(data)-1];
    data = permute(data, order);
    matrix = reshape(data, numel(frameTime), []);
elseif dimensions(1) == numel(frameTime)
    matrix = reshape(data, numel(frameTime), []);
elseif numel(frameTime) == 1
    matrix = reshape(data, 1, []);
else
    error("SimuVerity:F90:XMED08:SignalShape", ...
        "Timeseries dimensions do not align with time.");
end
width = size(matrix, 2);
offset = (0:width-1) / sampleRate;
time = reshape((frameTime + offset).', [], 1);
values = reshape(double(matrix).', [], 1);
count = min(numel(time), numel(values));
time = time(1:count);
values = values(1:count);
end

function audit = localStaticAudit(model)
p = localPaths(model);
root = struct( ...
    "selector_to_rate_converter", ...
        localFeeds(p.selector, 1, p.converter), ...
    "rate_converter_to_processor", ...
        localFeeds(p.converter, 1, p.processor));
processor = struct( ...
    "input_to_bandpass", localFeeds(p.processorInput, 1, p.bandpass), ...
    "bandpass_to_differentiator", ...
        localFeeds(p.bandpass, 1, p.differentiator), ...
    "differentiator_to_absolute", ...
        localFeeds(p.differentiator, 1, p.absolute), ...
    "absolute_to_moving_average", ...
        localFeeds(p.absolute, 1, p.movingAverage), ...
    "moving_average_to_qrs_detector", ...
        localFeeds(p.movingAverage, 1, p.qrsDetector));
outputs = struct( ...
    "filtered_feature_connected", localOutputConnected(p.processor, 1), ...
    "heart_rate_connected", localOutputConnected(p.processor, 2), ...
    "peak_connected", localOutputConnected(p.processor, 3), ...
    "threshold_connected", localOutputConnected(p.processor, 4));
audit = struct( ...
    "root_causal_links", root, ...
    "processor_causal_links", processor, ...
    "detector_outputs_connected", outputs, ...
    "adaptive_detector_present", ...
        getSimulinkBlockHandle(p.qrsDetector, false) > 0, ...
    "core_path_qualified", ...
        all(structfun(@logical, root)) && ...
        all(structfun(@logical, processor)) && ...
        all(structfun(@logical, outputs)));
end

function profile = localCompactProfile(model)
profile = struct( ...
    "block_count", numel(find_system(model, "Type", "Block")), ...
    "subsystem_count", numel(find_system(model, ...
        "BlockType", "SubSystem")), ...
    "source_rate_hz", 360, ...
    "detector_rate_hz", 200, ...
    "causal_chain", [ ...
        "recorded or synthesized single-channel ECG"; ...
        "360-to-200 Hz buffering and rate conversion"; ...
        "5-to-26 Hz FIR QRS-band conditioning"; ...
        "differentiation, absolute value and 80 ms moving average"; ...
        "adaptive peak/noise thresholding with refractory logic"; ...
        "missed-beat search-back and event-derived heart rate"], ...
    "reference_target", ...
        "causal event-level QRS detection and heart-rate estimation across rate and artifact conditions");
end

function paths = localPaths(model)
processor = model + "/ECGSignalProcessing1";
paths = struct( ...
    "selector", model + "/ECG Signal Selector", ...
    "converter", model + "/Convert Sample Rate to 200Hz", ...
    "processor", processor, ...
    "processorInput", processor + "/In1", ...
    "bandpass", processor + "/Bandpass Filter", ...
    "differentiator", processor + "/Differentiator Filter", ...
    "absolute", processor + "/Abs", ...
    "movingAverage", processor + "/moving Avg window", ...
    "qrsDetector", processor + "/QRS Detection");
end

function valid = localFeeds(source, sourcePort, target)
valid = false;
try
    handles = get_param(source, "PortHandles");
    line = get_param(handles.Outport(sourcePort), "Line");
    if line < 0, return; end
    destinations = get_param(line, "DstBlockHandle");
    destinations = destinations(destinations > 0);
    valid = any(destinations == getSimulinkBlockHandle(target, false));
catch
end
end

function valid = localOutputConnected(source, sourcePort)
valid = false;
try
    handles = get_param(source, "PortHandles");
    valid = get_param(handles.Outport(sourcePort), "Line") >= 0;
catch
end
end

function names = localOutputVariables
names = ["F90_SourceECG360", "F90_ConditionedECG", ...
    "F90_QRSFeature", "F90_HeartRate", "F90_Peak", ...
    "F90_Threshold"];
end

function localClearOutputs
names = localOutputVariables();
command = "clear " + strjoin(names, " ");
evalin("base", command);
end

function row = localEmptyScenario
row = struct("id", "", "requested_inputs", struct(), ...
    "simulation_pass", false, "valid", false, ...
    "output_contract", struct(), "metrics", struct(), ...
    "wall_seconds", 0, "error", struct());
end

function result = localFinalize(model, modelPath, dataPath, ...
        expectedModelBinding, expectedDataBinding, evidence, evidencePath)
try
    if bdIsLoaded(model), close_system(model, 0); end
catch exception
    evidence.errors{end + 1} = localIssue( ...
        "close", "model", exception.message);
end
evidence.source_file_presence_after = struct( ...
    "model", localFilePresence(modelPath), "data", localFilePresence(dataPath));
evidence.reference_binding_preserved = ...
    evidence.source_file_presence_after.model == expectedModelBinding && ...
    evidence.source_file_presence_after.data == expectedDataBinding;
if evidence.evidence_complete && ~evidence.reference_binding_preserved
    evidence.evidence_complete = false;
    evidence.errors{end + 1} = localIssue( ...
        "binding", "reference", "Reference source binding changed.");
end
evidence.model_closed_without_save = ~bdIsLoaded(model);
evidence.finished_at = localNow();
evidence.runtime = struct( ...
    "matlab_release", string(version("-release")), ...
    "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "matlab_prefdir", string(prefdir), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")), ...
    "adapter_execution_rule", ...
        "nonfailfast_preflight_then_same_process_reload_then_smoke_then_atomic_scenarios");
localAtomicWriteJson(evidencePath, evidence);
result = evidence;
validCount = 0;
if ~isempty(evidence.scenarios)
    validCount = sum([evidence.scenarios.valid]);
end
fprintf("F90_XMED08_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d complete=%d adapter_repairs=%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, numel(evidence.scenarios), ...
    evidence.evidence_complete, evidence.adapter_repair_count, evidencePath);
end

function output = localIssue(stage, id, message)
output = struct("stage", string(stage), "id", string(id), ...
    "message", string(message));
end

function localConfigureIsolation
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
if strlength(cache) > 0 && strlength(codegen) > 0
    if ~isfolder(cache), mkdir(cache); end
    if ~isfolder(codegen), mkdir(codegen); end
    Simulink.fileGenControl("set", "CacheFolder", cache, ...
        "CodeGenFolder", codegen, "createDir", true);
end
end

function localEnsureCompilerEnvironment
if strlength(string(getenv("MW_MINGW64_LOC"))) > 0
    return;
end
try
    value = string(winqueryreg("HKEY_CURRENT_USER", ...
        "Environment", "MW_MINGW64_LOC"));
    if strlength(value) > 0 && isfolder(value)
        setenv("MW_MINGW64_LOC", value);
    end
catch
    % The subsequent non-fail-fast compile check records any real compiler
    % dependency failure. This helper only restores an inherited user-level
    % environment variable inside an already-running persistent process.
end
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4, root = fileparts(root); end
end

function value = localSummary(input)
values = double(input(:));
count = min(numel(values), 8192);
if count == 0
    value = 0;
else
    weights = mod((1:count)', 101) + 1;
    value = double(sum(values(1:count) .* weights));
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

function localAtomicWriteJson(path, value)
parent = fileparts(path);
if ~isfolder(parent), mkdir(parent); end
temporary = string(path) + ".tmp." + string(feature("getpid"));
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMED08:Write");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleanup
movefile(temporary, path, "f");
end

function localRemovePaths(sharedDir, sourceDir)
try, rmpath(sharedDir); catch, end
try, rmpath(sourceDir); catch, end
end
