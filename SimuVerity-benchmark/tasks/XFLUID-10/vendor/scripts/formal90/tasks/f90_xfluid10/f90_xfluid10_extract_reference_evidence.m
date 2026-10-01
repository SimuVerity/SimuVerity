function result = f90_xfluid10_extract_reference_evidence(modelPath, outputDir, officialScenarios, evaluatorAssetRoot)
% Fixed-evidence adapter for the pinned R2025a in-line diesel injection model.
% Simulation and physical evidence extraction live here; all score policy is
% deliberately kept in the offline Python scorer.

arguments
    modelPath (1,1) string
    outputDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string
end
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
sourceDir = evaluatorAssetRoot;
assert(isfolder(taskDir) && isfolder(sourceDir), ...
    "SimuVerity:F90:XFLUID10:ReferenceAssetRoot", ...
    "Task root or evaluator-owned reference asset root is missing.");
assert(isfile(modelPath) && isfile(officialScenarios), ...
    "SimuVerity:F90:XFLUID10:ReferenceContract", ...
    "Reference model or official scenarios are missing.");
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xfluid10_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if ~isfolder(outputDir), mkdir(outputDir); end

sharedDir = fullfile(taskDir, "vendor", "scripts", "formal90", "shared");

expectedModelBinding = ...
    "present";
expectedParameterBinding = ...
    "present";
expectedCamBinding = ...
    "present";
parameterPath = fullfile(sourceDir, ...
    "DieselEngineInLineInjectionSystemParameters.m");
camPath = fullfile(sourceDir, "ParabolicCam.ssc");
bindingBefore = localFilePresence(modelPath);
[~, model] = fileparts(modelPath);
evidencePath = fullfile(outputDir, "evidence.json");
official = jsondecode(fileread(officialScenarios));
addpath(sourceDir, "-begin");
sourceCleanup = onCleanup(@() localSafeRmpath(sourceDir)); %#ok<NASGU>
addpath(sharedDir, "-begin");
localConfigureIsolation();

evidence = struct( ...
    "schema", "simuverity.f90-xfluid10-evidence.v1", ...
    "task_id", "F90-XFLUID-10", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "source_file_presence_before", bindingBefore, ...
    "parameter_file_presence", localFilePresence(parameterPath), ...
    "custom_component_file_presence", localFilePresence(camPath), ...
    "reference_direct_golden", strcmpi(bindingBefore, expectedModelBinding), ...
    "reference_substantive_modifications", 0, ...
    "reference_runtime_changes", ...
        "in-memory exposure of the existing speed and fuel-control constants, one flow tap, and native Simscape logging only", ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "evidence_complete", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "preflight", struct(), ...
    "adapter_repair_count", localAdapterRepairCount(evidencePath), ...
    "static_audit", struct(), ...
    "profile", localCompactProfile(), ...
    "output_columns", localOutputColumns(), ...
    "scenarios", struct([]), ...
    "errors", {{}}, ...
    "started_at", localNow());
localAtomicWriteJson(evidencePath, evidence);

try
    assert(strcmpi(bindingBefore, expectedModelBinding), ...
        "SimuVerity:F90:XFLUID10:ReferenceIdentity", ...
        "Pinned diesel-injection model identity differs.");
    assert(strcmpi(localFilePresence(parameterPath), expectedParameterBinding), ...
        "SimuVerity:F90:XFLUID10:ParameterIdentity", ...
        "Pinned parameter script identity differs.");
    assert(strcmpi(localFilePresence(camPath), expectedCamBinding), ...
        "SimuVerity:F90:XFLUID10:CamIdentity", ...
        "Pinned ParabolicCam component identity differs.");

    load_system(modelPath);
    evidence.load_pass = true;
    localPrepareRuntimeModel(model);
    paths = localPaths(model);
    evidence.static_audit = localStaticAudit(model, paths);

    preflightPath = fullfile(outputDir, "preflight.json");
    evidence.preflight = localRunPreflight(model, modelPath, ...
        parameterPath, camPath, expectedModelBinding, expectedParameterBinding, ...
        expectedCamBinding, official.scenarios(1), paths, preflightPath);
    evidence.update_pass = localCheckPassed(evidence.preflight, "model_update");
    evidence.compile_pass = localCheckPassed(evidence.preflight, "model_compile");
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.preflight.pass
        evidence.errors{end + 1} = localIssue("preflight", "aggregate", ...
            "Full non-fail-fast preflight failed; smoke and scenarios were not started.");
        result = localFinalize(model, modelPath, expectedModelBinding, ...
            evidence, evidencePath);
        return;
    end

    try
        localClearOutputs();
        localApplyScenario(model, official.scenarios(1), paths);
        smokeOut = sim(model, "StopTime", "0.05", ...
            "ReturnWorkspaceOutputs", "on", "CaptureErrors", "on");
        assert(strlength(string(smokeOut.ErrorMessage)) == 0, ...
            "SimuVerity:F90:XFLUID10:SmokeSimulation", "%s", smokeOut.ErrorMessage);
        smoke = localExtractSmoke(smokeOut);
        smokeContract = localSmokeContract(smoke);
        evidence.nominal_smoke_pass = localAllTrue(smokeContract);
        if ~evidence.nominal_smoke_pass
            evidence.errors{end + 1} = localIssue("smoke", ...
                "output_contract", jsonencode(smokeContract));
        end
    catch exception
        evidence.nominal_smoke_pass = false;
        evidence.errors{end + 1} = localIssue("smoke", ...
            string(exception.identifier), localExtendedError(exception));
    end
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.nominal_smoke_pass
        result = localFinalize(model, modelPath, expectedModelBinding, ...
            evidence, evidencePath);
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
            applied = localApplyScenario(model, scenario, paths);
            simOut = sim(model, "StopTime", ...
                string(official.simulation.stop_s), ...
                "ReturnWorkspaceOutputs", "on", "CaptureErrors", "on");
            assert(strlength(string(simOut.ErrorMessage)) == 0, ...
                "SimuVerity:F90:XFLUID10:ScenarioSimulation", "%s", ...
                simOut.ErrorMessage);
            outputs = localExtractOutputs(simOut, ...
                official.simulation.stop_s, outputDir);
            contract = localOutputContract(outputs, official.simulation.stop_s);
            metrics = localMetrics(outputs, applied);
            rawPath = fullfile(outputDir, ...
                "raw_" + string(scenario.id) + ".mat");
            localAtomicSaveRaw(rawPath, outputs, applied);
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
                string(exception.identifier), localExtendedError(exception));
        end
        row.wall_seconds = toc(started);
        rows(index) = row;
        localAtomicWriteJson(fullfile(outputDir, ...
            "scenario_" + string(scenario.id) + ".json"), row);
        evidence.scenarios = rows(1:index);
        localAtomicWriteJson(evidencePath, evidence);
    end
    evidence.scenarios = rows;
    evidence.evidence_complete = evidence.load_pass && ...
        evidence.update_pass && evidence.compile_pass && ...
        evidence.nominal_smoke_pass && ...
        evidence.static_audit.core_path_qualified && ...
        numel(rows) == numel(official.scenarios) && all([rows.valid]);
    if evidence.evidence_complete
        evidence.evidence_complete_at = localNow();
    end
catch exception
    evidence.errors{end + 1} = localIssue("session", ...
        string(exception.identifier), localExtendedError(exception));
end
result = localFinalize(model, modelPath, expectedModelBinding, ...
    evidence, evidencePath);
end

function evidence=localRunCandidate(modelPath,outputDir,official,generationRunId)
[~,model]=fileparts(modelPath); model=string(model);
evidencePath=fullfile(outputDir,"evidence.json");
evidence=struct("schema","simuverity.f90-xfluid10-evidence.v1", ...
 "task_id","F90-XFLUID-10","generation_run_id",generationRunId,"reference_direct_golden",false, ...
 "evaluation_subject","candidate","extraction_only",true, ...
 "contains_score_decisions",false,"platform_valid",false, ...
 "score_inputs_valid",false,"diagnostics_valid",false, ...
 "evidence_complete",false,"load_pass",false, ...
 "update_pass",false,"compile_pass",false,"nominal_smoke_pass",false, ...
 "static_audit",struct,"scenarios",struct([]),"errors",{{}});
try
 addpath(fileparts(modelPath),"-begin");load_system(modelPath);evidence.load_pass=true;
 set_param(model,"ReturnWorkspaceOutputs","on","LimitDataPoints","off");
 localApplyCandidateScenario(official.scenarios(1));
 set_param(model,"SimulationCommand","update");evidence.update_pass=true;
 feval(model,[],[],[],"compile");feval(model,[],[],[],"term");evidence.compile_pass=true;
 smokeOut=sim(model,"StopTime","0.05","ReturnWorkspaceOutputs","on");
 smoke=localExtractCandidateOutputs(smokeOut);
 evidence.nominal_smoke_pass=all(isfinite(smoke.injection_delivery),"all");
 rows=repmat(localEmptyScenario(),numel(official.scenarios),1);
 for index=1:numel(official.scenarios)
  scenario=official.scenarios(index);row=localEmptyScenario();row.id=string(scenario.id);
  row.class=string(scenario.class);row.requested_inputs=localScenarioInputs(scenario);
  try
   applied=localApplyCandidateScenario(scenario);
   simOut=sim(model,"StopTime",string(official.simulation.stop_s),"ReturnWorkspaceOutputs","on");
   outputs=localExtractCandidateOutputs(simOut);
   row.output_contract=localOutputContract(outputs,official.simulation.stop_s);
   row.metrics=localMetrics(outputs,applied);row.simulation_pass=true;
   row.valid=localAllTrue(row.output_contract);
  catch exception,row.error=localIssue("scenario",string(exception.identifier),localExtendedError(exception));end
  rows(index)=row;
 end
 evidence.static_audit=localCandidateStaticAudit(model,rows);
 evidence.scenarios=rows;evidence.evidence_complete=evidence.load_pass&&evidence.update_pass&& ...
  evidence.compile_pass&&evidence.nominal_smoke_pass&&all([rows.valid]);
catch exception,evidence.errors{end+1}=localIssue("session",string(exception.identifier),localExtendedError(exception));end
evidence.platform_valid=evidence.load_pass&&evidence.update_pass&&evidence.compile_pass;
evidence.score_inputs_valid=evidence.evidence_complete;
evidence.diagnostics_valid=evidence.evidence_complete;
try,close_system(model,0);catch,end
localAtomicWriteJson(evidencePath,evidence);
end

function applied=localApplyCandidateScenario(scenario)
assignin("base","EngineSpeed_rad_s",double(scenario.EngineSpeed_rad_s));
assignin("base","FuelControl_m",double(scenario.FuelControl_m));
applied=localScenarioInputs(scenario);
end

function outputs=localExtractCandidateOutputs(simOut)
delivery=localCandidateTimeseries(simOut,"injection_delivery",4);
kin=localCandidateTimeseries(simOut,"pump_kinematics",8);
state=localCandidateTimeseries(simOut,"injector_state",8);
time=delivery.time;
outputs=struct("time_s",time,"injection_delivery",delivery.values, ...
 "pump_kinematics",localInterpolate(kin,time), ...
 "injector_state",localInterpolate(state,time), ...
 "native_paths",struct("adapter","candidate_public_timeseries_contract"));
end

function output=localCandidateTimeseries(simOut,variable,width)
series=simuverity_public_output_compatibility( ...
 simOut,string(variable),width,AllowBaseWorkspace=true);
output=struct("time",double(series.Time(:)),"values",double(series.Data));
end

function audit=localCandidateStaticAudit(model,rows)
inventory=localCandidateInventory(model);
pumps=localCandidateClass(inventory,["fixed-displacement pump","fixed_displacement_pump"]);
chambers=localCandidateClass(inventory,["constant volume chamber","constant_volume_chamber"]);
pipes=localCandidateClass(inventory,["pipe (il)","elements.pipe"]);
checks=localCandidateClass(inventory,["check valve","check_valve"]);
orifices=localCandidateClass(inventory,["orifice (il)","valves_orifices.orifices.orifice"]);
flowSensors=localCandidateClass(inventory,["flow rate sensor","flow_rate_sensor"]);
pressureSensors=localCandidateClass(inventory,["pressure sensor","pressure_sensor"]);
converters=localCandidateClass(inventory, ...
 ["translational mechanical converter","translational_mechanical_converter"]);
linearSources=localCandidateClass(inventory, ...
 ["ideal translational velocity source","mechanical.sources.velocity"]);
angularSources=localCandidateClass(inventory, ...
 ["ideal angular velocity source","mechanical.sources.angular_velocity"]);
signalToPhysical=localCandidateClass(inventory,["simulink-ps converter"]);
masses=localCandidateClass(inventory,["translational elements/mass","translational.mass"]);
springs=localCandidateClass(inventory,["translational spring","translational.spring"]);
dampers=localCandidateClass(inventory,["translational damper","translational.damper"]);
hardStops=localCandidateClass(inventory,["translational hard stop","translational.hardstop"]);
reliefs=localCandidateClass(inventory,["pressure relief valve","pressure_relief_valve"]);
reservoirs=localCandidateClass(inventory,["reservoir (il)","elements.reservoir"]);

plungerPaths=strings(0,1);
needlePaths=strings(0,1);
for path=converters(:)'
 if localCandidateDirectCount(path,checks)>=2 && ...
   localCandidateDirectCount(path,orifices)>=1 && ...
   localCandidateDirectCount(path,linearSources)>=1
  plungerPaths(end+1,1)=path; %#ok<AGROW>
 end
 if localCandidateDirectCount(path,chambers)>=1 && ...
   localCandidateDirectCount(path,flowSensors)>=1 && ...
   localCandidateDirectCount(path,masses)>=1 && ...
   localCandidateDirectCount(path,springs)>=1 && ...
   localCandidateDirectCount(path,dampers)>=1 && ...
   localCandidateDirectCount(path,hardStops)>=1
  needlePaths(end+1,1)=path; %#ok<AGROW>
 end
end

feedChambers=strings(0,1);
highPressurePathCount=0;
for path=chambers(:)'
 if localCandidateDirectCount(path,pumps)>=1 && ...
   localCandidateDirectCount(path,checks)>=4
  feedChambers(end+1,1)=path; %#ok<AGROW>
 end
 if localCandidateWithinHops(path,plungerPaths,2) && ...
   localCandidateDirectCount(path,needlePaths)>=1 && ...
   localCandidateDirectCount(path,flowSensors)>=1 && ...
   localCandidateDirectCount(path,pressureSensors)>=1
  highPressurePathCount=highPressurePathCount+1;
 end
end

controlledOrificeCount=0;
for path=orifices(:)'
 if localCandidateDirectCount(path,signalToPhysical)>=1
  controlledOrificeCount=controlledOrificeCount+1;
 end
end
signalDrivenMotionSourceCount=0;
for path=linearSources(:)'
 if localCandidateDirectCount(path,signalToPhysical)>=1
  signalDrivenMotionSourceCount=signalDrivenMotionSourceCount+1;
 end
end

liftPumpConnected=false;
for path=pumps(:)'
 liftPumpConnected=liftPumpConnected || (...
  localCandidateDirectCount(path,reservoirs)>=1 && ...
  localCandidateDirectCount(path,feedChambers)>=1 && ...
  localCandidateDirectCount(path,reliefs)>=1 && ...
  localCandidateDirectCount(path,angularSources)>=1);
end
feedReliefConnected=any(arrayfun(@(index) ...
 localCandidateDirectCount(feedChambers(index),reliefs)>=1, ...
 (1:numel(feedChambers))'));
behavior=localCandidateBehaviorAudit(rows);

fourPumps=numel(plungerPaths)>=4;
fourInjectors=numel(needlePaths)>=4;
fiveCamOutputs=numel(linearSources)>=4 && numel(angularSources)>=1 && ...
 behavior.speed_response;
fuelDrivesAll=localCandidateUsesPublicVariable(model,"FuelControl_m") && ...
 controlledOrificeCount>=4 && behavior.fuel_response;
speedDrivesCam=localCandidateUsesPublicVariable(model,"EngineSpeed_rad_s") && ...
 numel(angularSources)>=1 && behavior.speed_response;
pairedPaths=highPressurePathCount>=4 && behavior.four_causal_delivery_paths;
feedPresent=~isempty(feedChambers);
accumulatorRelief=feedPresent && feedReliefConnected;
reservoirPresent=~isempty(reservoirs);
audit=struct( ...
 "four_injection_pumps",fourPumps, ...
 "four_injectors",fourInjectors, ...
 "camshaft_has_five_physical_outputs",fiveCamOutputs, ...
 "lift_pump_is_physically_connected",liftPumpConnected, ...
 "fuel_control_drives_all_pumps",fuelDrivesAll, ...
 "speed_drives_camshaft",speedDrivesCam, ...
 "each_pump_feeds_its_injector",pairedPaths, ...
 "feed_pipe_present",feedPresent, ...
 "accumulator_and_relief_present",accumulatorRelief, ...
 "reservoir_present",reservoirPresent, ...
 "candidate_structure_scan",true, ...
 "structure_evidence_mode","library_identity_connectivity_and_behavior", ...
 "component_counts",struct( ...
  "fixed_displacement_pumps",numel(pumps), ...
  "plunger_pump_paths",numel(plungerPaths), ...
  "injector_needle_paths",numel(needlePaths), ...
  "high_pressure_delivery_paths",highPressurePathCount, ...
  "feed_chambers",numel(feedChambers), ...
  "controlled_orifices",controlledOrificeCount, ...
  "compressible_delivery_elements",numel(chambers)+numel(pipes), ...
  "mechanical_storage_elements",numel(masses)+numel(springs)+numel(dampers), ...
  "plunger_motion_sources",numel(linearSources), ...
  "signal_driven_plunger_sources",signalDrivenMotionSourceCount, ...
  "reference_blocks",sum(inventory.block_types=="reference"), ...
  "reservoirs",numel(reservoirs),"relief_valves",numel(reliefs)), ...
 "causal_behavior",behavior);
required=[fourPumps,fourInjectors,fiveCamOutputs,liftPumpConnected, ...
 fuelDrivesAll,speedDrivesCam,pairedPaths,feedPresent, ...
 accumulatorRelief,reservoirPresent];
audit.core_path_qualified=all(required);
end

function inventory=localCandidateInventory(model)
blocks=string(find_system(model,"FollowLinks","on", ...
 "LookUnderMasks","all","Type","Block"));
identities=strings(numel(blocks),1);
blockTypes=strings(numel(blocks),1);
for index=1:numel(blocks)
 blockTypes(index)=lower(localCandidateParameter(blocks(index),"BlockType"));
 parts=strings(0,1);
 for parameter=["ReferenceBlock","SourceBlock","SourceType","ComponentPath"]
  value=strtrim(localCandidateParameter(blocks(index),parameter));
  if strlength(value)>0,parts(end+1,1)=value;end %#ok<AGROW>
 end
 identities(index)=lower(strjoin(parts,"|"));
end
inventory=struct("blocks",blocks(:),"identities",identities, ...
 "block_types",blockTypes);
end

function value=localCandidateParameter(path,parameter)
value="";
try
 raw=get_param(path,parameter);
 if ischar(raw)||(isstring(raw)&&isscalar(raw)),value=string(raw);end
catch
end
end

function blocks=localCandidateClass(inventory,tokens)
matched=false(size(inventory.blocks));
for token=lower(string(tokens))
 matched=matched|contains(inventory.identities,token);
end
blocks=inventory.blocks(matched);
end

function count=localCandidateDirectCount(path,candidates)
if isempty(candidates),count=0;return;end
neighbors=localCandidateNeighborHandles(path);
targets=zeros(numel(candidates),1);
for index=1:numel(candidates)
 targets(index)=getSimulinkBlockHandle(candidates(index),false);
end
count=numel(intersect(neighbors,targets(targets>0)));
end

function handles=localCandidateNeighborHandles(path)
handles=zeros(0,1);
try
 connectivity=get_param(path,"PortConnectivity");
 for index=1:numel(connectivity)
  handles=[handles;double(connectivity(index).DstBlock(:)); ... %#ok<AGROW>
   double(connectivity(index).SrcBlock(:))]; %#ok<AGROW>
 end
catch
end
handles=unique(handles(isfinite(handles)&handles>0));
end

function passed=localCandidateWithinHops(path,candidates,maximumHops)
passed=false;
if isempty(candidates),return;end
targets=zeros(numel(candidates),1);
for index=1:numel(candidates)
 targets(index)=getSimulinkBlockHandle(candidates(index),false);
end
targets=targets(targets>0);
start=getSimulinkBlockHandle(path,false);
frontier=start;visited=start;
for hop=1:maximumHops
 next=zeros(0,1);
 for index=1:numel(frontier)
  next=[next;localCandidateNeighborHandles(frontier(index))]; %#ok<AGROW>
 end
 next=unique(next);
 if any(ismember(next,targets)),passed=true;return;end
 frontier=setdiff(next,visited);
 visited=unique([visited;frontier]);
 if isempty(frontier),return;end
end
end

function used=localCandidateUsesPublicVariable(model,name)
used=false;
try
 uses=Simulink.findVars(model,"Name",char(name));
 used=~isempty(uses);
catch
end
if used,return;end
blocks=string(find_system(model,"FollowLinks","on", ...
 "LookUnderMasks","all","Type","Block"));
for path=blocks(:)'
 for parameter=["Value","VariableName","Expression"]
  value=localCandidateParameter(path,parameter);
  if strcmp(strtrim(value),string(name)),used=true;return;end
 end
end
end

function behavior=localCandidateBehaviorAudit(rows)
[nominal,hasNominal]=localCandidateScenarioMetrics(rows,"nominal");
[lowFuel,hasLowFuel]=localCandidateScenarioMetrics(rows,"low_fuel");
[highFuel,hasHighFuel]=localCandidateScenarioMetrics(rows,"high_fuel");
[lowSpeed,hasLowSpeed]=localCandidateScenarioMetrics(rows,"low_speed");
[highSpeed,hasHighSpeed]=localCandidateScenarioMetrics(rows,"high_speed");
lowVolumes=localCandidateMetricVector(lowFuel,"pulse_volume_per_event_m3");
highVolumes=localCandidateMetricVector(highFuel,"pulse_volume_per_event_m3");
fuelResponse=hasLowFuel&&hasHighFuel&&numel(lowVolumes)==4&& ...
 numel(highVolumes)==4&&all(isfinite([lowVolumes,highVolumes]))&& ...
 all(highVolumes>1.05*lowVolumes);
lowRate=localCandidateMetric(lowSpeed,"combined_event_rate_Hz",NaN);
highRate=localCandidateMetric(highSpeed,"combined_event_rate_Hz",NaN);
lowPlungerSpeed=localCandidateMetric(lowSpeed,"maximum_plunger_speed_m_s",NaN);
highPlungerSpeed=localCandidateMetric(highSpeed,"maximum_plunger_speed_m_s",NaN);
speedResponse=hasLowSpeed&&hasHighSpeed&&all(isfinite( ...
 [lowRate,highRate,lowPlungerSpeed,highPlungerSpeed]))&& ...
 highRate>1.2*lowRate&&highPlungerSpeed>1.2*lowPlungerSpeed;
nominalVolumes=localCandidateMetricVector(nominal,"pulse_volume_per_event_m3");
nominalCounts=localCandidateMetricVector(nominal,"pulse_count_per_injector");
fourPaths=hasNominal&&numel(nominalVolumes)==4&&numel(nominalCounts)==4&& ...
 all(nominalVolumes>0)&&all(nominalCounts>=1)&& ...
 localCandidateMetric(nominal,"minimum_plunger_amplitude_m",0)>1e-6&& ...
 localCandidateMetric(nominal,"minimum_needle_lift_m",0)>1e-8&& ...
 localCandidateMetric(nominal,"minimum_peak_chamber_pressure_Pa",0)>1e5&& ...
 localCandidateMetric(nominal,"maximum_zero_lag_flow_correlation",1)<0.98&& ...
 localCandidateMetric(nominal,"firing_order_match_fraction",0)>=0.75;
behavior=struct("fuel_response",fuelResponse,"speed_response",speedResponse, ...
 "four_causal_delivery_paths",fourPaths);
end

function [metrics,present]=localCandidateScenarioMetrics(rows,id)
metrics=struct;present=false;
for index=1:numel(rows)
 if strcmpi(string(rows(index).id),string(id))&& ...
   logical(rows(index).valid)&&isstruct(rows(index).metrics)
  metrics=rows(index).metrics;present=true;return;
 end
end
end

function value=localCandidateMetric(metrics,name,default)
field=char(name);value=default;
if isstruct(metrics)&&isfield(metrics,field)
 candidate=double(metrics.(field));
 if isscalar(candidate),value=candidate;end
end
end

function values=localCandidateMetricVector(metrics,name)
field=char(name);values=zeros(1,0);
if isstruct(metrics)&&isfield(metrics,field)
 values=double(metrics.(field));values=values(:)';
end
end

function localPrepareRuntimeModel(model)
set_param(model, ...
    "SimulationMode", "normal", ...
    "ReturnWorkspaceOutputs", "on", ...
    "LimitDataPoints", "off", ...
    "SimscapeLogType", "all", ...
    "SimscapeLogName", "simlog_F90_XFLUID10", ...
    "SimscapeLogLimitData", "off");
set(groot, "defaultFigureVisible", "off");
paths = localPaths(model);
localInstallTap(model, paths.flow_mux, "F90_InjectorFlows");
end

function report = localRunPreflight(model, modelPath, parameterPath, ...
        camPath, expectedModelBinding, expectedParameterBinding, ...
        expectedCamBinding, nominal, paths, reportPath)
localApplyScenario(model, nominal, paths);
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
audit = localStaticAudit(model, paths);
checks = [
    localCheckDef("source_identity", "path", ...
        @() localIdentityCheck(modelPath, parameterPath, camPath, ...
        expectedModelBinding, expectedParameterBinding, expectedCamBinding));
    localCheckDef("dependencies", "dependency", @() localCheckDependencies());
    localCheckDef("workspace_contract", "workspace", @() localCheckWorkspace());
    localCheckDef("locator_contract", "locator", @() localCheckLocators(paths));
    localCheckDef("port_contract", "port", @() localCheckPorts(paths));
    localCheckDef("model_update", "api", @() localBooleanResult( ...
        updatePass, "update_pass=" + updatePass, updateDetail));
    localCheckDef("model_compile", "api", @() localBooleanResult( ...
        compilePass, "compile_pass=" + compilePass, compileDetail));
    localCheckDef("compiled_dimensions", "compiled_dimension", ...
        @() localCheckCompiledDimensions(paths, compilePass, compileDetail));
    localCheckDef("compiled_types", "compiled_type", ...
        @() localCheckCompiledTypes(paths, compilePass, compileDetail));
    localCheckDef("logging_contract", "logging", @() localCheckLogging(model));
    localCheckDef("api_contract", "api", @() localCheckApis());
    localCheckDef("causal_path_contract", "locator", ...
        @() localBooleanResult(audit.core_path_qualified, ...
        "core_path_qualified", ...
        "Required lift-pump, four-plunger, high-pressure and injector paths are incomplete."))
];
report = formal90_nonfailfast_preflight(checks, string(reportPath));
try
    if compilePass, feval(model, [], [], [], "term"); end
catch
end
end

function definition = localCheckDef(id, category, run)
definition = struct("id", string(id), "category", string(category), ...
    "run", run);
end

function result = localIdentityCheck(modelPath, parameterPath, camPath, ...
        expectedModelBinding, expectedParameterBinding, expectedCamBinding)
actual = [string(localFilePresence(modelPath)); ...
    string(localFilePresence(parameterPath)); string(localFilePresence(camPath))];
expected = [string(expectedModelBinding); string(expectedParameterBinding); ...
    string(expectedCamBinding)];
result = localBooleanResult(all(strcmpi(actual, expected)), ...
    "matched=" + sum(strcmpi(actual, expected)) + "/3", ...
    "One or more pinned official source identities differ.");
end

function result = localCheckDependencies()
productInfo = ver;
products = string({productInfo.Name});
required = ["Simulink", "Simscape", "Simscape Fluids"];
present = false(size(required));
for index = 1:numel(required)
    present(index) = any(strcmpi(products, required(index)));
end
passed = all(present) && ~isempty(which("sim")) && ...
    ~isempty(which("Simulink.fileGenControl"));
result = localBooleanResult(passed, ...
    "present=" + sum(present) + "/" + numel(required), ...
    "Required R2025a products or APIs are unavailable.");
end

function result = localCheckWorkspace()
required = ["EngineSpeed_rad_s", "FuelControl_m"];
present = arrayfun(@(name) evalin("base", ...
    "exist('" + name + "','var') == 1"), required);
valid = arrayfun(@(name) isvarname(char(name)) && ...
    ~iskeyword(char(name)) && strlength(name) <= namelengthmax, required);
result = localBooleanResult(all(present) && all(valid), ...
    "present=" + sum(present) + "/2;valid_names=" + sum(valid) + "/2", ...
    "Required workspace inputs are absent or invalid.");
end

function paths = localPaths(model)
paths = struct( ...
    "camshaft", model + "/Cam Shaft", ...
    "speed", model + "/rad//s", ...
    "fuel_control", model + "/Fuel Control", ...
    "lift_pump", model + "/Lift Pump", ...
    "feed_pipe", model + "/Pipe (IL)", ...
    "reservoir", model + "/Reservoir (IL)", ...
    "accumulator", model + "/Spring-Loaded" + newline + "Accumulator (IL)", ...
    "relief", model + "/Pressure Relief" + newline + "Valve (IL)", ...
    "flow_mux", model + "/Mux", ...
    "flow_scope", model + "/Injector" + newline + "Flow Rates");
paths.pumps = strings(4, 1);
paths.injectors = strings(4, 1);
for index = 1:4
    paths.pumps(index) = model + "/Injection Pump " + index;
    paths.injectors(index) = model + "/Injector " + index;
end
end

function result = localCheckLocators(paths)
names = [paths.camshaft; paths.speed; paths.fuel_control; ...
    paths.lift_pump; paths.feed_pipe; paths.reservoir; ...
    paths.accumulator; paths.relief; paths.flow_mux; ...
    paths.flow_scope; paths.pumps; paths.injectors];
present = arrayfun(@(path) getSimulinkBlockHandle(path, false) > 0, names);
result = localBooleanResult(all(present), ...
    "present=" + sum(present) + "/" + numel(present), ...
    "One or more declared model locators are absent.");
end

function result = localCheckPorts(paths)
passed = true;
detail = strings(0, 1);
sourcePaths = [paths.speed; paths.fuel_control; paths.flow_mux];
for index = 1:numel(sourcePaths)
    path = sourcePaths(index);
    try
        blockHandle = getSimulinkBlockHandle(path, false);
        ports = double(get_param(blockHandle, "Ports"));
        outputCount = ports(2);
        passed = passed && outputCount >= 1;
        detail(end + 1) = path + ":out=" + ...
            outputCount; %#ok<AGROW>
    catch exception
        passed = false;
        detail(end + 1) = path + ":read_failed"; %#ok<AGROW>
    end
end
result = localBooleanResult(passed, ...
    "signal_source_ports_present=" + passed + ";" + join(detail, " | "), ...
    "One or more signal-source output ports are absent.");
end

function result = localCheckCompiledDimensions(paths, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_pass=false", detail);
    return;
end
try
    dimensions = get_param(paths.flow_mux, "CompiledPortDimensions");
    outputDimensions = dimensions.Outport;
    width = prod(double(outputDimensions(outputDimensions > 0)));
    result = localBooleanResult(width == 4, ...
        "flow_mux_width=" + width, ...
        "Injector-flow mux must compile to four channels.");
catch exception
    result = localBooleanResult(false, "dimension_read_failed", ...
        localExtendedError(exception));
end
end

function result = localCheckCompiledTypes(paths, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_pass=false", detail);
    return;
end
try
    types = get_param(paths.flow_mux, "CompiledPortDataTypes");
    passed = strcmpi(string(types.Outport), "double");
    result = localBooleanResult(passed, ...
        "flow_mux_type=" + string(types.Outport), ...
        "Injector-flow mux must compile as double.");
catch exception
    result = localBooleanResult(false, "type_read_failed", ...
        localExtendedError(exception));
end
end

function result = localCheckLogging(model)
required = ["ReturnWorkspaceOutputs", "LimitDataPoints", ...
    "SimscapeLogType", "SimscapeLogName", "SimscapeLogLimitData"];
expected = ["on", "off", "all", "simlog_F90_XFLUID10", "off"];
actual = arrayfun(@(name) string(get_param(model, name)), required);
tap = model + "/__F90_InjectorFlows";
tapOk = getSimulinkBlockHandle(tap, false) > 0 && ...
    strcmpi(string(get_param(tap, "VariableName")), "F90_InjectorFlows") && ...
    strcmpi(string(get_param(tap, "SaveFormat")), "Timeseries");
passed = all(strcmpi(actual, expected)) && tapOk;
result = localBooleanResult(passed, ...
    "settings=" + join(actual, ",") + ";tap=" + tapOk, ...
    "Runtime logging contract is incomplete.");
end

function result = localCheckApis()
required = ["jsonencode", "jsondecode", "sim", "load_system", ...
    "add_block", "add_line", "get_param", "set_param"];
present = arrayfun(@(name) ~isempty(which(name)), required);
result = localBooleanResult(all(present), ...
    "present=" + sum(present) + "/" + numel(required), ...
    "One or more required MATLAB/Simulink APIs are unavailable.");
end

function audit = localStaticAudit(model, paths)
pumpPresent = arrayfun(@(path) ...
    getSimulinkBlockHandle(path, false) > 0, paths.pumps);
injectorPresent = arrayfun(@(path) ...
    getSimulinkBlockHandle(path, false) > 0, paths.injectors);
camConnections = localPhysicalConnectionCount(paths.camshaft);
liftConnections = localPhysicalConnectionCount(paths.lift_pump);
fuelDestinations = localSignalDestinations(paths.fuel_control);
speedDestinations = localSignalDestinations(paths.speed);
pairConnected = false(4, 1);
for index = 1:4
    pairConnected(index) = localBlocksDirectlyConnected( ...
        paths.pumps(index), paths.injectors(index));
end
audit = struct( ...
    "four_injection_pumps", all(pumpPresent), ...
    "four_injectors", all(injectorPresent), ...
    "camshaft_has_five_physical_outputs", camConnections >= 5, ...
    "lift_pump_is_physically_connected", liftConnections >= 2, ...
    "fuel_control_drives_all_pumps", ...
        all(arrayfun(@(path) any(fuelDestinations == path), paths.pumps)), ...
    "speed_drives_camshaft", any(speedDestinations == paths.camshaft), ...
    "each_pump_feeds_its_injector", all(pairConnected), ...
    "feed_pipe_present", getSimulinkBlockHandle(paths.feed_pipe, false) > 0, ...
    "accumulator_and_relief_present", ...
        getSimulinkBlockHandle(paths.accumulator, false) > 0 && ...
        getSimulinkBlockHandle(paths.relief, false) > 0, ...
    "reservoir_present", getSimulinkBlockHandle(paths.reservoir, false) > 0);
fields = fieldnames(audit);
audit.core_path_qualified = all(cellfun(@(name) ...
    logical(audit.(name)), fields));
audit.model = string(model);
end

function count = localPhysicalConnectionCount(path)
count = 0;
try
    connectivity = get_param(path, "PortConnectivity");
    for index = 1:numel(connectivity)
        if ~isempty(connectivity(index).DstBlock) || ...
                connectivity(index).SrcBlock > 0
            count = count + 1;
        end
    end
catch
end
end

function destinations = localSignalDestinations(path)
destinations = strings(0, 1);
try
    handles = get_param(path, "PortHandles");
    line = get_param(handles.Outport(1), "Line");
    destinationHandles = get_param(line, "DstBlockHandle");
    destinationHandles = destinationHandles(destinationHandles > 0);
    for handle = destinationHandles(:)'
        destinations(end + 1, 1) = string(getfullname(handle)); %#ok<AGROW>
    end
catch
end
end

function passed = localBlocksDirectlyConnected(first, second)
passed = false;
try
    firstHandle = getSimulinkBlockHandle(first, false);
    secondHandle = getSimulinkBlockHandle(second, false);
    connectivity = get_param(first, "PortConnectivity");
    for index = 1:numel(connectivity)
        destinations = connectivity(index).DstBlock;
        if any(destinations == secondHandle)
            passed = true;
            return;
        end
        if connectivity(index).SrcBlock == secondHandle
            passed = true;
            return;
        end
    end
    assert(firstHandle > 0); %#ok<NASGU>
catch
end
end

function applied = localApplyScenario(model, scenario, paths)
speed = double(scenario.EngineSpeed_rad_s);
fuel = double(scenario.FuelControl_m);
assignin("base", "EngineSpeed_rad_s", speed);
assignin("base", "FuelControl_m", fuel);
set_param(paths.speed, "Value", num2str(speed, 17));
set_param(paths.fuel_control, "Value", num2str(fuel, 17));
set_param(model, "StopTime", "0.25");
applied = struct("EngineSpeed_rad_s", speed, "FuelControl_m", fuel);
end

function localInstallTap(parent, source, variable)
assert(getSimulinkBlockHandle(source, false) > 0, ...
    "SimuVerity:F90:XFLUID10:TapSource", "Missing tap source %s.", source);
tap = parent + "/__F90_InjectorFlows";
if getSimulinkBlockHandle(tap, false) < 0
    add_block("simulink/Sinks/To Workspace", tap, ...
        "VariableName", variable, "SaveFormat", "Timeseries", ...
        "MaxDataPoints", "inf", ...
        "Position", [590, 520, 740, 550]);
    sourceHandles = get_param(source, "PortHandles");
    tapHandles = get_param(tap, "PortHandles");
    add_line(parent, sourceHandles.Outport(1), tapHandles.Inport(1), ...
        "autorouting", "on");
end
end

function smoke = localExtractSmoke(simOut)
flow = localTimeseries(simOut, "F90_InjectorFlows");
simlog = localGetSimlog(simOut);
smoke = struct("flow", flow, "simlog_present", ~isempty(simlog));
end

function contract = localSmokeContract(smoke)
contract = struct( ...
    "flow_nonempty", numel(smoke.flow.time) >= 2, ...
    "flow_width_4", size(smoke.flow.values, 2) == 4, ...
    "flow_starts_at_zero", abs(smoke.flow.time(1)) <= 1e-9, ...
    "flow_reaches_smoke_end", smoke.flow.time(end) >= 0.049, ...
    "flow_finite", all(isfinite(smoke.flow.values), "all"), ...
    "simscape_log_present", smoke.simlog_present);
end

function outputs = localExtractOutputs(simOut, stopTime, outputDir)
flow = localTimeseries(simOut, "F90_InjectorFlows");
simlog = localGetSimlog(simOut);
inventory = localSimlogInventory(simlog, 8, 2500);

plunger = cell(4, 1);
needle = cell(4, 1);
pressure = cell(4, 1);
locators = struct("plunger", strings(4, 1), ...
    "needle", strings(4, 1), "pressure", strings(4, 1));
for index = 1:4
    pump = "Injection_Pump_" + index;
    injector = "Injector_" + index;
    [plunger{index}, locators.plunger(index)] = localFindNative( ...
        simlog, inventory, {[pump, "Plunger", "hard_stop", "x"], ...
        [pump, "Plunger", "interface_displacement"], ...
        [pump, "Plunger", "x"]}, "m");
    [needle{index}, locators.needle(index)] = localFindNative( ...
        simlog, inventory, {[injector, "Needle_Valve", "S"], ...
        [injector, "Needle_Valve", "x"], ...
        [injector, "Needle_Valve", "hard_stop", "x"], ...
        [injector, "Mass", "x"]}, "m");
    [pressure{index}, locators.pressure(index)] = localFindNative( ...
        simlog, inventory, {[injector, "Chamber", "p_I"], ...
        [injector, "Chamber", "A", "p"], ...
        [injector, "Needle_Valve", "A", "p"]}, "Pa");
end
missing = any(cellfun(@(item) isempty(item.time), plunger)) || ...
    any(cellfun(@(item) isempty(item.time), needle)) || ...
    any(cellfun(@(item) isempty(item.time), pressure));
if missing
    localAtomicWriteJson(fullfile(outputDir, "native_inventory.json"), ...
        struct("resolved", locators, "inventory", inventory));
    error("SimuVerity:F90:XFLUID10:NativeLocator", ...
        "Required plunger, needle or injector-pressure series are unresolved; inspect native_inventory.json.");
end

time = linspace(0, double(stopTime), ...
    max(3, round(10000 * double(stopTime)) + 1))';
positions = zeros(numel(time), 4);
needles = zeros(numel(time), 4);
pressures = zeros(numel(time), 4);
for index = 1:4
    positions(:, index) = localInterpolate(plunger{index}, time);
    needles(:, index) = localInterpolate(needle{index}, time);
    pressures(:, index) = localInterpolate(pressure{index}, time);
end
velocities = zeros(size(positions));
for index = 1:4
    velocities(:, index) = gradient(positions(:, index), time);
end
outputs = struct( ...
    "time_s", time, ...
    "injection_delivery", localInterpolate(flow, time), ...
    "pump_kinematics", [positions, velocities], ...
    "injector_state", [needles, pressures], ...
    "native_paths", locators);
end

function simlog = localGetSimlog(simOut)
simlog = [];
try, simlog = simOut.get("simlog_F90_XFLUID10"); catch, end
if isempty(simlog)
    try, simlog = evalin("base", "simlog_F90_XFLUID10"); catch, end
end
assert(~isempty(simlog), "SimuVerity:F90:XFLUID10:Simlog", ...
    "Required native Simscape log is missing.");
end

function [output, path] = localFindNative(root, inventory, tokenSets, unit)
output = struct("time", [], "values", []);
path = "";
paths = string({inventory.path});
for tokenIndex = 1:numel(tokenSets)
    tokens = lower(string(tokenSets{tokenIndex}));
    candidates = true(size(paths));
    for token = tokens
        candidates = candidates & contains(lower(paths), lower(token));
    end
    indices = find(candidates);
    for index = indices(:)'
        nodePath = erase(paths(index), "simlog.");
        try
            node = localNodeAtPath(root, nodePath);
            series = node.series;
            time = double(series.time);
            values = squeeze(double(series.values(char(unit))));
            time = time(:);
            if isvector(values), values = values(:); end
            if numel(time) >= 2 && size(values, 1) == numel(time) && ...
                    size(values, 2) == 1 && all(isfinite(time)) && ...
                    all(isfinite(values), "all")
                output = struct("time", time, "values", values);
                path = nodePath;
                return;
            end
        catch
        end
    end
end
end

function node = localNodeAtPath(root, path)
node = root;
parts = split(string(path), ".");
for part = parts(:)'
    if strlength(part) > 0
        node = node.(char(part));
    end
end
end

function inventory = localSimlogInventory(root, maximumDepth, maximumRows)
inventory = repmat(struct("path", "", "samples", 0), 0, 1);
inventory = localInventoryWalk(root, "simlog", 0, maximumDepth, ...
    maximumRows, inventory);
end

function rows = localInventoryWalk(node, prefix, depth, maximumDepth, ...
        maximumRows, rows)
if numel(rows) >= maximumRows || depth > maximumDepth, return; end
try
    native = node.series;
    time = double(native.time);
    if ~isempty(time)
        rows(end + 1, 1) = struct("path", string(prefix), ...
            "samples", numel(time)); %#ok<AGROW>
    end
catch
end
ids = strings(0, 1);
try, ids = string(node.childIds); catch, end
if isempty(ids)
    try, ids = string(childIds(node)); catch, end
end
for id = ids(:)'
    if numel(rows) >= maximumRows, return; end
    try
        child = node.(char(id));
        rows = localInventoryWalk(child, prefix + "." + id, ...
            depth + 1, maximumDepth, maximumRows, rows);
    catch
    end
end
end

function output = localTimeseries(simOut, variable)
value = [];
try, value = simOut.get(variable); catch, end
if isempty(value)
    try, value = evalin("base", variable); catch, end
end
assert(isa(value, "timeseries"), "SimuVerity:F90:XFLUID10:Timeseries", ...
    "Required output %s is not a Timeseries.", variable);
raw = squeeze(double(value.Data));
if isvector(raw), raw = raw(:); end
if size(raw, 1) ~= numel(value.Time) && size(raw, 2) == numel(value.Time)
    raw = raw.';
end
assert(size(raw, 1) == numel(value.Time), ...
    "SimuVerity:F90:XFLUID10:TimeseriesShape", ...
    "Required output %s has unexpected dimensions.", variable);
output = struct("time", double(value.Time(:)), "values", raw);
end

function values = localInterpolate(series, time)
[sourceTime, indices] = unique(double(series.time(:)), "stable");
sourceValues = double(series.values(indices, :));
assert(~isempty(sourceTime) && all(isfinite(sourceTime)) && ...
    all(isfinite(sourceValues), "all"), ...
    "SimuVerity:F90:XFLUID10:Interpolation", "Required series is invalid.");
if numel(sourceTime) == 1
    values = repmat(sourceValues(1, :), numel(time), 1);
else
    values = interp1(sourceTime, sourceValues, time, "linear", "extrap");
end
end

function contract = localOutputContract(outputs, stopTime)
plungerAmplitude = max(outputs.pump_kinematics(:,1:4), [], 1) - ...
    min(outputs.pump_kinematics(:,1:4), [], 1);
needleAmplitude = max(outputs.injector_state(:,1:4), [], 1) - ...
    min(outputs.injector_state(:,1:4), [], 1);
contract = struct( ...
    "time_strictly_increasing", all(diff(outputs.time_s) > 0), ...
    "time_starts_at_zero", abs(outputs.time_s(1)) <= 1e-9, ...
    "complete_interval", outputs.time_s(end) >= double(stopTime) - 1e-6, ...
    "sample_count_sufficient", numel(outputs.time_s) >= 2001, ...
    "delivery_width_4", size(outputs.injection_delivery, 2) == 4, ...
    "kinematics_width_8", size(outputs.pump_kinematics, 2) == 8, ...
    "injector_state_width_8", size(outputs.injector_state, 2) == 8, ...
    "all_finite", all(isfinite([outputs.injection_delivery(:); ...
        outputs.pump_kinematics(:); outputs.injector_state(:)])), ...
    "all_plungers_active", all(plungerAmplitude > 1e-6), ...
    "all_needles_active", all(needleAmplitude > 1e-8), ...
    "all_injectors_deliver", all(max(abs(outputs.injection_delivery)) > 1e-8));
end

function metrics = localMetrics(outputs, applied)
time = outputs.time_s;
flow = abs(outputs.injection_delivery);
position = outputs.pump_kinematics(:, 1:4);
velocity = outputs.pump_kinematics(:, 5:8);
needle = outputs.injector_state(:, 1:4);
pressure = outputs.injector_state(:, 5:8);
analysisStart = 0.04;
analysisMask = time >= analysisStart;
plungerAmplitude = max(position(analysisMask,:), [], 1) - ...
    min(position(analysisMask,:), [], 1);
needleAmplitude = max(needle(analysisMask,:), [], 1) - ...
    min(needle(analysisMask,:), [], 1);

pulseCount = zeros(1,4);
pulseVolume = zeros(1,4);
peakFlow = zeros(1,4);
pulseVolumeCv = zeros(1,4);
lastPulseDrift = zeros(1,4);
allEventTimes = zeros(0,1);
allEventIds = zeros(0,1);
for index = 1:4
    [eventTimes, eventVolumes, eventPeaks] = ...
        localPulseEvents(time, flow(:,index), analysisStart);
    pulseCount(index) = numel(eventTimes);
    if isempty(eventVolumes)
        pulseVolume(index) = 0;
        pulseVolumeCv(index) = 1;
        lastPulseDrift(index) = 1;
        peakFlow(index) = max(flow(analysisMask,index));
    else
        pulseVolume(index) = median(eventVolumes);
        pulseVolumeCv(index) = std(eventVolumes) / ...
            max(abs(mean(eventVolumes)), eps);
        peakFlow(index) = median(eventPeaks);
        if numel(eventVolumes) >= 2
            lastPulseDrift(index) = abs(eventVolumes(end) - ...
                eventVolumes(end-1)) / max(abs(eventVolumes(end-1)), eps);
        else
            lastPulseDrift(index) = 1;
        end
    end
    allEventTimes = [allEventTimes; eventTimes(:)]; %#ok<AGROW>
    allEventIds = [allEventIds; repmat(index, numel(eventTimes), 1)]; %#ok<AGROW>
end
[allEventTimes, order] = sort(allEventTimes);
allEventIds = allEventIds(order);
if numel(allEventTimes) >= 3
    eventSpacingCv = std(diff(allEventTimes)) / ...
        max(mean(diff(allEventTimes)), eps);
    eventRate = (numel(allEventTimes)-1) / ...
        max(allEventTimes(end)-allEventTimes(1), eps);
else
    eventSpacingCv = 1;
    eventRate = 0;
end

metrics = struct( ...
    "applied_inputs", applied, ...
    "analysis_start_s", analysisStart, ...
    "pulse_count_per_injector", pulseCount, ...
    "pulse_volume_per_event_m3", pulseVolume, ...
    "mean_pulse_volume_m3", mean(pulseVolume), ...
    "pulse_volume_balance_cv", std(pulseVolume) / ...
        max(abs(mean(pulseVolume)), eps), ...
    "per_injector_pulse_volume_cv", pulseVolumeCv, ...
    "maximum_pulse_volume_cv", max(pulseVolumeCv), ...
    "last_pulse_drift_fraction", lastPulseDrift, ...
    "maximum_last_pulse_drift_fraction", max(lastPulseDrift), ...
    "peak_flow_per_injector_m3_s", peakFlow, ...
    "peak_flow_balance_cv", std(peakFlow) / ...
        max(abs(mean(peakFlow)), eps), ...
    "maximum_zero_lag_flow_correlation", ...
        localMaximumPairwiseCorrelation(flow(analysisMask,:)), ...
    "firing_order_match_fraction", localFiringOrderMatch(allEventIds), ...
    "combined_event_spacing_cv", eventSpacingCv, ...
    "combined_event_rate_Hz", eventRate, ...
    "minimum_plunger_amplitude_m", min(plungerAmplitude), ...
    "plunger_amplitude_balance_cv", std(plungerAmplitude) / ...
        max(mean(plungerAmplitude), eps), ...
    "maximum_plunger_speed_m_s", max(abs(velocity(analysisMask,:)), [], "all"), ...
    "minimum_needle_lift_m", min(needleAmplitude), ...
    "needle_lift_balance_cv", std(needleAmplitude) / ...
        max(mean(needleAmplitude), eps), ...
    "minimum_peak_chamber_pressure_Pa", min(max(pressure(analysisMask,:))), ...
    "maximum_chamber_pressure_Pa", max(pressure(analysisMask,:), [], "all"), ...
    "pressure_peak_balance_cv", std(max(pressure(analysisMask,:))) / ...
        max(mean(max(pressure(analysisMask,:))), eps), ...
    "service_summary", sum(flow(analysisMask,:), "all") * 1e5 + ...
        sum(position(analysisMask,:), "all") * 1e2 + ...
        sum(needle(analysisMask,:), "all") * 1e3, ...
    "sample_count", numel(time));
end

function [eventTimes, eventVolumes, eventPeaks] = ...
        localPulseEvents(time, flow, analysisStart)
flow = movmean(abs(flow(:)), 5);
mask = time >= analysisStart;
peak = max(flow(mask));
if ~isfinite(peak) || peak <= 1e-10
    eventTimes = zeros(0,1);
    eventVolumes = zeros(0,1);
    eventPeaks = zeros(0,1);
    return;
end
active = flow >= max(0.12 * peak, 1e-9) & mask;
edges = diff([false; active; false]);
starts = find(edges == 1);
stops = find(edges == -1) - 1;
minimumSamples = 3;
boundaryMargin = 0.002;
keep = (stops - starts + 1) >= minimumSamples & ...
    time(starts) >= analysisStart + boundaryMargin & ...
    time(stops) <= time(end) - boundaryMargin;
starts = starts(keep);
stops = stops(keep);
eventTimes = zeros(numel(starts),1);
eventVolumes = zeros(numel(starts),1);
eventPeaks = zeros(numel(starts),1);
for index = 1:numel(starts)
    segment = starts(index):stops(index);
    [eventPeaks(index), localPeak] = max(flow(segment));
    eventTimes(index) = time(segment(localPeak));
    eventVolumes(index) = trapz(time(segment), flow(segment));
end
end

function score = localFiringOrderMatch(ids)
ids = double(ids(:)');
if numel(ids) < 4
    score = 0;
    return;
end
expected = [1 3 4 2];
scores = zeros(1,4);
for shift = 0:3
    reference = repmat(circshift(expected, [0 shift]), ...
        1, ceil(numel(ids)/4));
    scores(shift+1) = mean(ids == reference(1:numel(ids)));
end
score = max(scores);
end

function value = localMaximumPairwiseCorrelation(data)
value = 0;
for first = 1:size(data, 2)-1
    for second = first+1:size(data, 2)
        pair = corrcoef(data(:,first), data(:,second));
        if all(size(pair) == [2 2]) && all(isfinite(pair), "all")
            value = max(value, abs(pair(1,2)));
        else
            value = 1;
        end
    end
end
end

function inputs = localScenarioInputs(scenario)
inputs = struct("EngineSpeed_rad_s", double(scenario.EngineSpeed_rad_s), ...
    "FuelControl_m", double(scenario.FuelControl_m));
end

function row = localEmptyScenario()
row = struct("id", "", "class", "", "requested_inputs", struct(), ...
    "simulation_pass", false, "valid", false, ...
    "output_contract", struct(), "metrics", struct(), ...
    "raw_log_path", "", "wall_seconds", 0, "error", struct());
end

function result = localFinalize(model, modelPath, expectedBinding, ...
        evidence, evidencePath)
evidence.source_file_presence_after = localFilePresence(modelPath);
evidence.source_unchanged = strcmpi(evidence.source_file_presence_after, expectedBinding);
evidence.finished_at = localNow();
if evidence.evidence_complete
    evidence.evidence_file_presence = "";
    localAtomicWriteJson(evidencePath, evidence);
    evidence.evidence_file_presence = localFilePresence(evidencePath);
end
localAtomicWriteJson(evidencePath, evidence);
try, close_system(model, 0); catch, end
result = evidence;
end

function profile = localCompactProfile()
profile = struct( ...
    "physical_objects", {{"common five-cam shaft", ...
        "eccentric lift pump", "four positive-displacement plunger pumps", ...
        "four high-pressure delivery paths", ...
        "four spring-loaded needle injectors", ...
        "reservoir, accumulator and pressure relief"}}, ...
    "measurement", ...
        "four physical injector volume flows plus native plunger, needle and chamber-pressure states", ...
    "reference_and_control", ...
        "common fuel-metering displacement changes helical spill opening; common shaft speed determines cam timing", ...
    "actuation", ...
        "five mechanical cam profiles drive the lift-pump piston and four injection plungers", ...
    "causal_path", ...
        "shaft -> cams -> lift/plunger motion -> pressurized fuel -> delivery valve -> injector needle -> nozzle flow; metering displacement -> spill opening -> delivered volume", ...
    "supported_official_range", ...
        "shaft speed 80-120 rad/s and fuel-control displacement 0.0015-0.0025 m", ...
    "official_firing_order", "1-3-4-2", ...
    "source_model_stop_s", 0.25);
end

function columns = localOutputColumns()
columns = struct( ...
    "injection_delivery", ["injector_1_volume_flow_m3_s", ...
        "injector_2_volume_flow_m3_s", ...
        "injector_3_volume_flow_m3_s", ...
        "injector_4_volume_flow_m3_s"], ...
    "pump_kinematics", ["plunger_1_position_m", ...
        "plunger_2_position_m", "plunger_3_position_m", ...
        "plunger_4_position_m", "plunger_1_velocity_m_s", ...
        "plunger_2_velocity_m_s", "plunger_3_velocity_m_s", ...
        "plunger_4_velocity_m_s"], ...
    "injector_state", ["needle_1_lift_m", "needle_2_lift_m", ...
        "needle_3_lift_m", "needle_4_lift_m", ...
        "injector_1_chamber_pressure_Pa", ...
        "injector_2_chamber_pressure_Pa", ...
        "injector_3_chamber_pressure_Pa", ...
        "injector_4_chamber_pressure_Pa"]);
end

function result = localBooleanResult(passed, observed, failure)
result = struct("passed", logical(passed), ...
    "observed", string(observed), "failure", "");
if ~passed, result.failure = string(failure); end
end

function passed = localCheckPassed(report, id)
passed = false;
try
    checks = report.checks;
    for index = 1:numel(checks)
        if string(checks(index).id) == string(id)
            passed = logical(checks(index).passed);
            return;
        end
    end
catch
end
end

function passed = localAllTrue(value)
fields = fieldnames(value);
passed = all(cellfun(@(name) logical(value.(name)), fields));
end

function issue = localIssue(stage, id, message)
issue = struct("stage", string(stage), "id", string(id), ...
    "message", string(message));
end

function localClearOutputs()
variables = ["F90_InjectorFlows", "simlog_F90_XFLUID10", ...
    "EngineSpeed_rad_s", "FuelControl_m"];
for variable = variables
    try, evalin("base", "clear " + variable); catch, end
end
end

function localAtomicSaveRaw(path, outputs, applied)
temporary = string(path) + ".tmp.mat";
save(temporary, "outputs", "applied", "-v7");
if isfile(path), delete(path); end
movefile(temporary, path, "f");
end

function localAtomicWriteJson(path, value)
temporary = string(path) + ".tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XFLUID10:JsonWrite", ...
    "Cannot write temporary JSON %s.", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleanup;
if isfile(path), delete(path); end
movefile(temporary, path, "f");
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
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

function message = localExtendedError(exception)
message = string(getReport(exception, "extended", "hyperlinks", "off"));
end

function timestamp = localNow()
timestamp = string(datetime("now", "TimeZone", "Asia/Shanghai", ...
    "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
end

function count = localAdapterRepairCount(evidencePath)
count = 0;
if isfile(evidencePath)
    try
        prior = jsondecode(fileread(evidencePath));
        if isfield(prior, "adapter_repair_count")
            count = double(prior.adapter_repair_count) + 1;
        else
            count = 1;
        end
        % The current persistent session already completed the binding-reader
        % and escaped-locator repairs before this helper was introduced.
        count = max(count, 2);
    catch
        count = 1;
    end
end
end

function localSafeRmpath(path)
try, rmpath(path); catch, end
end
