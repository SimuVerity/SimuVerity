function result = f90_xaero06_extract_reference_evidence( ...
        modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
% Extract fixed complete-run HL-20 approach/landing evidence. Scoring is offline.

arguments
    modelPath (1,1) string = ""
    outputDir (1,1) string = ""
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end

repo = localProjectRoot();
explicitReferenceBoundary = strlength(officialScenarios) > 0 && ...
    strlength(evaluatorAssetRoot) > 0;
if explicitReferenceBoundary
    evaluationMode = "reference";
else
    evaluationMode = officialScenarios;
    if strlength(evaluationMode) == 0, evaluationMode = "reference"; end
    officialScenarios = simuverity_official_scenarios_path();
end
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
sourceDir = fullfile(taskDir, "reference", "source");
if strcmpi(string(evaluationMode), "reference")
    if explicitReferenceBoundary
        sourceDir = evaluatorAssetRoot;
    else
        sourceDir = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
    end
    assert(isfolder(sourceDir), "SimuVerity:F90:XAERO06:ReferenceAssetRoot", ...
        "Evaluator-owned reference asset root is missing.");
end
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = fullfile(sourceDir, "aeroblk_HL20_UE.slx");
end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xaero06_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(repo, "results", "cross_domain", ...
        "simuverity_public", "F90-XAERO-06", "fixed_evidence", generationRunId);
end
if ~isfolder(outputDir), mkdir(outputDir); end

sharedDir = fullfile(repo, "scripts", "formal90", "shared");
assert(isfile(officialScenarios), "SimuVerity:F90:XAERO06:OfficialScenarios", ...
    "Official scenario contract is missing.");
official = jsondecode(fileread(officialScenarios));
if strcmpi(string(evaluationMode), "candidate")
    addpath(sharedDir, "-begin");
    pathCleanup = onCleanup(@() rmpath(sharedDir)); %#ok<NASGU>
    localConfigureIsolation();
    result = localRunCandidate(modelPath, outputDir, official, generationRunId);
    return;
end
addpath(sharedDir, "-begin");
addpath(sourceDir, "-begin");
pathCleanup = onCleanup(@() localRemovePaths(sharedDir, sourceDir)); %#ok<NASGU>
localConfigureIsolation();
libraryPath = fullfile(sourceDir, "aeroblk_lib_HL20.slx");
initPath = fullfile(sourceDir, "aeroblk_init_HL20.m");
gainPath = fullfile(sourceDir, "aeroblk_HL20_autopilot_gains.mat");
glidePath = fullfile(sourceDir, "aeroblk_HL20_glideslope.mat");
expected = struct( ...
    "model", "present", ...
    "library", "present", ...
    "init", "present", ...
    "gains", "present", ...
    "glide", "present");
bindingBefore = localSourceBindings(modelPath, libraryPath, initPath, gainPath, glidePath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[~, model] = fileparts(modelPath);
evidencePath = fullfile(outputDir, "evidence.json");

evidence = struct( ...
    "schema", "simuverity.f90-xaero06-evidence.v1", ...
    "task_id", "F90-XAERO-06", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "source_file_presence_before", bindingBefore, ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "reference_runtime_changes", ...
        "in-memory headless presentation suppression, measurement taps, adaptive zero-crossing evaluation and supported scenario parameter overrides only", ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "EVIDENCE_COMPLETE", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "preflight", struct(), ...
    "adapter_repair_count", 9, ...
    "static_audit", struct(), ...
    "profile", struct(), ...
    "output_columns", localOutputColumns(), ...
    "scenarios", [], ...
    "errors", {{}}, ...
    "started_at", localNow());
localAtomicWriteJson(evidencePath, evidence);

try
    assert(isReference, "SimuVerity:F90:XAERO06:ReferenceIdentity", ...
        "Pinned HL-20 source identity differs.");
    load_system(modelPath);
    load_system(libraryPath);
    evidence.load_pass = true;
    localPrepareRuntimeModel(model, sourceDir);
    evidence.static_audit = localStaticAudit(model);
    evidence.profile = localCompactProfile();

    preflightPath = fullfile(outputDir, "preflight.json");
    evidence.preflight = localRunPreflight(model, modelPath, ...
        libraryPath, initPath, gainPath, glidePath, expected, ...
        official.scenarios(1), preflightPath);
    evidence.update_pass = localCheckPassed(evidence.preflight, "model_update");
    evidence.compile_pass = localCheckPassed(evidence.preflight, "model_compile");
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.preflight.pass
        evidence.errors{end + 1} = localIssue("preflight", "aggregate", ...
            "Full non-fail-fast preflight failed; smoke and official scenarios were not started.");
        result = localFinalize(model, modelPath, libraryPath, initPath, ...
            gainPath, glidePath, expected, evidence, evidencePath);
        return;
    end

    % A short nominal smoke is a hard gate.
    try
        localClearOutputs();
        localApplyScenario(model, sourceDir, official.scenarios(1));
        smokeOut = sim(model, "StopTime", "0.5", ...
            "ReturnWorkspaceOutputs", "on", "CaptureErrors", "on");
        assert(strlength(string(smokeOut.ErrorMessage)) == 0, ...
            "SimuVerity:F90:XAERO06:SmokeSimulation", "%s", smokeOut.ErrorMessage);
        smokeSignals = localReadOutputs(smokeOut);
        smokeContract = localSmokeContract(smokeSignals);
        evidence.nominal_smoke_pass = localAllTrue(smokeContract);
        if ~evidence.nominal_smoke_pass
            evidence.errors{end + 1} = localIssue("smoke", ...
                "output_contract", jsonencode(smokeContract));
        end
    catch exception
        evidence.nominal_smoke_pass = false;
        evidence.errors{end + 1} = localIssue("smoke", ...
            string(exception.identifier), exception.message);
    end
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.nominal_smoke_pass
        result = localFinalize(model, modelPath, libraryPath, initPath, ...
            gainPath, glidePath, expected, evidence, evidencePath);
        return;
    end

    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.class = string(scenario.class);
        row.requested_inputs = localScenarioInputs(scenario);
        started = tic;
        try
            localClearOutputs();
            applied = localApplyScenario(model, sourceDir, scenario);
            out = sim(model, "StopTime", ...
                string(official.simulation.stop_s), ...
                "ReturnWorkspaceOutputs", "on", "CaptureErrors", "on");
            assert(strlength(string(out.ErrorMessage)) == 0, ...
                "SimuVerity:F90:XAERO06:ScenarioSimulation", "%s", out.ErrorMessage);
            signals = localReadOutputs(out);
            contract = localOutputContract(signals);
            metrics = localMetrics(signals, scenario, applied);
            rawPath = fullfile(outputDir, ...
                "raw_" + string(scenario.id) + ".mat");
            localAtomicSaveRaw(rawPath, signals, applied);
            row.simulation_pass = true;
            row.output_contract = contract;
            row.metrics = metrics;
            row.raw_log_path = string(rawPath);
            row.valid = localAllTrue(contract);
            if ~row.valid
                row.error = localIssue("scenario_contract", ...
                    string(scenario.id), jsonencode(contract));
            end
        catch exception
            row.simulation_pass = false;
            row.valid = false;
            row.error = localIssue("scenario", ...
                string(exception.identifier), exception.message);
        end
        row.wall_seconds = toc(started);
        rows(index) = row;
        localAtomicWriteJson(fullfile(outputDir, ...
            "scenario_" + string(scenario.id) + ".json"), row);
        evidence.scenarios = rows(1:index);
        localAtomicWriteJson(evidencePath, evidence);
    end
    evidence.scenarios = rows;
    evidence.EVIDENCE_COMPLETE = evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && ...
        evidence.nominal_smoke_pass && evidence.static_audit.core_path_qualified && ...
        numel(rows) == numel(official.scenarios) && all([rows.valid]);
    if evidence.EVIDENCE_COMPLETE
        evidence.evidence_complete_at = localNow();
    end
catch exception
    evidence.errors{end + 1} = localIssue("session", ...
        string(exception.identifier), exception.message);
end
result = localFinalize(model, modelPath, libraryPath, initPath, ...
    gainPath, glidePath, expected, evidence, evidencePath);
end

function evidence=localRunCandidate(modelPath,outputDir,official,generationRunId)
[~,model]=fileparts(modelPath); model=string(model); evidencePath=fullfile(outputDir,"evidence.json");
evidence=struct("schema","simuverity.f90-xaero06-evidence.v1", ...
 "task_id","F90-XAERO-06","generation_run_id",generationRunId,"reference_direct_golden",false, ...
 "evaluation_subject","candidate","EVIDENCE_COMPLETE",false,"load_pass",false, ...
 "update_pass",false,"compile_pass",false,"nominal_smoke_pass",false, ...
 "score_inputs_valid",false,"diagnostics_valid",false, ...
 "static_audit",struct,"scenarios",struct([]),"errors",{{}});
try
 addpath(fileparts(modelPath),"-begin");load_system(modelPath);evidence.load_pass=true;
 localApplyCandidateScenario(official.scenarios(1));
 set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on", ...
  "LimitDataPoints","off","SimulationCommand","update");evidence.update_pass=true;
 feval(model,[],[],[],"compile");feval(model,[],[],[],"term");evidence.compile_pass=true;
 evidence.static_audit=localCandidateStaticAudit(model);
 smokeOut=sim(model,"StopTime","0.5","ReturnWorkspaceOutputs","on");
 smokeSignals=localReadCandidateOutputs(smokeOut);
 evidence.nominal_smoke_pass=localAllTrue(localSmokeContract(smokeSignals));
 rows=repmat(localEmptyScenario(),numel(official.scenarios),1);
 for index=1:numel(official.scenarios)
  scenario=official.scenarios(index);row=localEmptyScenario();row.id=string(scenario.id);
  row.class=string(scenario.class);row.requested_inputs=localScenarioInputs(scenario);
  try
   applied=localApplyCandidateScenario(scenario);
   out=sim(model,"StopTime",string(official.simulation.stop_s),"ReturnWorkspaceOutputs","on");
   signals=localReadCandidateOutputs(out);row.output_contract=localOutputContract(signals);
   row.metrics=localMetrics(signals,scenario,applied);row.simulation_pass=true;
   row.valid=localAllTrue(row.output_contract);
  catch exception,row.error=localIssue("scenario",string(exception.identifier),exception.message);end
  rows(index)=row;
 end
 evidence.scenarios=rows;
 scenarioEvidenceValid=numel(rows)==numel(official.scenarios)&& ...
  all([rows.simulation_pass])&&all([rows.valid]);
 evidence.diagnostics_valid=evidence.load_pass&&evidence.update_pass&& ...
  evidence.compile_pass&&evidence.nominal_smoke_pass&& ...
  evidence.static_audit.candidate_structure_scan&&scenarioEvidenceValid;
 evidence.score_inputs_valid=evidence.diagnostics_valid&& ...
  evidence.static_audit.core_path_qualified;
 evidence.EVIDENCE_COMPLETE=evidence.score_inputs_valid;
 evidence.evidence_complete=evidence.EVIDENCE_COMPLETE;
catch exception,evidence.errors{end+1}=localIssue("session",string(exception.identifier),exception.message);end
try,close_system(model,0);catch,end
localAtomicWriteJson(evidencePath,evidence);
end

function applied=localApplyCandidateScenario(scenario)
names=["InitialAirspeedScale","InitialBankOffset_deg","VehicleMassScale","WindSeverityScale"];
for name=names,assignin("base",name,double(scenario.(name)));end
applied=localScenarioInputs(scenario);
end

function signals=localReadCandidateOutputs(out)
landing=simuverity_public_output_compatibility(out,"landing_state",16,AllowBaseWorkspace=true);
guidance=simuverity_public_output_compatibility(out,"guidance_command",3,AllowBaseWorkspace=true);
command=simuverity_public_output_compatibility(out,"surface_command_deg",6,AllowBaseWorkspace=true);
position=simuverity_public_output_compatibility(out,"surface_position_deg",6,AllowBaseWorkspace=true);
signals=struct("LandingState",localSeries(landing),"Guidance",localSeries(guidance), ...
 "SurfaceCommand",localSeries(command),"SurfacePosition",localSeries(position));
end

function audit=localCandidateStaticAudit(model)
blockPaths=string(find_system(model,"FollowLinks","on","LookUnderMasks","all","Type","Block"));
blocks=lower(blockPaths);
blockNames=lower(string(get_param(cellstr(blockPaths),"Name")));
has=@(token) any(contains(blocks,lower(string(token))));
hasExact=@(token) any(blockNames==lower(string(token)));
sixDofPresent=has("6dof")||has("six")|| ...
 (hasExact("veh_plant")&&hasExact("eom"));
atmospherePresent=has("atmosphere")||hasExact("atmos_wind");
aerodynamicsPresent=has("aero");
guidanceToControl=has("guidance")&& ...
 (has("control")||hasExact("guidance_ctl"));
boundedActuators=has("actuator")||has("saturation");
zeroSustainedThrust=~has("engine")&&~has("thrust");
corePathQualified=sixDofPresent&&atmospherePresent&& ...
 aerodynamicsPresent&&guidanceToControl&&boundedActuators&& ...
 zeroSustainedThrust;
audit=struct("six_dof_present",sixDofPresent, ...
 "atmosphere_present",atmospherePresent, ...
 "aerodynamics_present",aerodynamicsPresent, ...
 "guidance_to_control",guidanceToControl, ...
 "bounded_actuators",boundedActuators, ...
 "zero_sustained_thrust",zeroSustainedThrust, ...
 "core_path_qualified",corePathQualified, ...
 "candidate_structure_scan",true);
end

function localPrepareRuntimeModel(model, sourceDir)
localEnsureCompilerEnvironment();
set_param(model, "SimulationMode", "normal", ...
    "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off", ...
    "ZeroCrossAlgorithm", "Adaptive", ...
    "MaxConsecutiveZCsMsg", "warning");
addpath(sourceDir, "-begin");
localSuppressPresentation(model);
localInstallTaps(model);
end

function report = localRunPreflight(model, modelPath, libraryPath, ...
        initPath, gainPath, glidePath, expected, nominal, reportPath)
localApplyScenario(model, fileparts(modelPath), nominal);
updatePass = false;
compilePass = false;
updateDetail = "";
compileDetail = "";
try
    set_param(model, "SimulationCommand", "update");
    updatePass = true;
catch exception
    updateDetail = localExtendedError(exception);
end
if updatePass
    try
        feval(model, [], [], [], "compile");
        compilePass = true;
    catch exception
        compileDetail = localExtendedError(exception);
    end
end
causalAudit = localStaticAudit(model);
checks = [
    localCheckDef("source_identity", "path", ...
        @() localCheckSource(modelPath, libraryPath, initPath, ...
        gainPath, glidePath, expected));
    localCheckDef("dependencies", "dependency", @() localCheckDependencies());
    localCheckDef("workspace_contract", "workspace", @() localCheckWorkspace());
    localCheckDef("locator_contract", "locator", @() localCheckLocators(model));
    localCheckDef("port_contract", "port", @() localCheckPorts(model));
    localCheckDef("model_update", "api", @() localBooleanResult( ...
        updatePass, "update_pass=" + updatePass, updateDetail));
    localCheckDef("model_compile", "api", @() localBooleanResult( ...
        compilePass, "compile_pass=" + compilePass, compileDetail));
    localCheckDef("compiled_dimensions", "compiled_dimension", ...
        @() localCheckCompiledDimensions(model, compilePass, compileDetail));
    localCheckDef("compiled_types", "compiled_type", ...
        @() localCheckCompiledTypes(model, compilePass, compileDetail));
    localCheckDef("bus_contract", "bus", ...
        @() localCheckBusContract(model, compilePass, compileDetail));
    localCheckDef("logging_contract", "logging", @() localCheckLogging(model));
    localCheckDef("runtime_path_contract", "path", ...
        @() localCheckRuntimePath(reportPath));
    localCheckDef("api_contract", "api", @() localCheckApis());
    localCheckDef("causal_path_contract", "locator", ...
        @() localBooleanResult(causalAudit.core_path_qualified, ...
        "core_path_qualified", "Required closed-loop causal path is incomplete."))
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

function result = localCheckSource(modelPath, libraryPath, initPath, ...
        gainPath, glidePath, expected)
observed = localSourceBindings(modelPath, libraryPath, initPath, gainPath, glidePath);
passed = localBindingsEqual(observed, expected);
result = localBooleanResult(passed, ...
    "model=" + observed.model + ";library=" + observed.library, ...
    "Pinned source bindings differ.");
end

function result = localCheckDependencies()
productInfo = ver;
products = string({productInfo.Name});
required = ["Simulink", "Aerospace Toolbox", ...
    "Aerospace Blockset", "Control System Toolbox"];
present = false(size(required));
for index = 1:numel(required)
    present(index) = any(strcmpi(products, required(index)));
end
passed = all(present) && ~isempty(which("aeroblk_init_HL20")) && ...
    ~isempty(which("Simulink.fileGenControl"));
result = localBooleanResult(passed, ...
    "products=" + join(required(present), ","), ...
    "One or more required R2025a products or initialization files are unavailable.");
end

function result = localCheckWorkspace()
required = ["xme_0", "Vmw", "Euler_0", "pm_0", "mass", ...
    "Inertia", "wn_act", "z_act", "max_lim", "min_lim", ...
    "InitialAirspeedScale", "InitialBankOffset_deg", ...
    "VehicleMassScale", "WindSeverityScale"];
present = arrayfun(@(name) evalin("base", ...
    "exist('" + name + "','var') == 1"), required);
validNames = arrayfun(@(name) isvarname(char(name)) && ...
    ~iskeyword(char(name)) && strlength(name) <= namelengthmax, required);
result = localBooleanResult(all(present) && all(validNames), ...
    "present=" + sum(present) + "/" + numel(required) + ...
    ";valid_names=" + sum(validNames) + "/" + numel(required), ...
    "Workspace initialization or variable-name contract is incomplete.");
end

function paths = localPaths(model)
% A literal slash in a Simulink block name is escaped as // in a path.
paths = struct( ...
    "actuators", model + "/Actuators", ...
    "airdata", model + "/Airdata System", ...
    "control", model + "/Control System", ...
    "guidance", model + "/Guidance System", ...
    "airframe", model + "/HL20" + newline + "Airframe", ...
    "sensors", model + "/IMU,GPS " + newline + "& Radar Altimeter", ...
    "modelbus", model + "/Model" + newline + "o//p bus", ...
    "thrust", model + "/Thrust", ...
    "visualization", model + "/UE Visualization");
end

function result = localCheckLocators(model)
paths = localPaths(model);
% UE Visualization is intentionally commented for headless evidence runs.
% It is presentation-only and must not be a core task locator.
corePaths = rmfield(paths, "visualization");
values = string(struct2cell(corePaths));
present = arrayfun(@(path) getSimulinkBlockHandle(path, false) > 0, values);
wind = localWindBlocks();
windPresent = all(arrayfun(@(path) ...
    getSimulinkBlockHandle(path, false) > 0, string(struct2cell(wind))));
result = localBooleanResult(all(present) && windPresent, ...
    "top=" + sum(present) + "/" + numel(present) + ...
    ";wind=" + windPresent, "A required model locator is missing.");
end

function result = localCheckPorts(model)
paths = localPaths(model);
guidance = get_param(paths.guidance, "PortHandles");
control = get_param(paths.control, "PortHandles");
actuators = get_param(paths.actuators, "PortHandles");
airframe = get_param(paths.airframe, "PortHandles");
passed = numel(guidance.Inport) == 1 && numel(guidance.Outport) == 1 && ...
    numel(control.Inport) == 3 && numel(control.Outport) == 1 && ...
    numel(actuators.Inport) == 1 && numel(actuators.Outport) == 1 && ...
    numel(airframe.Inport) == 2 && numel(airframe.Outport) == 11;
result = localBooleanResult(passed, ...
    "guidance=1/1;control=3/1;actuators=1/1;airframe=2/11", ...
    "Compiled top-level interface differs from the pinned source.");
end

function result = localCheckCompiledDimensions(model, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
paths = localPaths(model);
blocks = [paths.guidance, paths.control, paths.actuators, paths.airframe];
passed = true;
observed = strings(size(blocks));
for index = 1:numel(blocks)
    dims = get_param(blocks(index), "CompiledPortDimensions");
    encoded = [double(dims.Inport(:)); double(dims.Outport(:))];
    passed = passed && ~isempty(encoded) && all(isfinite(encoded)) && ...
        ~any(encoded == -1);
    observed(index) = mat2str(encoded');
end
result = localBooleanResult(passed, join(observed, ";"), ...
    "One or more compiled port dimensions are unresolved.");
end

function result = localCheckCompiledTypes(model, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
paths = localPaths(model);
blocks = [paths.guidance, paths.control, paths.actuators, paths.airframe];
types = strings(0);
passed = true;
for block = blocks
    value = get_param(block, "CompiledPortDataTypes");
    current = [string(value.Inport(:)); string(value.Outport(:))];
    passed = passed && all(strlength(current) > 0);
    types = [types; current]; %#ok<AGROW>
end
result = localBooleanResult(passed, join(types, ","), ...
    "One or more compiled port types are unresolved.");
end

function result = localCheckBusContract(model, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
paths = localPaths(model);
numericBlocks = [paths.guidance, paths.control, paths.actuators];
passed = true;
observed = strings(0);
for block = numericBlocks
    value = get_param(block, "CompiledPortDataTypes");
    current = string(value.Outport(:));
    passed = passed && all(~startsWith(current, "Bus:"));
    observed = [observed; current]; %#ok<AGROW>
end
result = localBooleanResult(passed, join(observed, ","), ...
    "Guidance or actuator evidence unexpectedly compiles as an unresolved bus.");
end

function result = localCheckLogging(model)
variables = ["Xe", "Ve", "Euler", "Pqr", "AlphaBeta", ...
    "Mach", "Qbar", "Guidance", "SurfaceCommand", "SurfacePosition"];
present = arrayfun(@(name) getSimulinkBlockHandle( ...
    model + "/__F90_" + name, false) > 0, variables);
valid = arrayfun(@(name) isvarname("F90_" + name), variables);
result = localBooleanResult(all(present) && all(valid), ...
    "bound=" + sum(present) + "/" + numel(present) + ...
    ";valid_names=" + sum(valid) + "/" + numel(valid), ...
    "One or more required measurement taps are unavailable.");
end

function result = localCheckRuntimePath(reportPath)
paths = [string(reportPath), string(getenv("MATLAB_PREFDIR")), ...
    string(getenv("SIMULINK_CACHE_FOLDER")), ...
    string(getenv("SIMULINK_CODEGEN_FOLDER"))];
lengths = strlength(paths);
passed = all(lengths > 0) && max(lengths) < 220;
result = localBooleanResult(passed, ...
    "lengths=" + join(string(lengths), ","), ...
    "Runtime path is empty or unsafe for the Windows worker.");
end

function result = localCheckApis()
names = ["formal90_nonfailfast_preflight", "sim", "jsonencode", ...
    "timeseries", "interp1", "aeroblk_init_HL20"];
present = arrayfun(@(name) ~isempty(which(name)), names);
result = localBooleanResult(all(present), ...
    join(names(present), ","), "One or more required APIs are unavailable.");
end

function result = localBooleanResult(passed, observed, detail)
result = struct("passed", logical(passed), ...
    "observed", string(observed), "detail", string(detail));
if passed, result.detail = ""; end
end

function passed = localCheckPassed(report, id)
passed = false;
for index = 1:numel(report.checks)
    if string(report.checks(index).id) == string(id)
        passed = logical(report.checks(index).passed);
        return;
    end
end
end

function applied = localApplyScenario(model, sourceDir, scenario)
old = pwd;
cleanup = onCleanup(@() cd(old)); %#ok<NASGU>
cd(sourceDir);
evalin("base", "aeroblk_init_HL20");
airspeedScale = double(scenario.InitialAirspeedScale);
bankDeg = double(scenario.InitialBankOffset_deg);
massScale = double(scenario.VehicleMassScale);
windScale = double(scenario.WindSeverityScale);
evalin("base", "Vmw = Vmw * " + airspeedScale + ";");
evalin("base", "Euler_0(1) = " + deg2rad(bankDeg) + ";");
evalin("base", "mass = mass * " + massScale + ";");
evalin("base", "Inertia = Inertia * " + massScale + ";");
assignin("base", "InitialAirspeedScale", airspeedScale);
assignin("base", "InitialBankOffset_deg", bankDeg);
assignin("base", "VehicleMassScale", massScale);
assignin("base", "WindSeverityScale", windScale);
localApplyWindScale(windScale);
set_param(model, "StopTime", "70");
applied = struct( ...
    "InitialAirspeedScale", airspeedScale, ...
    "InitialBankOffset_deg", bankDeg, ...
    "VehicleMassScale", massScale, ...
    "WindSeverityScale", windScale, ...
    "initial_position_ned_m", evalin("base", "xme_0"), ...
    "initial_body_velocity_mps", evalin("base", "Vmw"), ...
    "initial_euler_rad", evalin("base", "Euler_0"), ...
    "mass_kg", evalin("base", "mass"));
end

function blocks = localWindBlocks()
library = "aeroblk_lib_HL20";
if ~bdIsLoaded(library)
    load_system(library);
end
try, set_param(library, "Lock", "off"); catch, end
blocks = struct( ...
    "gust", localFindNamedBlock(library, "Discrete Wind Gust Model - On"), ...
    "dryden", localFindNamedBlock(library, ...
        "Dryden Wind Turbulence Model " + newline + "(Continuous (+q -r))"), ...
    "shear", localFindNamedBlock(library, "Wind Shear Model"));
end

function path = localFindNamedBlock(root, name)
matches = find_system(root, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block", "Name", char(name));
assert(numel(matches) == 1, "SimuVerity:F90:XAERO06:WindLocator", ...
    "Expected one %s block, found %d.", name, numel(matches));
path = string(matches{1});
end

function localApplyWindScale(scale)
blocks = localWindBlocks();
set_param(blocks.gust, "v_m", mat2str(scale * [3.5 3.0 3.0], 10));
set_param(blocks.dryden, "W20", num2str(scale * 5, 12));
set_param(blocks.shear, "W_20", num2str(scale, 12));
end

function localInstallTaps(model)
paths = localPaths(model);
mapping = {
    "Xe", paths.airframe, 8;
    "Ve", paths.airframe, 7;
    "Euler", paths.airframe, 3;
    "Pqr", paths.airframe, 2;
    "AlphaBeta", paths.airframe, 9;
    "Mach", paths.airframe, 10;
    "Qbar", paths.airframe, 11;
    "Guidance", paths.guidance, 1;
    "SurfaceCommand", paths.control, 1;
    "SurfacePosition", paths.actuators, 1
};
for index = 1:size(mapping, 1)
    localInstallTap(model, string(mapping{index, 2}), ...
        double(mapping{index, 3}), string(mapping{index, 1}), index);
end
end

function localInstallTap(parent, source, sourcePort, variable, index)
assert(getSimulinkBlockHandle(source, false) > 0, ...
    "SimuVerity:F90:XAERO06:ReferenceLocator", "Missing %s.", source);
tap = parent + "/__F90_" + variable;
if getSimulinkBlockHandle(tap, false) < 0
    add_block("simulink/Sinks/To Workspace", tap, ...
        "VariableName", "F90_" + variable, ...
        "SaveFormat", "Timeseries", ...
        "Save2DSignal", "2-D array (concatenate along first dimension)", ...
        "MaxDataPoints", "inf", ...
        "Position", [835, 195 + 32*index, 980, 219 + 32*index]);
    sourceHandles = get_param(source, "PortHandles");
    tapHandles = get_param(tap, "PortHandles");
    add_line(parent, sourceHandles.Outport(sourcePort), ...
        tapHandles.Inport(1), "autorouting", "on");
end
end

function localSuppressPresentation(model)
names = ["UE Visualization", "Instrument Panel", "Scopes"];
for name = names
    block = model + "/" + name;
    if getSimulinkBlockHandle(block, false) > 0
        try, set_param(block, "Commented", "on"); catch, end
    end
end
scope = model + "/Limited" + newline + "Actuators";
if getSimulinkBlockHandle(scope, false) > 0
    try, set_param(scope, "Commented", "on"); catch, end
end
set(groot, "defaultFigureVisible", "off");
end

function signals = localReadOutputs(out)
names = ["Xe", "Ve", "Euler", "Pqr", "AlphaBeta", ...
    "Mach", "Qbar", "Guidance", "SurfaceCommand", "SurfacePosition"];
signals = struct();
for name = names
    variable = "F90_" + name;
    value = [];
    try, value = out.get(variable); catch, end
    value = localUnwrapTimeseries(value);
    if ~isa(value, "timeseries")
        baseValue = [];
        try, baseValue = evalin("base", variable); catch, end
        baseValue = localUnwrapTimeseries(baseValue);
        if isa(baseValue, "timeseries")
            value = baseValue;
        end
    end
    assert(isa(value, "timeseries"), "SimuVerity:F90:XAERO06:MissingTimeseries", ...
        "%s is not a Timeseries (%s).", variable, localDescribeValue(value));
    signals.(name) = localSeries(value);
end
signals.LandingState = localLandingState(signals);
end

function description = localDescribeValue(value)
description = "class=" + string(class(value)) + ";size=" + ...
    string(mat2str(size(value)));
if isstruct(value)
    description = description + ";fields=" + ...
        join(string(fieldnames(value)), ",");
    if isscalar(value) && isfield(value, "signals")
        description = description + ";signals_size=" + ...
            string(mat2str(size(value.signals))) + ";signals_fields=" + ...
            join(string(fieldnames(value.signals)), ",");
    end
end
end

function value = localUnwrapTimeseries(value)
if isa(value, "Simulink.SimulationData.Signal") && ...
        isa(value.Values, "timeseries")
    value = value.Values;
elseif isstruct(value) && isscalar(value) && ...
        isfield(value, "time") && isfield(value, "signals")
    payload = value.signals;
    if isstruct(payload) && all(isfield(payload, "values"))
        sampleCount = numel(value.time);
        columns = [];
        for index = 1:numel(payload)
            raw = double(payload(index).values);
            dimension = find(size(raw) == sampleCount, 1, "first");
            if isempty(dimension)
                columns = [];
                break;
            end
            order = [dimension, setdiff(1:ndims(raw), dimension, "stable")];
            columns = [columns, reshape(permute(raw, order), ...
                sampleCount, [])]; %#ok<AGROW>
        end
        if ~isempty(columns)
            value = timeseries(columns, value.time);
        end
    end
elseif isstruct(value) && isscalar(value) && ...
        isfield(value, "Time") && isfield(value, "Data")
    value = timeseries(value.Data, value.Time);
elseif isstruct(value) && isscalar(value)
    names = fieldnames(value);
    members = cell(numel(names), 1);
    allTimeseries = ~isempty(names);
    for index = 1:numel(names)
        members{index} = localUnwrapTimeseries(value.(names{index}));
        allTimeseries = allTimeseries && isa(members{index}, "timeseries");
    end
    if allTimeseries
        time = double(members{1}.Time(:));
        columns = [];
        for index = 1:numel(members)
            current = localSeries(members{index});
            columns = [columns, localInterpolate(current, time)]; %#ok<AGROW>
        end
        value = timeseries(columns, time);
    end
end
end

function series = localSeries(value)
time = double(value.Time(:));
raw = double(value.Data);
sampleCount = numel(time);
if sampleCount == 1
    data = reshape(raw, 1, []);
else
    dimensions = size(raw);
    timeDimension = find(dimensions == sampleCount, 1, "first");
    assert(~isempty(timeDimension), "SimuVerity:F90:XAERO06:SeriesShape", ...
        "No data dimension matches %d timestamps.", sampleCount);
    order = [timeDimension, setdiff(1:numel(dimensions), ...
        timeDimension, "stable")];
    data = reshape(permute(raw, order), sampleCount, []);
end
series = struct("time", time, "values", data);
end

function landing = localLandingState(signals)
time = signals.Xe.time;
landing = struct("time", time, "values", [ ...
    localInterpolate(signals.Xe, time), ...
    localInterpolate(signals.Ve, time), ...
    localInterpolate(signals.Euler, time), ...
    localInterpolate(signals.Pqr, time), ...
    localInterpolate(signals.AlphaBeta, time), ...
    localInterpolate(signals.Mach, time), ...
    localInterpolate(signals.Qbar, time)]);
end

function values = localInterpolate(series, time)
[sourceTime, uniqueIndex] = unique(series.time, "stable");
sourceValues = series.values(uniqueIndex, :);
if numel(sourceTime) == 1
    values = repmat(sourceValues(1, :), numel(time), 1);
else
    values = interp1(sourceTime, sourceValues, time, "linear", "extrap");
end
end

function contract = localSmokeContract(signals)
contract = struct( ...
    "landing_state_nonempty", ~isempty(signals.LandingState.time), ...
    "landing_state_finite", all(isfinite(signals.LandingState.values), "all"), ...
    "guidance_nonempty", ~isempty(signals.Guidance.time), ...
    "surface_command_nonempty", ~isempty(signals.SurfaceCommand.time), ...
    "surface_position_nonempty", ~isempty(signals.SurfacePosition.time), ...
    "landing_state_width_16", size(signals.LandingState.values, 2) == 16, ...
    "guidance_width_3", size(signals.Guidance.values, 2) == 3, ...
    "surface_command_width_6", size(signals.SurfaceCommand.values, 2) == 6, ...
    "surface_position_width_6", size(signals.SurfacePosition.values, 2) == 6);
end

function contract = localOutputContract(signals)
smoke = localSmokeContract(signals);
names = fieldnames(signals);
finite = true;
startsAtZero = true;
for index = 1:numel(names)
    series = signals.(names{index});
    finite = finite && all(isfinite(series.time)) && ...
        all(isfinite(series.values), "all");
    startsAtZero = startsAtZero && ~isempty(series.time) && ...
        series.time(1) <= 1e-8;
end
state = signals.LandingState.values;
altitude = -state(:, 3);
positionDynamic = max(state(:, 1)) - min(state(:, 1)) > 1000 && ...
    max(altitude) - min(altitude) > 500;
contract = smoke;
contract.all_required_timeseries_finite = finite;
contract.complete_run_starts_at_zero = startsAtZero;
contract.mission_horizon_present = signals.LandingState.time(end) >= 20;
contract.position_and_altitude_dynamic = positionDynamic;
contract.airdata_dynamic = max(state(:, 15)) - min(state(:, 15)) > 0.01;
contract.guidance_dynamic = max(signals.Guidance.values(:, 2)) - ...
    min(signals.Guidance.values(:, 2)) > 0.1;
contract.surface_command_dynamic = max(signals.SurfaceCommand.values, ...
    [], "all") - min(signals.SurfaceCommand.values, [], "all") > 0.1;
contract.surface_position_dynamic = max(signals.SurfacePosition.values, ...
    [], "all") - min(signals.SurfacePosition.values, [], "all") > 0.1;
end

function metrics = localMetrics(signals, scenario, applied)
state = signals.LandingState.values;
time = signals.LandingState.time;
position = state(:, 1:3);
velocity = state(:, 4:6);
euler = state(:, 7:9);
rates = state(:, 10:12);
alphaBeta = state(:, 13:14);
mach = state(:, 15);
qbar = state(:, 16);
altitude = -position(:, 3);
speed = sqrt(sum(velocity.^2, 2));
finalMask = time >= max(time(end) - 0.75, time(1));
terminalAltitude = median(altitude(finalMask));
terminalSpeed = median(speed(finalMask));
terminalSink = median(abs(velocity(finalMask, 3)));
glideMask = time >= max(5, time(end) - 18) & ...
    time <= max(6, time(end) - 8);
if ~any(glideMask), glideMask = time >= time(1); end
glideSink = median(abs(velocity(glideMask, 3)));
progress = (position(end, 1) - position(1, 1)) / ...
    max(abs(position(1, 1)), 1);

command = signals.SurfaceCommand;
achieved = signals.SurfacePosition;
commandAtActuator = localInterpolate(command, achieved.time);
trackingError = commandAtActuator - achieved.values;
limits = [30 30 60 60 60 60];
saturation = abs(achieved.values) >= 0.98 * limits;
guidance = signals.Guidance.values;
guidanceTime = signals.Guidance.time;
lateGuidance = guidanceTime >= max(guidanceTime(end) - 8, 0);
midGuidance = guidanceTime >= max(5, guidanceTime(end) - 25) & ...
    guidanceTime <= max(6, guidanceTime(end) - 12);
if ~any(midGuidance), midGuidance = true(size(guidanceTime)); end

rollAbsDeg = abs(rad2deg(euler(:, 1)));
recoveryTime = localRecoveryTime(time, rollAbsDeg, 0.75);
metrics = struct( ...
    "simulation_end_s", time(end), ...
    "initial_downrange_m", position(1, 1), ...
    "final_downrange_m", median(position(finalMask, 1)), ...
    "downrange_progress_fraction", progress, ...
    "initial_altitude_m", altitude(1), ...
    "terminal_altitude_m", terminalAltitude, ...
    "terminal_cross_track_m", median(abs(position(finalMask, 2))), ...
    "initial_speed_mps", speed(1), ...
    "terminal_speed_mps", terminalSpeed, ...
    "terminal_sink_rate_mps", terminalSink, ...
    "glide_sink_rate_mps", glideSink, ...
    "terminal_sink_reduction_fraction", ...
        max(0, (glideSink - terminalSink) / max(glideSink, 1e-6)), ...
    "maximum_abs_roll_deg", max(rollAbsDeg), ...
    "terminal_abs_roll_deg", median(rollAbsDeg(finalMask)), ...
    "bank_recovery_time_s", recoveryTime, ...
    "maximum_abs_pitch_deg", max(abs(rad2deg(euler(:, 2)))), ...
    "maximum_abs_body_rate_radps", max(abs(rates), [], "all"), ...
    "minimum_alpha_deg", min(rad2deg(alphaBeta(:, 1))), ...
    "maximum_alpha_deg", max(rad2deg(alphaBeta(:, 1))), ...
    "maximum_abs_beta_deg", max(abs(rad2deg(alphaBeta(:, 2)))), ...
    "minimum_mach", min(mach), ...
    "maximum_mach", max(mach), ...
    "minimum_dynamic_pressure_pa", min(qbar), ...
    "maximum_dynamic_pressure_pa", max(qbar), ...
    "surface_tracking_rmse_deg", sqrt(mean(trackingError.^2, "all")), ...
    "surface_tracking_peak_deg", max(abs(trackingError), [], "all"), ...
    "surface_saturation_fraction", mean(saturation, "all"), ...
    "surface_command_activity_deg", ...
        sqrt(mean((command.values - mean(command.values, 1)).^2, "all")), ...
    "guidance_activity_deg", ...
        sqrt(mean((guidance - mean(guidance, 1)).^2, "all")), ...
    "late_alpha_demand_change_deg", ...
        median(guidance(lateGuidance, 2)) - ...
        median(guidance(midGuidance, 2)), ...
    "flight_state_summary", localSummary(state), ...
    "guidance_summary", localSummary(guidance), ...
    "surface_command_summary", localSummary(command.values), ...
    "surface_position_summary", localSummary(achieved.values), ...
    "applied_inputs", applied, ...
    "requested_scenario_id", string(scenario.id));
end

function value = localRecoveryTime(time, signal, threshold)
value = time(end);
for index = 1:numel(time)
    if time(index) >= 0.5 && signal(index) <= threshold
        horizon = time >= time(index) & time <= time(index) + 2;
        if all(signal(horizon) <= max(1.5 * threshold, threshold + 0.25))
            value = time(index);
            return;
        end
    end
end
end

function audit = localStaticAudit(model)
paths = localPaths(model);
audit = struct( ...
    "guidance_to_control", localConnected(paths.guidance, 1, paths.control), ...
    "control_to_actuators", localConnected(paths.control, 1, paths.actuators), ...
    "actuators_to_airframe", localConnected(paths.actuators, 1, paths.airframe), ...
    "airframe_to_model_bus", localConnected(paths.airframe, 8, paths.modelbus), ...
    "model_bus_to_sensors", localConnected(paths.modelbus, 1, paths.sensors), ...
    "model_bus_to_airdata", localConnected(paths.modelbus, 1, paths.airdata), ...
    "sensors_to_guidance", localConnected(paths.sensors, 1, paths.guidance), ...
    "sensors_to_control", localConnected(paths.sensors, 2, paths.control), ...
    "airdata_to_control", localConnected(paths.airdata, 1, paths.control), ...
    "zero_sustained_thrust", ...
        strtrim(string(get_param(paths.thrust, "Value"))) == "[0 0 0]", ...
    "six_dof_present", localHasNamedBlock(model, "6DOF (Euler Angles)"), ...
    "aerodynamics_present", localHasNamedBlock(model, ...
        "Aerodynamic" + newline + "Coefficients"), ...
    "environment_present", localHasNamedBlock(model, "Environment Models"), ...
    "dynamic_actuator_present", localHasNamedBlock(model, ...
        "Nonlinear Second-Order Actuator"), ...
    "flare_guidance_present", localHasNamedBlock(model, "Flare"), ...
    "core_path_qualified", false);
values = struct2cell(rmfield(audit, "core_path_qualified"));
audit.core_path_qualified = all(cellfun(@logical, values));
end

function passed = localConnected(source, sourcePort, destination)
passed = false;
try
    sourceHandles = get_param(source, "PortHandles");
    sourcePortHandle = sourceHandles.Outport(sourcePort);
    destinationHandles = get_param(destination, "PortHandles");
    for destinationPort = destinationHandles.Inport(:)'
        line = get_param(destinationPort, "Line");
        if line > 0 && get_param(line, "SrcPortHandle") == sourcePortHandle
            passed = true;
            return;
        end
    end
catch
end
end

function passed = localHasNamedBlock(model, name)
blocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block", "Name", char(name));
passed = ~isempty(blocks);
end

function profile = localCompactProfile()
profile = struct( ...
    "plant", "unpowered finite-mass HL-20 lifting-body nonlinear aerodynamic model with 6DOF Euler rigid-body dynamics", ...
    "control", "measured airdata and inertial/navigation feedback drive approach and flare guidance, closed-loop control and bounded second-order aerodynamic-surface actuators", ...
    "causal_path", "wind and initial state -> atmosphere and nonlinear aerodynamics -> 6DOF state -> airdata/navigation feedback -> approach and flare guidance -> controller -> dynamic surface actuators -> airframe", ...
    "native_stop_time_s", 70, ...
    "official_coverage", ["nominal autoland", "low initial energy", ...
        "high initial energy", "initial bank recovery", ...
        "upper mass boundary", "enhanced native wind"]);
end

function columns = localOutputColumns()
columns = struct( ...
    "landing_state", ["north_m", "east_m", "down_m", ...
        "vn_mps", "ve_mps", "vd_mps", "roll_rad", "pitch_rad", ...
        "yaw_rad", "p_radps", "q_radps", "r_radps", ...
        "alpha_rad", "beta_rad", "mach", "qbar_pa"], ...
    "guidance_command", ["roll_demand_deg", ...
        "alpha_demand_deg", "beta_demand_deg"], ...
    "surface_command_deg", ["aileron", "elevator", "rudder", ...
        "positive_body_flap", "negative_body_flap", ...
        "differential_body_flap"], ...
    "surface_position_deg", ["aileron", "elevator", "rudder", ...
        "positive_body_flap", "negative_body_flap", ...
        "differential_body_flap"]);
end

function input = localScenarioInputs(scenario)
input = struct( ...
    "InitialAirspeedScale", double(scenario.InitialAirspeedScale), ...
    "InitialBankOffset_deg", double(scenario.InitialBankOffset_deg), ...
    "VehicleMassScale", double(scenario.VehicleMassScale), ...
    "WindSeverityScale", double(scenario.WindSeverityScale));
end

function row = localEmptyScenario()
row = struct( ...
    "id", "", "class", "", "requested_inputs", struct(), ...
    "simulation_pass", false, "valid", false, ...
    "output_contract", struct(), "metrics", struct(), ...
    "raw_log_path", "", "wall_seconds", 0, "error", struct());
end

function passed = localAllTrue(value)
fields = fieldnames(value);
passed = all(cellfun(@(name) logical(value.(name)), fields));
end

function localClearOutputs()
variables = ["F90_Xe", "F90_Ve", "F90_Euler", "F90_Pqr", ...
    "F90_AlphaBeta", "F90_Mach", "F90_Qbar", "F90_Guidance", ...
    "F90_SurfaceCommand", "F90_SurfacePosition"];
for variable = variables
    evalin("base", "if exist('" + variable + "','var'), clear('" + ...
        variable + "'); end");
end
end

function result = localFinalize(model, modelPath, libraryPath, initPath, ...
        gainPath, glidePath, expected, evidence, evidencePath)
bindingAfter = localSourceBindings(modelPath, libraryPath, initPath, gainPath, glidePath);
evidence.source_file_presence_after = bindingAfter;
evidence.reference_binding_preserved = localBindingsEqual(bindingAfter, expected);
try, close_system(model, 0); catch, end
try, close_system("aeroblk_lib_HL20", 0); catch, end
evidence.model_closed_without_save = true;
evidence.finished_at = localNow();
evidence.evidence_complete = evidence.EVIDENCE_COMPLETE;
evidence.runtime = struct( ...
    "matlab_release", string(version("-release")), ...
    "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "matlab_prefdir", string(getenv("MATLAB_PREFDIR")), ...
    "appdata", string(getenv("APPDATA")), ...
    "temp", string(getenv("TEMP")), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")), ...
    "mcp_port", string(getenv("SIMUVERITY_MCP_PORT")), ...
    "adapter_execution_rule", ...
        "nonfailfast_preflight_then_smoke_then_atomic_scenarios");
localAtomicWriteJson(evidencePath, evidence);
validCount = 0;
if isstruct(evidence.scenarios) && ~isempty(evidence.scenarios)
    validCount = sum([evidence.scenarios.valid]);
end
fprintf("F90_XAERO06_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d complete=%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, ...
    numel(evidence.scenarios), evidence.EVIDENCE_COMPLETE, evidencePath);
result = evidence;
end

function bindings = localSourceBindings(modelPath, libraryPath, initPath, gainPath, glidePath)
bindings = struct( ...
    "model", localFilePresence(modelPath), ...
    "library", localFilePresence(libraryPath), ...
    "init", localFilePresence(initPath), ...
    "gains", localFilePresence(gainPath), ...
    "glide", localFilePresence(glidePath));
end

function passed = localBindingsEqual(observed, expected)
names = fieldnames(expected);
passed = true;
for index = 1:numel(names)
    passed = passed && lower(string(observed.(names{index}))) == ...
        lower(string(expected.(names{index})));
end
end

function localAtomicSaveRaw(path, signals, applied)
temporary = string(path) + ".tmp.mat";
save(temporary, "signals", "applied", "-v7.3");
movefile(temporary, path, "f");
end

function localAtomicWriteJson(path, value)
temporary = string(path) + ".tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XAERO06:JsonWrite", ...
    "Cannot open %s.", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleanup;
movefile(temporary, path, "f");
end

function output = localIssue(stage, id, message)
output = struct("stage", string(stage), "id", string(id), ...
    "message", string(message));
end

function localConfigureIsolation()
cache = string(getenv("SIMULINK_CACHE_FOLDER"));
codegen = string(getenv("SIMULINK_CODEGEN_FOLDER"));
if strlength(cache) > 0 && strlength(codegen) > 0
    if ~isfolder(cache), mkdir(cache); end
    if ~isfolder(codegen), mkdir(codegen); end
    Simulink.fileGenControl("set", "CacheFolder", cache, ...
        "CodeGenFolder", codegen, "createDir", true);
end
end

function localEnsureCompilerEnvironment()
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
end
end

function localRemovePaths(sharedDir, sourceDir)
try, rmpath(sharedDir); catch, end
try, rmpath(sourceDir); catch, end
end

function root = localProjectRoot()
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

function value = localNow()
value = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function value = localExtendedError(exception)
value = string(exception.identifier) + ": " + ...
    string(getReport(exception, "extended", "hyperlinks", "off"));
end
