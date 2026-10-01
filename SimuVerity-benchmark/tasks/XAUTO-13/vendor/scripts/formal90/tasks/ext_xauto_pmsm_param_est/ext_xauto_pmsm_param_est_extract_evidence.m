function evidence = ext_xauto_pmsm_param_est_extract_evidence(modelPath,outDir)
% Simulation/evidence boundary for the hidden-measurement PMSM contract.
%
% Exact reference file binding:
%   - evaluator-official plant variables are injected into the reference source;
%   - native estimates, diagnostics, commands, and measurements are tapped;
%   - a truth-free candidate measurement pack is emitted beside evidence.
%
% Any other file binding (candidate):
%   - an evaluator-owned exact-reference pack is loaded and validated;
%   - only pmsm_measurement_experiment is assigned to the base workspace;
%   - a held-measurement counterfactual tests estimator causality.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

taskId = "EXT-XAUTO-PMSM-PARAM-EST";
referencePresence = "present";
evaluatedPresence = upper(string(localFilePresence(modelPath)));
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";

measurementPack = struct([]);
packAudit = struct("ready",false,"source_scoring_run_id","", ...
    "pack_file_presence","","truth_fields_absent",false);
if isReference
    spec = localOfficialSpec(taskId);
    runCount = numel(spec.scenarios);
else
    % No official spec (and therefore no hidden truth) is loaded while a
    % candidate model or any of its callbacks is resident in MATLAB. This
    % pre-load boundary must be enforced by an evaluator process that the
    % candidate cannot instrument; the pack path remains outside submission.
    [measurementPack,packAudit] = localLoadMeasurementPack();
    runCount = numel(measurementPack.experiments);
end

addpath(fileparts(modelPath));
pathCleanup = onCleanup(@() rmpath(fileparts(modelPath))); %#ok<NASGU>
load_system(modelPath);
[~,model] = fileparts(modelPath);
modelCleanup = onCleanup(@() close_system(model,0)); %#ok<NASGU>
set_param(model,"SimulationMode","normal","SignalLogging","on", ...
    "SignalLoggingName","logsout","ReturnWorkspaceOutputs","on");

if isReference
    localApplyReferenceScenario(spec.scenarios(1));
    localInstallReferenceTaps(model);
else
    localAssignCandidateExperiment(measurementPack.experiments(1));
end
set_param(model,"SimulationCommand","update");
feval(model,[],[],[],"compile");
feval(model,[],[],[],"term");

items = cell(runCount,1);
sanitized = cell(runCount,1);
rawLogs = cell(runCount,1);
rawProbes = cell(runCount,1);
rawExceptions = cell(runCount,1);
for index = 1:runCount
    try
        if isReference
            scenario = spec.scenarios(index);
            localApplyReferenceScenario(scenario);
            simOut = sim(model,"StopTime",num2str(scenario.duration_s,17), ...
                "SimulationMode","normal","ReturnWorkspaceOutputs","on");
            logs = localReferenceLogs(simOut);
            probe = localReferenceCausalityMarker();
            sanitized{index} = localSanitizedExperiment(logs,scenario.duration_s);
        else
            experiment = measurementPack.experiments(index);
            localAssignCandidateExperiment(experiment);
            simOut = sim(model,"StopTime",num2str(experiment.duration_s,17), ...
                "SimulationMode","normal","ReturnWorkspaceOutputs","on");
            logs = localCandidateLogsPartial(simOut,experiment);

            heldExperiment = localHeldMeasurementExperiment(experiment);
            localAssignCandidateExperiment(heldExperiment);
            heldOut = sim(model,"StopTime",num2str(heldExperiment.duration_s,17), ...
                "SimulationMode","normal","ReturnWorkspaceOutputs","on");
            heldLogs = localCandidateLogsPartial(heldOut,heldExperiment);
            probe = localCandidateCausalityProbe(logs,heldLogs);
        end
        if isReference
            items{index} = localScenarioEvidence(scenario,logs,probe);items{index}.simulation_valid=true;items{index}.estimate_available=true;items{index}.diagnostic_available=true;
        else
            rawLogs{index} = logs;
            rawProbes{index} = probe;
        end
    catch exception
        if isReference
            rethrow(exception);
        end
        rawExceptions{index} = exception;
    end
end

if ~isReference
    % Unload every candidate callback before official truth enters memory.
    clear modelCleanup;
    assert(~bdIsLoaded(model),"SimuVerity:EXT:PMSMCandidateUnload", ...
        "Candidate model remained loaded before official scoring data access.");
    evalin("base","clear pmsm_measurement_experiment");
    spec = localOfficialSpec(taskId);
    assert(numel(spec.scenarios)==4,"SimuVerity:EXT:PMSMOfficialCount", ...
        "Expected four evaluator-official scenarios.");
    assert(numel(spec.scenarios)==runCount, ...
        "SimuVerity:EXT:PMSMScenarioCount","Official scenario count does not match the measurement pack.");
    for index=1:runCount
        scenario = spec.scenarios(index);
        assert(abs(double(scenario.duration_s)- ...
            double(measurementPack.experiments(index).duration_s))<=1e-12, ...
            "SimuVerity:EXT:PMSMOfficialDuration", ...
            "Official truth and evaluator-owned measurement pack durations differ.");
        if isempty(rawExceptions{index})
            items{index} = localScenarioEvidence( ...
                scenario,rawLogs{index},rawProbes{index});
            items{index}.simulation_valid=true;items{index}.estimate_available=rawLogs{index}.estimate_available;items{index}.diagnostic_available=rawLogs{index}.diagnostic_available;
            items{index}.valid=items{index}.valid&&rawLogs{index}.estimate_available&&rawLogs{index}.diagnostic_available;
        else
            items{index} = localInvalidScenario( ...
                scenario,rawExceptions{index});
        end
    end
end
items = vertcat(items{:});

generatedPack = false;
generatedManifest = "";
if isReference
    sanitized = vertcat(sanitized{:});
    [generatedPack,generatedManifest,packAudit] = ...
        localWriteMeasurementPack(outDir,sanitized,referencePresence);
end

adapterMode = string(localChoose(isReference, ...
    "reference_native_measurement_taps","candidate_measurement_contract"));
role = string(localChoose(isReference,"reference","candidate"));
causalityBasis = string(localChoose(isReference, ...
    "reference_native_feedback", ...
    "held_measurement_counterfactual"));
inputBoundaryValid = generatedPack || packAudit.ready;
evidence = struct( ...
    "schema","simuverity.ext-xauto-pmsm-param-est-evidence.v1", ...
    "task_id",taskId, ...
    "contract_id","hidden-measurement", ...
    "role",role, ...
    "model_path",modelPath, ...
    "evaluated_model_file_presence",evaluatedPresence, ...
    "generator_reference_file_presence",referencePresence, ...
    "adapter_mode",adapterMode, ...
    "causality_basis",causalityBasis, ...
    "candidate_contract_only",~isReference, ...
    "input_boundary_valid",inputBoundaryValid, ...
    "official_measurement_pack_generated",generatedPack, ...
    "official_measurement_pack_ready",packAudit.ready, ...
    "measurement_pack_manifest",generatedManifest, ...
    "measurement_pack_file_presence",packAudit.pack_file_presence, ...
    "measurement_pack_source_scoring_run_id",packAudit.source_scoring_run_id, ...
    "truth_fields_absent",packAudit.truth_fields_absent, ...
    "load_ok",true,"update_ok",true,"compile_ok",true, ...
    "simulate_ok",all([items.simulation_valid]), ...
    "scenario_count",numel(items),"scenarios",items);
localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
end

function spec = localOfficialSpec(taskId)
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
path = simuverity_official_scenarios_path();
spec = jsondecode(fileread(path));
end

function localApplyReferenceScenario(s)
% These variables are evaluator-official and are never assigned in the
% candidate branch or stored in the candidate measurement pack.
Tsim=1e-6; Tob=1/20e3; Rs=s.plant_Rs_ohm;
Ldd_inc=s.plant_Ldd_H; Ldq_inc=s.plant_Ldq_H; Lqq_inc=s.plant_Lqq_H;
L_inc=[Ldd_inc Ldq_inc;Ldq_inc Lqq_inc]; L_inc_inv=L_inc^-1; J=[0 -1;1 0];
Ld_ap=90e-6; Lq_ap=300e-6; Psi_dm=0.054; L_ap=[Ld_ap 0;0 Lq_ap];
inertia=s.plant_inertia_kgm2; damping=s.plant_damping_Nms;
Id0=s.operating_id_A; Iq0=s.operating_iq_A; we0=s.electrical_speed_radps;
Ud0=Rs*Id0-we0*Lq_ap*Iq0; Uq0=Rs*Iq0+we0*(Ld_ap*Id0+Psi_dm);
Umd=s.injection_d_voltage_V; Umq=s.injection_q_voltage_V;
weh=2*pi*s.injection_frequency_Hz;
Tdd=L_inc_inv(1,1); Tdq=L_inc_inv(1,2); Tqq=L_inc_inv(2,2);
R=diag([1 1]); Q=0.01*diag([0.01 0.01 Rs Tdd Tdq Tqq]);
Qx=Q(1:2,1:2); Qp=Q(3:6,3:6);
K_inertia=1e-5; K_damping=1e1;
initial_percentage=s.reference_initial_estimate_scale;
names=who;
for index=1:numel(names)
    assignin("base",names{index},eval(names{index}));
end
end

function localAssignCandidateExperiment(experiment)
localAssertSanitizedExperiment(experiment);
assignin("base","pmsm_measurement_experiment",experiment);
end

function localInstallReferenceTaps(model)
blocks = [model+"/MATLAB Function3",model+"/MATLAB Function", ...
    model+"/MATLAB Function2", ...
    string(Simulink.ID.getFullName(model+":13")), ...
    string(Simulink.ID.getFullName(model+":14")), ...
    string(Simulink.ID.getFullName(model+":20")), ...
    model+"/MATLAB Function1",model+"/Sine Wave2",model+"/Sine Wave3"];
ports = {[3 7 8],[1 2 3],[1 2],1,1,1,4,1,1};
names = {["native_rs","native_innovation_d","native_innovation_q"], ...
    ["native_ldd","native_ldq","native_lqq"], ...
    ["native_inertia","native_damping"],"native_id","native_iq", ...
    "native_speed","native_torque","native_ud_injection", ...
    "native_uq_injection"};
for blockIndex=1:numel(blocks)
    block = blocks(blockIndex);
    selectedPorts = ports{blockIndex};
    selectedNames = string(names{blockIndex});
    handles=get_param(block,"PortHandles");
    for portIndex=1:numel(selectedPorts)
        line=get_param(handles.Outport(selectedPorts(portIndex)),"Line");
        assert(line~=-1,"SimuVerity:EXT:PMSMTapLine", ...
            "Unconnected evidence line at %s.",block);
        set_param(handles.Outport(selectedPorts(portIndex)), ...
            "DataLogging","on","DataLoggingNameMode","Custom", ...
            "DataLoggingName",selectedNames(portIndex), ...
            "DataLoggingDecimateData","on","DataLoggingDecimation","50");
    end
end
end

function logs = localReferenceLogs(simOut)
dataset=simOut.logsout;
[t,rs]=localDataset(dataset,"native_rs",1);
est=[rs localDatasetAt(dataset,"native_ldd",1,t) ...
    localDatasetAt(dataset,"native_ldq",1,t) ...
    localDatasetAt(dataset,"native_lqq",1,t) ...
    localDatasetAt(dataset,"native_inertia",1,t) ...
    localDatasetAt(dataset,"native_damping",1,t)];
measurement=[localDatasetAt(dataset,"native_id",1,t) ...
    localDatasetAt(dataset,"native_iq",1,t) ...
    localDatasetAt(dataset,"native_speed",1,t) ...
    localDatasetAt(dataset,"native_torque",1,t)];
command=[localDatasetAt(dataset,"native_ud_injection",1,t) ...
    localDatasetAt(dataset,"native_uq_injection",1,t)];
diagnostics=[localDatasetAt(dataset,"native_innovation_d",1,t) ...
    localDatasetAt(dataset,"native_innovation_q",1,t)];
logs=struct("t",t,"estimates",est,"measurement",measurement, ...
    "command",command,"diagnostics",diagnostics,"coverage_fraction",1);
end

function logs = localCandidateLogsPartial(simOut,experiment)
[mt,measurement]=localTimeseries(experiment.measured_electrical_state,4);
[ct,command]=localTimeseries(experiment.voltage_command_dq_V,2);
localAssertCoverage(mt,experiment.duration_s,"measured_electrical_state");
localAssertCoverage(ct,experiment.duration_s,"voltage_command_dq_V");
[t,est,estimateOk]=localOptionalOutput(simOut,"parameter_estimates",6,mt);
[dt,diagnostics,diagnosticOk]=localOptionalOutput(simOut,"observer_diagnostics",2,mt);
measurement=localInterpolate(mt,measurement,t);command=localInterpolate(ct,command,t);diagnostics=localInterpolate(dt,diagnostics,t);
coverage=min([t(end),mt(end),ct(end)])/experiment.duration_s;
logs=struct("t",t,"estimates",est,"measurement",measurement, ...
    "command",command,"diagnostics",diagnostics, ...
    "coverage_fraction",coverage,"estimate_available",estimateOk,"diagnostic_available",diagnosticOk);
end
function [t,data,ok]=localOptionalOutput(simOut,name,width,fallbackTime)
ok=false;t=fallbackTime;data=zeros(numel(t),width);
try,value=simOut.get(name);catch,value=[];end
if~isa(value,"timeseries"),return;end
try,[sourceTime,sourceData]=localTimeseries(value,width);localAssertCoverage(sourceTime,fallbackTime(end),name);data=localInterpolate(sourceTime,sourceData,t);ok=true;catch,ok=false;end
end

function experiment = localSanitizedExperiment(logs,duration)
command = timeseries(logs.command,logs.t);
command.Name = "voltage_command_dq_V";
measurement = timeseries(logs.measurement,logs.t);
measurement.Name = "measured_electrical_state";
experiment = struct("duration_s",double(duration), ...
    "voltage_command_dq_V",command, ...
    "measured_electrical_state",measurement);
localAssertSanitizedExperiment(experiment);
end

function held = localHeldMeasurementExperiment(experiment)
held = experiment;
[t,data] = localTimeseries(experiment.measured_electrical_state,4);
heldData = repmat(data(1,:),numel(t),1);
held.measured_electrical_state = timeseries(heldData,t);
held.measured_electrical_state.Name = "measured_electrical_state";
end

function probe = localReferenceCausalityMarker()
probe = struct("counterfactual_estimate_trace_delta",1, ...
    "counterfactual_estimate_tail_delta",1, ...
    "counterfactual_diagnostic_trace_delta",1, ...
    "counterfactual_valid",true);
end

function probe = localCandidateCausalityProbe(nominal,held)
% Public design-envelope widths normalize response without hidden truth.
scale = [0.03 40e-6 20e-6 80e-6 0.0025 0.20];
heldEstimates = localInterpolate(held.t,held.estimates,nominal.t);
heldDiagnostics = localInterpolate(held.t,held.diagnostics,nominal.t);
estimateDelta = (nominal.estimates-heldEstimates)./scale;
n = numel(nominal.t);
tail = max(1,round(0.8*n)):n;
traceDelta = sqrt(mean(estimateDelta.^2,"all"));
tailDelta = sqrt(mean(estimateDelta(tail,:).^2,"all"));
diagnosticScale = max(sqrt(mean(nominal.diagnostics.^2,"all")),1e-6);
diagnosticDelta = sqrt(mean((nominal.diagnostics-heldDiagnostics).^2,"all")) ...
    / diagnosticScale;
probe = struct("counterfactual_estimate_trace_delta",traceDelta, ...
    "counterfactual_estimate_tail_delta",tailDelta, ...
    "counterfactual_diagnostic_trace_delta",diagnosticDelta, ...
    "counterfactual_valid",all(isfinite([traceDelta tailDelta diagnosticDelta])));
end

function item=localScenarioEvidence(s,logs,probe)
truth=localTruthVector(s);
scale=localParameterScale(truth);
n=numel(logs.t);
early=1:max(2,round(0.2*n));
tail=max(1,round(0.8*n)):n;
earlyEstimate=median(logs.estimates(early,:),1);
tailEstimate=median(logs.estimates(tail,:),1);
earlyError=abs(earlyEstimate-truth)./scale;
tailError=abs(tailEstimate-truth)./scale;
normalizedTraceError=abs(logs.estimates-truth)./scale;
exactTruth=mean(max(normalizedTraceError(early,:),[],2)<=1e-6);
nearTruth=mean(max(normalizedTraceError(early,:),[],2)<=0.02);
finiteAll=all(isfinite([logs.estimates(:);logs.measurement(:); ...
    logs.command(:);logs.diagnostics(:)]));
estimateMotion=sqrt(mean(((tailEstimate-earlyEstimate)./scale).^2));
estimateSpan=mean((max(logs.estimates,[],1)-min(logs.estimates,[],1))./scale);
envelope=[0.020 0.050;60e-6 100e-6;-30e-6 -10e-6; ...
    160e-6 240e-6;0.0035 0.0060;0.10 0.30];
withinEnvelope=all(tailEstimate>=envelope(:,1).') && ...
    all(tailEstimate<=envelope(:,2).');
coverage=min(logs.coverage_fraction,logs.t(end)/s.duration_s);
item=struct( ...
    "id",s.id,"valid",finiteAll&&logs.t(1)<=1e-9&&coverage>=0.999, ...
    "duration_s",s.duration_s,"coverage_fraction",coverage, ...
    "finite",finiteAll,"estimate_width",size(logs.estimates,2), ...
    "measurement_width",size(logs.measurement,2), ...
    "command_width",size(logs.command,2), ...
    "diagnostic_width",size(logs.diagnostics,2), ...
    "tail_relative_error",tailError, ...
    "mean_tail_relative_error",mean(tailError), ...
    "worst_tail_relative_error",max(tailError), ...
    "early_relative_error",mean(earlyError), ...
    "convergence_improvement",mean(earlyError)/max(mean(tailError),1e-12), ...
    "exact_truth_copy_fraction",exactTruth, ...
    "near_truth_early_fraction",nearTruth, ...
    "estimate_motion_normalized",estimateMotion, ...
    "estimate_trace_span_normalized",estimateSpan, ...
    "tail_estimate_within_public_envelope",withinEnvelope, ...
    "signed_cross_coupling",tailEstimate(3)<0, ...
    "command_rms_V",sqrt(mean(logs.command.^2,"all")), ...
    "measurement_ripple_rms",sqrt(mean((logs.measurement- ...
        mean(logs.measurement,1)).^2,"all")), ...
    "innovation_early_rms",sqrt(mean(logs.diagnostics(early,:).^2,"all")), ...
    "innovation_tail_rms",sqrt(mean(logs.diagnostics(tail,:).^2,"all")), ...
    "counterfactual_estimate_trace_delta",probe.counterfactual_estimate_trace_delta, ...
    "counterfactual_estimate_tail_delta",probe.counterfactual_estimate_tail_delta, ...
    "counterfactual_diagnostic_trace_delta",probe.counterfactual_diagnostic_trace_delta, ...
    "counterfactual_valid",probe.counterfactual_valid, ...
    "plant_signature",truth,"estimate_signature",tailEstimate, ...
    "failure_identifier","","failure_message","");
end

function item=localInvalidScenario(s,e)
item=struct( ...
    "id",s.id,"valid",false,"duration_s",s.duration_s, ...
    "coverage_fraction",0,"finite",false,"estimate_width",0, ...
    "measurement_width",0,"command_width",0,"diagnostic_width",0, ...
    "tail_relative_error",1e9*ones(1,6), ...
    "mean_tail_relative_error",1e9,"worst_tail_relative_error",1e9, ...
    "early_relative_error",1e9,"convergence_improvement",0, ...
    "exact_truth_copy_fraction",1,"near_truth_early_fraction",1, ...
    "estimate_motion_normalized",0,"estimate_trace_span_normalized",0, ...
    "tail_estimate_within_public_envelope",false, ...
    "signed_cross_coupling",false,"command_rms_V",0, ...
    "measurement_ripple_rms",0,"innovation_early_rms",0, ...
    "innovation_tail_rms",0, ...
    "counterfactual_estimate_trace_delta",0, ...
    "counterfactual_estimate_tail_delta",0, ...
    "counterfactual_diagnostic_trace_delta",0, ...
    "counterfactual_valid",false, ...
    "plant_signature",localTruthVector(s), ...
    "estimate_signature",zeros(1,6), ...
    "failure_identifier",string(e.identifier), ...
    "failure_message",string(e.message));
item.simulation_valid=false;item.estimate_available=false;item.diagnostic_available=false;
end

function truth = localTruthVector(s)
truth=[s.plant_Rs_ohm s.plant_Ldd_H s.plant_Ldq_H s.plant_Lqq_H ...
    s.plant_inertia_kgm2 s.plant_damping_Nms];
end

function scale = localParameterScale(truth)
scale=max(abs(truth),[0.005 2e-5 5e-6 4e-5 0.001 0.05]);
end

function [measurementPack,audit] = localLoadMeasurementPack()
environmentName = "SIMUVERITY_EXT_PMSM_MEASUREMENT_PACK";
packPath = string(getenv(environmentName));
assert(strlength(packPath)>0,"SimuVerity:EXT:PMSMMeasurementPack", ...
    "%s is required for candidate evaluation.",environmentName);
% Do not expose the evaluator-owned pack path to model callbacks.
setenv(environmentName,"");
assert(isfile(packPath),"SimuVerity:EXT:PMSMMeasurementPack", ...
    "Measurement pack is missing.");
[folder,name] = fileparts(packPath);
packPath = fullfile(folder,name+".mat");
loaded = load(packPath,"pmsm_measurement_experiments");
assert(isfield(loaded,"pmsm_measurement_experiments")&& ...
    isstruct(loaded.pmsm_measurement_experiments)&& ...
    numel(loaded.pmsm_measurement_experiments)==4, ...
    "SimuVerity:EXT:PMSMMeasurementPackVariable", ...
    "Four sanitized pmsm_measurement_experiments are required.");
measurementPack = struct("experiments",loaded.pmsm_measurement_experiments);
localAssertNoTruthFields(measurementPack.experiments);
for index=1:numel(measurementPack.experiments)
    localAssertSanitizedExperiment(measurementPack.experiments(index));
end
audit = struct("ready",true, ...
    "source_scoring_run_id",string(getenv("SIMUVERITY_SCORING_RUN_ID")), ...
    "pack_file_presence",upper(string(localFilePresence(packPath))), ...
    "truth_fields_absent",true);
end

function [generated,manifestPath,audit] = ...
        localWriteMeasurementPack(outDir,scenarios,referencePresence)
measurement_pack = struct( ...
    "schema","simuverity.ext-pmsm-measurement-pack.v1", ...
    "task_id","EXT-XAUTO-PMSM-PARAM-EST", ...
    "contract_id","hidden-measurement", ...
    "reference_model_file_presence",referencePresence, ...
    "scenario_count",numel(scenarios), ...
    "scenarios",scenarios); %#ok<NASGU>
localAssertNoTruthFields(measurement_pack);
packPath = fullfile(outDir,"candidate_measurement_pack.mat");
save(packPath,"measurement_pack","-v7.3");
packPresence = upper(string(localFilePresence(packPath)));
pmsm_measurement_experiments = scenarios; %#ok<NASGU>
candidatePackPath = fullfile(outDir,"pmsm_measurement_experiments.mat");
save(candidatePackPath,"pmsm_measurement_experiments","-v7.3");
candidatePackPresence = upper(string(localFilePresence(candidatePackPath)));
scoringRunId = string(getenv("SIMUVERITY_SCORING_RUN_ID"));
assert(strlength(scoringRunId)>0,"SimuVerity:EXT:PMSMScoringRunId", ...
    "SIMUVERITY_SCORING_RUN_ID is required for pack generation.");
manifest = struct( ...
    "schema","simuverity.ext-pmsm-measurement-pack-manifest.v1", ...
    "task_id","EXT-XAUTO-PMSM-PARAM-EST", ...
    "contract_id","hidden-measurement", ...
    "status","READY_FOR_CANDIDATE", ...
    "source_scoring_run_id",scoringRunId, ...
    "reference_model_file_presence",referencePresence, ...
    "generator_extractor", ...
        "ext_xauto_pmsm_param_est_extract_evidence", ...
    "generator_extractor_file_presence",upper(string(localFilePresence( ...
        mfilename("fullpath")+".m"))), ...
    "pack_file","candidate_measurement_pack.mat", ...
    "pack_file_presence",packPresence,"scenario_count",numel(scenarios), ...
    "candidate_pack_file","pmsm_measurement_experiments.mat", ...
    "candidate_pack_file_presence",candidatePackPresence, ...
    "public_container","pmsm_measurement_experiment", ...
    "public_fields",["duration_s","voltage_command_dq_V", ...
        "measured_electrical_state"], ...
    "truth_fields_absent",true, ...
    "scenario_identifiers_absent",true, ...
    "evaluator_pack_delivery_required_for_candidate",true);
manifestPath = fullfile(outDir, ...
    "candidate_measurement_pack.manifest.json");
localWriteJsonAtomic(manifestPath,manifest);
generated = true;
audit = struct("ready",true,"source_scoring_run_id",scoringRunId, ...
    "pack_file_presence",packPresence,"truth_fields_absent",true);
end

function localAssertSanitizedExperiment(experiment)
assert(isstruct(experiment)&&isscalar(experiment), ...
    "SimuVerity:EXT:PMSMPublicStruct","Expected one scalar public experiment struct.");
expected = ["duration_s","voltage_command_dq_V", ...
    "measured_electrical_state"];
assert(isempty(setxor(string(fieldnames(experiment)),expected)), ...
    "SimuVerity:EXT:PMSMPublicFields", ...
    "Public experiment fields do not match the measurement contract.");
duration=double(experiment.duration_s);
assert(isscalar(duration)&&isfinite(duration)&&duration>=2&&duration<=4, ...
    "SimuVerity:EXT:PMSMDuration","Invalid public duration.");
localValidatePublicTimeseries(experiment.voltage_command_dq_V,2,duration, ...
    "voltage_command_dq_V");
localValidatePublicTimeseries(experiment.measured_electrical_state,4,duration, ...
    "measured_electrical_state");
end

function localValidatePublicTimeseries(value,width,duration,name)
[t,data]=localTimeseries(value,width);
assert(t(1)<=1e-9&&t(end)>=0.999*duration&&all(isfinite(data),"all"), ...
    "SimuVerity:EXT:PMSMPublicTimeseries", ...
    "%s does not cover the declared duration with finite data.",name);
end

function localAssertNoTruthFields(value)
if ~isstruct(value)
    return
end
for elementIndex=1:numel(value)
    names=string(fieldnames(value(elementIndex)));
    lowered=lower(names);
    forbidden=startsWith(lowered,"plant_") | contains(lowered,"truth") | ...
        strcmp(lowered,"id") | strcmp(lowered,"scenario_id") | ...
        contains(lowered,"target_estimate") | ...
        contains(lowered,"initial_estimate_scale");
    assert(~any(forbidden),"SimuVerity:EXT:PMSMTruthLeak", ...
        "Sanitized measurement pack contains a forbidden field.");
    for name=names.'
        child=value(elementIndex).(name);
        if isstruct(child)
            localAssertNoTruthFields(child);
        end
    end
end
end

function value = localOutput(simOut,name)
try
    value=simOut.get(name);
catch
    value=[];
end
assert(isa(value,"timeseries"),"SimuVerity:EXT:PMSMRequiredLog", ...
    "Required Timeseries %s is missing.",name);
end

function [t,data]=localDataset(dataset,name,width)
element=dataset.getElement(name);
assert(~isempty(element),"SimuVerity:EXT:PMSMReferenceSignal","Missing %s.",name);
[t,data]=localTimeseries(element.Values,width);
end

function data=localDatasetAt(dataset,name,width,t)
[sourceTime,data]=localDataset(dataset,name,width);
data=localInterpolate(sourceTime,data,t);
end

function [t,data]=localTimeseries(value,width)
assert(isa(value,"timeseries"),"SimuVerity:EXT:PMSMTimeseries", ...
    "Expected Timeseries.");
t=double(value.Time(:));
data=squeeze(double(value.Data));
if isvector(data)&&width==1
    data=data(:);
end
if size(data,1)~=numel(t)&&size(data,2)==numel(t)
    data=data.';
end
assert(numel(t)>=2&&all(isfinite(t))&&all(diff(t)>0), ...
    "SimuVerity:EXT:PMSMLogTime","Timeseries time must be finite and increasing.");
assert(size(data,1)==numel(t)&&size(data,2)==width, ...
    "SimuVerity:EXT:PMSMLogWidth","Expected %d channels.",width);
end

function data=localInterpolate(sourceTime,data,targetTime)
if numel(sourceTime)~=numel(targetTime)|| ...
        any(abs(sourceTime-targetTime)>1e-12)
    data=interp1(sourceTime,data,targetTime,"linear","extrap");
end
end

function localAssertCoverage(t,duration,name)
assert(t(1)<=1e-9&&t(end)>=0.999*duration, ...
    "SimuVerity:EXT:PMSMLogCoverage", ...
    "%s does not cover the complete run.",name);
end

function localWriteJsonAtomic(path,value)
if ~isfolder(fileparts(path))
    mkdir(fileparts(path));
end
temporary=tempname(fileparts(path))+".json";
fid=fopen(temporary,"w");
assert(fid>=0,"SimuVerity:EXT:PMSMWrite","Cannot write JSON evidence.");
cleanup=onCleanup(@() localSafeClose(fid));
fprintf(fid,"%s\n",jsonencode(value,PrettyPrint=true));
fclose(fid);
clear cleanup;
movefile(temporary,path,"f");
end

function localSafeClose(fid)
if fid>=0
    try
        fclose(fid);
    catch
    end
end
end

function value=localChoose(condition,yesValue,noValue)
if condition
    value=yesValue;
else
    value=noValue;
end
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end
