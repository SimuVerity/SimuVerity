function result = f90_xtherm11_extract_reference_evidence(modelPath, outputDir, evaluationMode)
% Extract complete fixed evidence for F90-XTHERM-11. Scoring is offline only.

repo = localProjectRoot();
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
official = jsondecode(fileread(simuverity_official_scenarios_path()));
expectedSourceBinding = "present";
assert(nargin >= 1 && strlength(string(modelPath)) > 0, ...
    "SimuVerity:F90:XTHERM11:ModelRequired", "Public extraction requires an explicit model path.");
sourceModel = string(modelPath);
if nargin < 3 || strlength(string(evaluationMode)) == 0, evaluationMode = "reference"; end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xtherm11_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(tempdir, "SimuVerity", "F90-XTHERM-11", generationRunId);
end
if ~isfolder(outputDir), mkdir(outputDir); end
evidencePath = fullfile(outputDir, "evidence.json");
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";

evidence = struct( ...
    "schema", "simuverity.f90-xtherm11-evidence.v1", ...
    "task_id", "F90-XTHERM-11", ...
    "generation_run_id", generationRunId, ...
    "evaluation_subject", string(evaluationMode), ...
    "model_path", string(modelPath), ...
    "source_file_presence_before", localFilePresence(modelPath), ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "runtime_changes", ...
        "Normal mode, fixed random seeds, public scenario parameters and non-truncating evidence logs only", ...
    "load_pass", false, "update_pass", false, "compile_pass", false, ...
    "nominal_smoke_pass", false, "static_audit", struct(), ...
    "behavior_audit", struct(), "scenarios", struct([]), ...
    "EVIDENCE_COMPLETE", false, "contains_score_decisions", false, ...
    "errors", {{}}, "started_at", localNow());
localWriteJson(evidencePath, evidence);

[modelDir, model, ~] = fileparts(modelPath);
addpath(modelDir, "-begin");
pathCleanup = onCleanup(@() localRemovePath(modelDir)); %#ok<NASGU>
localConfigureRuntime(outputDir);

try
    if isReference
        assert(strcmpi(localFilePresence(modelPath), expectedSourceBinding), ...
            "SimuVerity:F90:XTHERM11:ReferenceIdentity", "Pinned reference model file presence differs.");
    end
    load_system(modelPath);
    evidence.load_pass = true;
    set_param(model, "SimulationMode", "normal", ...
        "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
    toWs = find_system(model, "LookUnderMasks", "all", "BlockType", "ToWorkspace");
    for index = 1:numel(toWs), set_param(toWs{index}, "MaxDataPoints", "inf"); end
    localAssignInputs(official.scenarios(1));
    if isReference, localConfigureReference(model, official.scenarios(1)); end
    set_param(model, "SimulationCommand", "update");
    evidence.update_pass = true;
    set_param(model, "SimulationCommand", "start");
    set_param(model, "SimulationCommand", "stop");
    evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model, isReference);
    localWriteJson(evidencePath, evidence);

    smokeOut = localRunScenario(model, official.scenarios(1), isReference, 30);
    smokeSignals = localReadSignals(smokeOut, isReference, official.scenarios(1));
    smokeContract = localOutputContract(smokeSignals, 30);
    evidence.nominal_smoke_contract = smokeContract;
    evidence.nominal_smoke_pass = all(structfun(@logical, smokeContract));
    localWriteJson(evidencePath, evidence);
    assert(evidence.nominal_smoke_pass, "SimuVerity:F90:XTHERM11:NominalSmoke", ...
        "Nominal smoke output contract failed.");

    scenarioDir = fullfile(outputDir, "scenarios");
    if ~isfolder(scenarioDir), mkdir(scenarioDir); end
    rows = repmat(localEmptyScenario(), numel(official.scenarios), 1);
    for index = 1:numel(official.scenarios)
        scenario = official.scenarios(index);
        row = localEmptyScenario();
        row.id = string(scenario.id);
        row.inputs = rmfield(scenario, "id");
        started = tic;
        try
            out = localRunScenario(model, scenario, isReference, ...
                double(official.simulation.duration_seconds));
            signals = localReadSignals(out, isReference, scenario);
            row.output_contract = localOutputContract(signals, ...
                double(official.simulation.duration_seconds));
            row.metrics = localMetrics(signals, scenario, official.simulation);
            signalPath = fullfile(scenarioDir, "signals_" + string(scenario.id) + ".mat");
            save(signalPath, "signals", "-v7");
            row.complete_signal_artifact = localRelativePath(repo, signalPath);
            row.complete_signal_file_presence = localFilePresence(signalPath);
            row.simulation_pass = true;
            row.valid = all(structfun(@logical, row.output_contract));
            if ~row.valid
                row.error = localIssue("output_contract", row.id, ...
                    "Required complete-run evidence is invalid.");
            end
        catch exception
            row.error = localIssue("scenario", row.id, ...
                string(exception.identifier) + ": " + string(exception.message));
        end
        row.wall_seconds = toc(started);
        rows(index) = row;
        evidence.scenarios = rows(1:index);
        localWriteJson(fullfile(scenarioDir, "scenario_" + ...
            string(scenario.id) + ".json"), row);
        localWriteJson(evidencePath, evidence);
    end
    evidence.scenarios = rows;
    evidence.behavior_audit = localBehaviorAudit(rows);
    evidence.source_file_presence_after = localFilePresence(modelPath);
    evidence.reference_binding_preserved = ~isReference || ...
        strcmpi(evidence.source_file_presence_after, expectedSourceBinding);
    evidence.EVIDENCE_COMPLETE = evidence.load_pass && evidence.update_pass && ...
        evidence.compile_pass && evidence.nominal_smoke_pass && ...
        all([rows.valid]) && evidence.reference_binding_preserved && ...
        evidence.static_audit.core_path_qualified && ...
        evidence.behavior_audit.core_behavior_qualified;
    if evidence.EVIDENCE_COMPLETE, evidence.evidence_complete_at = localNow(); end
catch exception
    evidence.errors{end+1} = localIssue("session", "fatal", ...
        string(exception.identifier) + ": " + string(exception.message));
end

try
    if bdIsLoaded(model), close_system(model, 0); end
catch exception
    evidence.errors{end+1} = localIssue("close", "model", exception.message);
end
evidence.model_closed_without_save = ~bdIsLoaded(model);
evidence.finished_at = localNow();
evidence.source_file_presence_after = localFilePresence(modelPath);
if isReference
    evidence.reference_binding_preserved = strcmpi(evidence.source_file_presence_after, expectedSourceBinding);
    if ~evidence.reference_binding_preserved, evidence.EVIDENCE_COMPLETE = false; end
end
evidence.runtime = struct("matlab_release", string(version("-release")), ...
    "normal_mode", true, "generation_run_id", generationRunId, "matlab_prefdir", string(prefdir), ...
    "cache", string(getenv("SIMULINK_CACHE_FOLDER")), ...
    "codegen", string(getenv("SIMULINK_CODEGEN_FOLDER")));
localWriteJson(evidencePath, evidence);
result = evidence;
validCount = 0;
if ~isempty(evidence.scenarios), validCount = sum([evidence.scenarios.valid]); end
fprintf("F90_XTHERM11_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d complete=%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, numel(evidence.scenarios), ...
    evidence.EVIDENCE_COMPLETE, evidencePath);
end

function out = localRunScenario(model, scenario, isReference, duration)
localAssignInputs(scenario);
if isReference, localConfigureReference(model, scenario); end
in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", num2str(duration, 17), ...
    "SimulationMode", "normal", "ReturnWorkspaceOutputs", "on", ...
    "OutputOption", "RefineOutputTimes", "Refine", "1");
names = fieldnames(rmfield(scenario, "id"));
for index = 1:numel(names), in = in.setVariable(names{index}, scenario.(names{index})); end
out = sim(in);
end

function localAssignInputs(scenario)
names = fieldnames(rmfield(scenario, "id"));
for index = 1:numel(names), assignin("base", names{index}, scenario.(names{index})); end
end

function localConfigureReference(model, scenario)
set_param(model + "/Noise & Disturbance Layer/Control Layer/T (sp)", ...
    "Value", num2str(scenario.reactor_temperature_setpoint_K, 17));
set_param(model + "/Noise & Disturbance Layer/Control Layer/h (sp)", ...
    "Value", num2str(scenario.liquid_level_setpoint_m, 17));
process = model + "/Noise & Disturbance Layer/Control Layer/Process Layer/";
set_param(process + "Fi (0)", "Value", num2str(scenario.feed_flow_kg_s, 17));
set_param(process + "F (0)", "Value", num2str(scenario.feed_flow_kg_s, 17));
set_param(model + "/Noise & Disturbance Layer/Control Layer/F (0)", ...
    "Value", num2str(scenario.feed_flow_kg_s, 17));
set_param(process + "Ci (0)", "Value", num2str(scenario.feed_concentration_kmol_m3, 17));
set_param(process + "Ti (0)", "Value", num2str(scenario.feed_temperature_K, 17));
set_param(process + "Tci (0)", "Value", num2str(scenario.coolant_inlet_temperature_K, 17));

ramps = {"Ramp10","Fi (+)",scenario.feed_flow_ramp_kg_s2; ...
    "Ramp11","Ci (-)",scenario.feed_concentration_ramp_kmol_m3_s; ...
    "Ramp12","Ti (+)",scenario.feed_temperature_ramp_K_s; ...
    "Ramp13","Tci (+)",scenario.coolant_inlet_temperature_ramp_K_s};
for index = 1:size(ramps,1)
    slope = double(ramps{index,3});
    set_param(model + "/" + ramps{index,1}, "slope", num2str(slope,17), ...
        "start", num2str(scenario.disturbance_start_s,17), "InitialOutput", "0");
    set_param(model + "/" + ramps{index,2}, "sw", num2str(double(abs(slope) > 0)));
end
set_param(model + "/Delay = 200", "DelayTime", num2str(scenario.disturbance_start_s,17));
set_param(model + "/-0.002 ", "Gain", num2str(-scenario.catalyst_decay_rate_s_inverse,17));
set_param(model + "/-0.005", "Gain", num2str(-scenario.heat_transfer_decay_rate_s_inverse,17));
set_param(model + "/a (-)", "sw", num2str(double(scenario.catalyst_decay_rate_s_inverse > 0)));
set_param(model + "/b (-)", "sw", num2str(double(scenario.heat_transfer_decay_rate_s_inverse > 0)));
randoms = find_system(model,"LookUnderMasks","all","FollowLinks","on","BlockType","RandomNumber");
for index = 1:numel(randoms), set_param(randoms{index},"Seed",num2str(1300+97*index)); end
end

function signals = localReadSignals(out, isReference, scenario)
if isReference
    Y = localGetOutput(out, "Y");
    assert(isstruct(Y) && isfield(Y,"signals") && numel(Y.signals) >= 12, ...
        "SimuVerity:F90:XTHERM11:ReferenceY", "Reference Y log is incomplete.");
    t = double(Y.time(:)); y = zeros(numel(t),12);
    for index = 1:12, y(:,index) = reshape(double(Y.signals(index).values),[],1); end
    reactor = [y(:,1),y(:,2),y(:,3),y(:,4)];
    flow = [y(:,5),y(:,6),y(:,10),y(:,7),y(:,8),y(:,9)];
    control = [repmat(double(scenario.reactor_temperature_setpoint_K),numel(t),1), ...
        repmat(double(scenario.liquid_level_setpoint_m),numel(t),1), ...
        double(scenario.reactor_temperature_setpoint_K)-y(:,3), ...
        double(scenario.liquid_level_setpoint_m)-y(:,1),y(:,11),y(:,12)];
    signals = struct("reactor_state",localSeries(t,reactor), ...
        "flow_state",localSeries(t,flow), "control_state",localSeries(t,control));
else
    signals = struct("reactor_state",localTimeseries(localGetOutput(out,"reactor_state"),4), ...
        "flow_state",localTimeseries(localGetOutput(out,"flow_state"),6), ...
        "control_state",localTimeseries(localGetOutput(out,"control_state"),6));
end
end

function value = localGetOutput(out, name)
names = out.who;
if any(strcmp(names,name)), value = out.get(name); return; end
if evalin("base", "exist('" + name + "','var')")
    value = evalin("base", name); return
end
error("SimuVerity:F90:XTHERM11:MissingOutput", "Required output %s is missing.", name);
end

function series = localTimeseries(value, width)
assert(isa(value,"timeseries"), "SimuVerity:F90:XTHERM11:SeriesType", ...
    "Required output must be a Timeseries, not %s.", class(value));
time = double(value.Time(:)); data = squeeze(double(value.Data));
if isvector(data) && width == 1, data = data(:); end
if size(data,1) ~= numel(time) && size(data,2) == numel(time), data = data.'; end
assert(size(data,1) == numel(time) && size(data,2) == width, ...
    "SimuVerity:F90:XTHERM11:SeriesWidth", "Expected %d channels.", width);
series = localSeries(time,data);
end

function series = localSeries(time,data)
series = struct("time",double(time(:)),"data",double(data));
end

function contract = localOutputContract(signals, duration)
names = fieldnames(signals); expected = [4,6,6]; contract = struct;
for index = 1:numel(names)
    s = signals.(names{index});
    contract.(names{index}) = numel(s.time) >= 10 && ...
        size(s.data,1) == numel(s.time) && size(s.data,2) == expected(index) && ...
        all(isfinite(s.time)) && all(isfinite(s.data(:))) && ...
        all(diff(s.time) > 0) && s.time(1) <= 0.1 && s.time(end) >= duration-0.1;
end
t0 = signals.reactor_state.time;
contract.shared_time_axis = isequal(t0,signals.flow_state.time) && ...
    isequal(t0,signals.control_state.time);
end

function metrics = localMetrics(signals, scenario, simulation)
t = signals.reactor_state.time; r = signals.reactor_state.data;
f = signals.flow_state.data; c = signals.control_state.data;
tail = t >= double(simulation.tail_start_seconds);
post = t >= double(scenario.disturbance_start_s);
pre = t >= max(0,double(scenario.disturbance_start_s)-100) & ...
    t <= max(0,double(scenario.disturbance_start_s)-10);
temperatureError = r(:,3)-double(scenario.reactor_temperature_setpoint_K);
levelError = r(:,1)-double(scenario.liquid_level_setpoint_m);
expectedA = ones(size(t)); expectedB = ones(size(t));
elapsed = max(t-double(scenario.disturbance_start_s),0);
expectedA(post) = exp(-double(scenario.catalyst_decay_rate_s_inverse)*elapsed(post));
expectedB(post) = exp(-double(scenario.heat_transfer_decay_rate_s_inverse)*elapsed(post));
metrics = struct;
metrics.temperature_tail_mean_K = mean(r(tail,3));
metrics.temperature_tail_rmse_K = sqrt(mean(temperatureError(tail).^2));
metrics.temperature_tail_max_abs_error_K = max(abs(temperatureError(tail)));
metrics.temperature_peak_abs_error_K = max(abs(temperatureError(post)));
metrics.level_tail_mean_m = mean(r(tail,1));
metrics.level_tail_rmse_m = sqrt(mean(levelError(tail).^2));
metrics.level_tail_max_abs_error_m = max(abs(levelError(tail)));
metrics.level_peak_abs_error_m = max(abs(levelError(post)));
metrics.concentration_tail_mean_kmol_m3 = mean(r(tail,2));
metrics.concentration_min_kmol_m3 = min(r(:,2));
metrics.concentration_max_kmol_m3 = max(r(:,2));
metrics.jacket_temperature_tail_mean_K = mean(r(tail,4));
metrics.thermal_gradient_rms_K = sqrt(mean((r(:,3)-r(:,4)).^2));
metrics.thermal_state_correlation = localCorrelation(r(:,3),r(:,4));
metrics.feed_flow_tail_mean_kg_s = mean(f(tail,1));
metrics.outlet_flow_tail_mean_kg_s = mean(f(tail,2));
metrics.coolant_flow_tail_mean_kg_s = mean(f(tail,3));
metrics.outlet_flow_range_kg_s = max(f(:,2))-min(f(:,2));
metrics.coolant_flow_range_kg_s = max(f(:,3))-min(f(:,3));
metrics.outlet_flow_change_from_pre_kg_s = abs(mean(f(tail,2))-mean(f(pre,2)));
metrics.coolant_flow_change_from_pre_kg_s = abs(mean(f(tail,3))-mean(f(pre,3)));
metrics.catalyst_activity_tail_mean = mean(c(tail,5));
metrics.heat_transfer_factor_tail_mean = mean(c(tail,6));
metrics.catalyst_factor_max_error = max(abs(c(:,5)-expectedA));
metrics.heat_transfer_factor_max_error = max(abs(c(:,6)-expectedB));
metrics.temperature_error_log_max_mismatch = max(abs(c(:,3)+temperatureError));
metrics.level_error_log_max_mismatch = max(abs(c(:,4)+levelError));
metrics.positive_state_fraction = mean(r(:,1)>0 & r(:,2)>=-0.02 & r(:,3)>250 & r(:,4)>250);
metrics.nonnegative_flow_fraction = mean(all(f(:,1:3)>=-1e-6,2));
metrics.temperature_tail_slope_K_s = localSlope(t(tail),r(tail,3));
metrics.level_tail_slope_m_s = localSlope(t(tail),r(tail,1));
metrics.temperature_pre_rmse_K = sqrt(mean(temperatureError(pre).^2));
metrics.level_pre_rmse_m = sqrt(mean(levelError(pre).^2));
metrics.state_response_vector = [metrics.level_tail_mean_m, ...
    metrics.concentration_tail_mean_kmol_m3,metrics.temperature_tail_mean_K, ...
    metrics.jacket_temperature_tail_mean_K,metrics.outlet_flow_tail_mean_kg_s, ...
    metrics.coolant_flow_tail_mean_kg_s];
metrics.physically_plausible = metrics.positive_state_fraction >= 0.995 && ...
    metrics.nonnegative_flow_fraction >= 0.995 && max(r(:,3)) < 480 && max(r(:,4)) < 470;
metrics.dynamic_dual_actuation = metrics.outlet_flow_range_kg_s > 0.1 && ...
    metrics.coolant_flow_range_kg_s > 0.5;
metrics.control_log_consistent = metrics.temperature_error_log_max_mismatch < 1e-6 && ...
    metrics.level_error_log_max_mismatch < 1e-6;
end

function audit = localStaticAudit(model, isReference)
blocks = find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");
types = string(get_param(blocks,"BlockType")); paths = replace(string(blocks),newline," ");
dynamicCount = sum(ismember(types,["Integrator","DiscreteIntegrator", ...
    "StateSpace","DiscreteStateSpace","TransferFcn","UnitDelay","Memory"]));
sumCount = sum(types=="Sum"); nonlinearCount = sum(ismember(types,["Fcn","Math","Product","Lookup_n-D"]));
if isReference
    processStates = sum(types=="Integrator" & contains(paths,"/Process Layer/"));
    controllerPaths = unique(paths(contains(paths,"PID")));
    faultSwitchCount = sum(types=="ManualSwitch");
    core = processStates>=4 && numel(controllerPaths)>=4 && faultSwitchCount>=6;
else
    processStates = dynamicCount; controllerPaths = strings(0,1);
    faultSwitchCount = 0;
    core = dynamicCount>=4 && sumCount>=2 && nonlinearCount>=2;
end
audit = struct("block_count",numel(blocks),"dynamic_block_count",dynamicCount, ...
    "process_state_count",processStates,"sum_block_count",sumCount, ...
    "nonlinear_block_count",nonlinearCount,"controller_path_count",numel(controllerPaths), ...
    "fault_switch_count",faultSwitchCount,"reference_exact_structure",isReference, ...
    "core_path_qualified",core);
end

function audit = localBehaviorAudit(rows)
if isempty(rows) || ~all([rows.valid])
    audit = struct("input_axes_effective_count",0,"dynamic_dual_actuation",false, ...
        "core_behavior_qualified",false); return
end
metrics = [rows.metrics]; base = metrics(1); scales = [0.05,0.05,3,3,1,2];
responses = zeros(1,numel(metrics)-1);
for index = 2:numel(metrics)
    responses(index-1) = sqrt(mean(((metrics(index).state_response_vector- ...
        base.state_response_vector)./scales).^2));
end
effective = responses > 0.05;
dynamicDual = all([metrics.dynamic_dual_actuation]);
degradationEffective = abs(metrics(end).catalyst_activity_tail_mean-1)>0.05 && ...
    abs(metrics(end).heat_transfer_factor_tail_mean-1)>0.05;
coupled = all([metrics.thermal_state_correlation] > 0.15) && ...
    max(abs([metrics.concentration_tail_mean_kmol_m3]- ...
    base.concentration_tail_mean_kmol_m3)) > 0.02;
audit = struct("scenario_response_norms",responses, ...
    "input_axes_effective",effective,"input_axes_effective_count",sum(effective), ...
    "dynamic_dual_actuation",dynamicDual,"degradation_axis_effective",degradationEffective, ...
    "thermal_and_reaction_coupling_effective",coupled);
audit.core_behavior_qualified = sum(effective)>=4 && dynamicDual && degradationEffective && coupled;
end

function value = localCorrelation(a,b)
if std(a)<1e-12 || std(b)<1e-12, value=0; return; end
x = corrcoef(a,b); value = abs(x(1,2));
end

function value = localSlope(t,y)
if numel(t)<2, value=inf; return; end
p=polyfit(t(:),y(:),1); value=p(1);
end

function row = localEmptyScenario
row = struct("id","","inputs",struct(),"simulation_pass",false,"valid",false, ...
    "output_contract",struct(),"metrics",struct(),"complete_signal_artifact","", ...
    "complete_signal_file_presence","","wall_seconds",0,"error",struct());
end

function issue = localIssue(stage,id,message)
safe = regexprep(char(string(message)), '[^\x20-\x7E]', '?');
issue = struct("stage",string(stage),"id",string(id),"message",string(safe));
end

function localConfigureRuntime(outputDir)
cache=fullfile(outputDir,"runtime","cache"); codegen=fullfile(outputDir,"runtime","codegen");
if ~isfolder(cache),mkdir(cache);end; if ~isfolder(codegen),mkdir(codegen);end
Simulink.fileGenControl("set","CacheFolder",cache,"CodeGenFolder",codegen,"createDir",true);
end

function root = localProjectRoot
root=fileparts(mfilename("fullpath")); for level=1:4,root=fileparts(root);end
end

function value = localRelativePath(repo,path)
value=replace(string(path),string(repo)+filesep,""); value=replace(value,"\","/");
end

function value = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
value = "present";
end

function value = localNow
value=string(datetime("now","TimeZone","Asia/Shanghai","Format","yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function localWriteJson(path,value)
parent=fileparts(path);if ~isfolder(parent),mkdir(parent);end
temporary=string(path)+".tmp."+string(feature("getpid"));
fid=fopen(temporary,"w","n","UTF-8");assert(fid>=0,"SimuVerity:F90:XTHERM11:Write");
cleanup=onCleanup(@()fclose(fid));fprintf(fid,"%s\n",jsonencode(value,PrettyPrint=true));
clear cleanup;movefile(temporary,path,"f");
end

function localRemovePath(path)
try,rmpath(path);catch,end
end
