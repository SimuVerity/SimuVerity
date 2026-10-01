function result = f90_xaero08_extract_reference_evidence(modelPath, outputRoot, officialScenarios, evaluatorAssetRoot)
% Extract fixed multi-scenario evidence for F90-XAERO-08. Scoring is offline.

modelPath = string(modelPath);
outputRoot = string(outputRoot);
sourceRoot = fullfile(string(evaluatorAssetRoot), "source", "simulink_stuff");
assert(isfolder(sourceRoot), "SimuVerity:F90:XAERO08:MissingAssetRoot", ...
    "Evaluator-owned reference asset root is incomplete: %s", sourceRoot);
sourceModel = fullfile(sourceRoot, "Rocket.slx");
initializer = fullfile(sourceRoot, "Parameters.m");
expectedModelBinding = "present";
expectedInitializerBinding = "present";
assert(isfile(sourceModel) && strcmpi(localFilePresence(sourceModel), expectedModelBinding), ...
    "SimuVerity:F90:XAERO08:ReferenceAssetIdentity", ...
    "Evaluator-owned Rocket.slx is missing or binding-mismatched.");
assert(strcmpi(localFilePresence(modelPath), expectedModelBinding) && ...
    strcmpi(localFilePresence(modelPath), localFilePresence(sourceModel)), ...
    "SimuVerity:F90:XAERO08:ReferenceAliasIdentity", ...
    "The staged reference alias differs from the asset-root entrypoint.");
scenarioContract = localOfficialScenarios(officialScenarios);
scenarios = scenarioContract.scenarios;
simulation = scenarioContract.contract.simulation;
scoringRunId = strtrim(string(getenv("SIMUVERITY_SCORING_RUN_ID")));
assert(strlength(scoringRunId) > 0, "SimuVerity:F90:XAERO08:ScoringRunIdRequired", ...
    "Reference extraction requires a fresh SimuVerity ScoringRunId.");
assert(~isfolder(outputRoot), "SimuVerity:F90:XAERO08:OutputExists", ...
    "Fresh evidence output already exists: %s", outputRoot);
mkdir(outputRoot);
diary(fullfile(outputRoot, "extractor.log"));
cleanupDiary = onCleanup(@() diary("off")); %#ok<NASGU>
evidencePath = fullfile(outputRoot, "evidence.json");

modelPath = string(sourceModel);
sourcePresenceBefore = localFilePresence(modelPath);
isReference = true;
evidence = struct("schema", "simuverity.f90-xaero08-evidence.v1", ...
    "task_id", "F90-XAERO-08", "scoring_run_id", scoringRunId, ...
    "evaluation_subject", "reference", "model_file_presence_before", sourcePresenceBefore, ...
    "reference_direct_golden", isReference, ...
    "runtime_changes", "Normal mode, fixed official inputs, non-truncating logs, isolated cache/codegen, evaluator-only in-memory measurement taps, and phase-grid resampling", ...
    "load_pass", false, "update_pass", false, "compile_pass", false, ...
    "simulate_pass", false, "all_scenarios_valid", false, ...
    "static_audit", struct(), "behavior_audit", struct(), ...
    "scenario_count", numel(scenarios), "scenarios", struct([]), ...
    "evidence_complete", false, "contains_score_decisions", false, "failure", "");
localWriteJson(evidencePath, evidence);

[modelDir, model, ~] = fileparts(modelPath);
oldPath = path; oldDir = pwd;
sessionCleanup = onCleanup(@() localRestore(oldPath, oldDir)); %#ok<NASGU>
    restoredefaultpath;
addpath(modelDir, "-begin");
scratchRoot = string(tempname);
assert(~isfolder(scratchRoot), "SimuVerity:F90:XAERO08:ScratchExists", ...
    "Fresh evaluator scratch path already exists: %s", scratchRoot);
mkdir(scratchRoot);
scratchCleanup = onCleanup(@() localRemoveTree(scratchRoot)); %#ok<NASGU>
cacheRoot = fullfile(scratchRoot, "cache"); codegenRoot = fullfile(scratchRoot, "codegen");
mkdir(cacheRoot); mkdir(codegenRoot);
Simulink.fileGenControl("set", "CacheFolder", cacheRoot, "CodeGenFolder", codegenRoot, "createDir", true);

try
    if isReference
        assert(strcmpi(localFilePresence(initializer), expectedInitializerBinding), ...
            "SimuVerity:F90:XAERO08:InitializerIdentity", "Pinned initializer file binding differs.");
        evalin("base", "run('" + replace(initializer, "'", "''") + "')");
    end
    load_system(modelPath);
    cleanupModel = onCleanup(@() localClose(model)); %#ok<NASGU>
    evidence.load_pass = true;
    set_param(model, "SimulationMode", "normal", "ReturnWorkspaceOutputs", "on", "LimitDataPoints", "off");
    toWs = find_system(model, "LookUnderMasks", "all", "BlockType", "ToWorkspace");
    for index = 1:numel(toWs), set_param(toWs{index}, "MaxDataPoints", "inf"); end
    if isReference, localAddReferenceTaps(model); end
    set_param(model, "SimulationCommand", "update"); evidence.update_pass = true;
    feval(model, [], [], [], "compile"); feval(model, [], [], [], "term"); evidence.compile_pass = true;
    evidence.static_audit = localStaticAudit(model, isReference);
    localWriteJson(evidencePath, evidence);

    rows = cell(1, numel(scenarios)); suiteTimer = tic;
    for index = 1:numel(scenarios)
        scenario = scenarios(index); scenarioTimer = tic;
        out = localRunScenario(model, scenario, isReference, simulation.maximum_duration_seconds);
        if isReference
            signals = localReadReference(out, scenario, simulation.evidence_phase_points);
        else
            signals = localReadCandidate(out, scenario, simulation.evidence_phase_points, ...
                simulation.maximum_duration_seconds);
        end
        contract = localOutputContract(signals, simulation.maximum_duration_seconds);
        assert(all(structfun(@logical, contract)), "SimuVerity:F90:XAERO08:OutputContract", ...
            "Scenario %s violates the public output contract.", scenario.id);
        row = struct("id", string(scenario.id), "inputs", rmfield(scenario, "id"), ...
            "time_s", signals.time_s, "phase", signals.phase, ...
            "actual_terminal_time_s", signals.actual_terminal_time_s, ...
            "flight_state", signals.flight_state, "propulsion_state", signals.propulsion_state, ...
            "guidance_attitude_state", signals.guidance_attitude_state, ...
            "output_contract", contract, "metrics", localScenarioMetrics(signals), ...
            "wall_seconds", toc(scenarioTimer), "valid", true);
        rows{index} = row;
    end
    rows = [rows{:}]; evidence.scenarios = rows; evidence.suite_wall_seconds = toc(suiteTimer);
    evidence.simulate_pass = true; evidence.all_scenarios_valid = all([rows.valid]);
    evidence.behavior_audit = localBehaviorAudit(rows);
    assert(evidence.behavior_audit.all_three_axes_effective, "SimuVerity:F90:XAERO08:InterventionAxes", ...
        "One or more required intervention axes are ineffective.");
    evidence.model_file_presence_after = localFilePresence(modelPath);
    evidence.model_binding_preserved = evidence.model_file_presence_after == evidence.model_file_presence_before;
    assert(evidence.model_binding_preserved, "SimuVerity:F90:XAERO08:ModelModified", "Evaluated model file changed.");
    evidence.evidence_complete = true; localWriteJson(evidencePath, evidence);
    completeEvidence = evidence; %#ok<NASGU>
    save(fullfile(outputRoot, "evidence_complete.mat"), "completeEvidence", "-v7");
    result = evidence;
catch ME
    evidence.failure = string(getReport(ME, "extended", "hyperlinks", "off"));
    if isfile(modelPath)
        evidence.model_file_presence_after = localFilePresence(modelPath);
        evidence.model_binding_preserved = evidence.model_file_presence_after == evidence.model_file_presence_before;
    end
    evidence.evidence_complete = false; localWriteJson(evidencePath, evidence);
    localWriteJson(fullfile(outputRoot, "failure_receipt.json"), evidence); rethrow(ME);
end
end

function out = localRunScenario(model, scenario, isReference, maximumDuration)
in = Simulink.SimulationInput(model);
in = in.setModelParameter("StopTime", num2str(maximumDuration, 17), "SimulationMode", "normal", ...
    "ReturnWorkspaceOutputs", "on", "SignalLogging", "on", "LimitDataPoints", "off");
if isReference
    dryMass = evalin("base", "m_dry");
    in = in.setVariable("m_dot", double(scenario.mass_flow_kg_per_s));
    in = in.setVariable("m_payload", double(scenario.payload_mass_kg));
    in = in.setVariable("m_zfw", double(scenario.payload_mass_kg) + dryMass);
    in = in.setVariable("gam_in", double(scenario.gravity_turn_angle_rad));
else
    in = in.setVariable("mass_flow_kg_per_s", double(scenario.mass_flow_kg_per_s));
    in = in.setVariable("payload_mass_kg", double(scenario.payload_mass_kg));
    in = in.setVariable("gravity_turn_angle_rad", double(scenario.gravity_turn_angle_rad));
end
capture = evalc("out = sim(in);"); %#ok<NASGU>
end

function localAddReferenceTaps(model)
taps = { ...
    "dH/dT", 1, "xa08_altitude"; "dX/dT", 1, "xa08_downrange"; ...
    "dV/dT", 1, "xa08_speed"; "d(gam)/dT", 1, "xa08_gamma"; ...
    "dot", 1, "xa08_pitch"; "ddot", 1, "xa08_pitch_rate"; ...
    "Thrust", 1, "xa08_thrust"; "Thrust", 2, "xa08_fuel_initial"; ...
    "Thrust", 3, "xa08_ascent_consumed"; "Thrust", 4, "xa08_terminal_consumed"; ...
    "Pitch", 1, "xa08_pitch_command"};
for index = 1:size(taps,1)
    sink = model + "/__eval_" + string(index);
    add_block("simulink/Sinks/To Workspace", sink, "VariableName", taps{index,3}, ...
        "SaveFormat", "Timeseries", "MaxDataPoints", "inf", "Position", [1650 20+35*index 1740 45+35*index]);
    sourcePath = model + "/" + replace(string(taps{index,1}), "/", "//");
    sourcePorts = get_param(sourcePath, "PortHandles");
    sinkPorts = get_param(sink, "PortHandles");
    add_line(model, sourcePorts.Outport(double(taps{index,2})), sinkPorts.Inport(1), "autorouting", "on");
end
end

function signals = localReadReference(out, scenario, phasePoints)
names = ["xa08_altitude","xa08_downrange","xa08_speed","xa08_gamma","xa08_pitch", ...
    "xa08_thrust","xa08_fuel_initial","xa08_ascent_consumed","xa08_terminal_consumed", ...
    "xa08_pitch_command","xa08_pitch_rate"];
raw = cell(1,numel(names)); terminal = zeros(1,numel(names));
for index=1:numel(names), [raw{index}.t,raw{index}.d] = localRawSeries(out,names(index),1); terminal(index)=raw{index}.t(end); end
actualEnd = min(terminal); phase = linspace(0,1,double(phasePoints)).'; grid = phase * actualEnd;
for index=1:numel(raw), values{index}=localInterpolate(raw{index}.t,raw{index}.d,grid); end %#ok<AGROW>
command = repmat(double(scenario.gravity_turn_angle_rad),numel(grid),1);
signals = struct("time_s",grid,"phase",phase,"actual_terminal_time_s",actualEnd, ...
    "flight_state",[values{1} values{2} values{3} values{4} values{5}], ...
    "propulsion_state",[values{6} values{7} values{8} values{9}], ...
    "guidance_attitude_state",[command values{10} values{5} values{11}]);
end

function signals = localReadCandidate(out, scenario, phasePoints, maximumDuration)
[tf,flight]=localRawSeries(out,"flight_state",5); [tp,propulsion]=localRawSeries(out,"propulsion_state",4);
[tg,guidance]=localRawSeries(out,"guidance_attitude_state",4);
assert(numel(tf)>=50 && numel(tp)>=50 && numel(tg)>=50,"SimuVerity:F90:XAERO08:SampleCount","Required outputs need at least 50 samples.");
ends=[tf(end),tp(end),tg(end)]; assert(max(ends)-min(ends)<=max(0.1,0.001*max(ends)), ...
    "SimuVerity:F90:XAERO08:TerminalAlignment","Required outputs do not share a terminal time.");
actualEnd=tf(end); assert(actualEnd>1 && actualEnd<=maximumDuration+1e-6,"SimuVerity:F90:XAERO08:TerminalTime","Invalid terminal time.");
phase=linspace(0,1,double(phasePoints)).'; grid=phase*actualEnd;
flight=localInterpolate(tf,flight,grid); propulsion=localInterpolate(tp,propulsion,grid); guidance=localInterpolate(tg,guidance,grid);
assert(max(abs(guidance(:,1)-double(scenario.gravity_turn_angle_rad)))<=1e-6, ...
    "SimuVerity:F90:XAERO08:CommandLog","Logged gravity-turn command does not match the official input.");
signals=struct("time_s",grid,"phase",phase,"actual_terminal_time_s",actualEnd, ...
    "flight_state",flight,"propulsion_state",propulsion,"guidance_attitude_state",guidance);
end

function [t,data] = localRawSeries(out,name,width)
try, value=out.get(name); catch, error("SimuVerity:F90:XAERO08:MissingOutput","Required output %s is absent.",name); end
if isa(value,"timeseries")
    t=double(value.Time(:)); data=squeeze(double(value.Data));
elseif isstruct(value)&&isfield(value,"time")&&isfield(value,"signals")
    t=double(value.time(:)); data=squeeze(double(value.signals.values));
else, error("SimuVerity:F90:XAERO08:OutputType","Output %s is not a supported Timeseries.",name); end
if isvector(data),data=data(:);end
if size(data,1)~=numel(t)&&size(data,2)==numel(t),data=data.';end
assert(size(data,1)==numel(t)&&size(data,2)==width,"SimuVerity:F90:XAERO08:OutputShape","Output %s has invalid width.",name);
assert(all(isfinite(t))&&all(isfinite(data(:))),"SimuVerity:F90:XAERO08:NonfiniteOutput","Output %s contains NaN or Inf.",name);
[t,keep]=unique(t,"stable"); data=data(keep,:);
assert(numel(t)>=20&&all(diff(t)>0)&&t(1)<=0.01,"SimuVerity:F90:XAERO08:OutputCoverage","Output %s has invalid time coverage.",name);
end

function dataGrid=localInterpolate(t,data,grid)
dataGrid=interp1(t,data,grid,"linear","extrap");
assert(all(isfinite(dataGrid(:))),"SimuVerity:F90:XAERO08:Resample","Nonfinite evidence after resampling.");
end

function contract=localOutputContract(s,maximumDuration)
contract=struct("time_strictly_increasing",all(diff(s.time_s)>0),"starts_at_zero",abs(s.time_s(1))<=1e-9, ...
    "valid_terminal_time",s.actual_terminal_time_s>1&&s.actual_terminal_time_s<=maximumDuration+1e-6, ...
    "phase_points_501",numel(s.phase)==501,"flight_width_5",size(s.flight_state,2)==5, ...
    "propulsion_width_4",size(s.propulsion_state,2)==4,"guidance_width_4",size(s.guidance_attitude_state,2)==4, ...
    "finite_flight",all(isfinite(s.flight_state(:))),"finite_propulsion",all(isfinite(s.propulsion_state(:))), ...
    "finite_guidance",all(isfinite(s.guidance_attitude_state(:))));
end

function metrics=localScenarioMetrics(s)
metrics=struct("terminal_time_s",s.actual_terminal_time_s,"flight_final",s.flight_state(end,:), ...
    "flight_minimum",min(s.flight_state,[],1),"flight_maximum",max(s.flight_state,[],1), ...
    "flight_rms",sqrt(mean(s.flight_state.^2,1)),"propulsion_minimum",min(s.propulsion_state,[],1), ...
    "propulsion_maximum",max(s.propulsion_state,[],1),"propulsion_final",s.propulsion_state(end,:), ...
    "guidance_minimum",min(s.guidance_attitude_state,[],1),"guidance_maximum",max(s.guidance_attitude_state,[],1), ...
    "guidance_final",s.guidance_attitude_state(end,:));
end

function audit=localBehaviorAudit(rows)
features=zeros(numel(rows),16);
for index=1:numel(rows),m=rows(index).metrics;features(index,:)=[m.terminal_time_s,m.flight_final,m.flight_maximum(1:3),m.flight_minimum(1:3),m.propulsion_final(1:2),m.guidance_final(2:3)];end
scale=max(abs(features(1,:)),1e-6); delta=zeros(1,numel(rows));
for index=2:numel(rows),delta(index)=norm((features(index,:)-features(1,:))./scale)/sqrt(size(features,2));end
audit=struct("normalized_feature_delta",delta,"mass_flow_axis_effective",all(delta(2:3)>1e-4), ...
    "payload_axis_effective",delta(4)>1e-4,"gravity_turn_axis_effective",delta(5)>1e-4);
audit.all_three_axes_effective=audit.mass_flow_axis_effective&&audit.payload_axis_effective&&audit.gravity_turn_axis_effective;
end

function audit=localStaticAudit(model,isReference)
blocks=find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");
audit=struct("block_count",numel(blocks),"reference_fixed_source",isReference,"measurement_taps_in_memory_only",isReference);
end

function localWriteJson(p,v)
fid=fopen(p,"w","n","UTF-8");assert(fid>=0,"SimuVerity:F90:XAERO08:Write","Cannot write %s.",p);c=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(v,"PrettyPrint",true));
end
function contract=localOfficialScenarios(value)
if isstruct(value)
    contract=value;
else
    scenarioPath=string(value);
    assert(isfile(scenarioPath),"SimuVerity:F90:XAERO08:OfficialScenariosMissing", ...
        "Official scenarios are absent: %s",scenarioPath);
    contract=jsondecode(fileread(scenarioPath));
end
assert(string(contract.task_id)=="F90-XAERO-08"&& ...
    isfield(contract,"scenarios")&&numel(contract.scenarios)==5&& ...
    isfield(contract,"contract")&&isfield(contract.contract,"simulation"), ...
    "SimuVerity:F90:XAERO08:OfficialScenarioContract", ...
    "The public official scenario contract is invalid.");
required=["id","mass_flow_kg_per_s","payload_mass_kg","gravity_turn_angle_rad"];
assert(all(isfield(contract.scenarios,required)), ...
    "SimuVerity:F90:XAERO08:OfficialScenarioFields", ...
    "An official scenario is missing a required input field.");
simulation=contract.contract.simulation;
assert(double(simulation.maximum_duration_seconds)==350&& ...
    double(simulation.evidence_phase_points)==501, ...
    "SimuVerity:F90:XAERO08:OfficialSimulationContract", ...
    "The public simulation evidence contract is invalid.");
end
function d = localFilePresence(p)
assert(isfile(p), "SimuVerity:FileMissing", "Required file is missing: %s", p);
d = "present";
end

function localClose(model),try,if bdIsLoaded(model),close_system(model,0);end,catch,end,end
function localRestore(oldPath,oldDir),try,path(oldPath);catch,end,try,cd(oldDir);catch,end,end
function localRemoveTree(pathValue),if isfolder(pathValue),rmdir(pathValue,"s");end,end
