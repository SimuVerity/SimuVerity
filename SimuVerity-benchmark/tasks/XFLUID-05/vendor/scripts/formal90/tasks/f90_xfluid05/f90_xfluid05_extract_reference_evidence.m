function result = f90_xfluid05_extract_reference_evidence(modelPath, outputDir, evaluationMode)
% Fixed-evidence adapter for the pinned R2025a five-piston pump.
% This file extracts physical evidence only. Score decisions stay offline.

repo = localProjectRoot();
if nargin < 3, evaluationMode = "reference"; end
taskDir = string(getenv("SIMUVERITY_TASK_ROOT"));
sourceDir = fullfile(taskDir, "reference", "source");
if strcmpi(string(evaluationMode), "reference")
    sourceDir = string(getenv("SIMUVERITY_EVALUATOR_ASSET_ROOT"));
    assert(isfolder(sourceDir), "SimuVerity:F90:XFLUID05:ReferenceAssetRoot", ...
        "Evaluator-owned reference asset root is missing.");
end
if nargin < 1 || strlength(string(modelPath)) == 0
    modelPath = fullfile(sourceDir, ...
        "PistonPumpWithLoadSensingAndPressureLimitingControl.slx");
end
generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
if strlength(generationRunId) == 0
    generationRunId = "f90_xfluid05_manual_" + string(datetime("now", ...
        "Format", "yyyyMMdd'T'HHmmss"));
end
if nargin < 2 || strlength(string(outputDir)) == 0
    outputDir = fullfile(repo, "results", "cross_domain", ...
        "simuverity_public", "F90-XFLUID-05", ...
        "fixed_evidence", generationRunId);
end
if ~isfolder(outputDir), mkdir(outputDir); end

sharedDir = fullfile(repo, "scripts", "formal90", "shared");
addpath(sharedDir, "-begin");
localConfigureIsolation();
expectedBinding = ...
    "present";
bindingBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
[~, model] = fileparts(modelPath);
evidencePath = fullfile(outputDir, "evidence.json");
official = jsondecode(fileread(simuverity_official_scenarios_path()));
if strcmpi(string(evaluationMode), "candidate")
    result = localRunCandidate(modelPath, outputDir, official, generationRunId);
    return;
end

evidence = struct( ...
    "schema", "simuverity.f90-xfluid05-evidence.v1", ...
    "task_id", "F90-XFLUID-05", ...
    "generation_run_id", generationRunId, ...
    "model_path", string(modelPath), ...
    "source_file_presence_before", bindingBefore, ...
    "reference_direct_golden", isReference, ...
    "reference_substantive_modifications", 0, ...
    "reference_runtime_changes", ...
        "in-memory exposure of three existing parameters, three signal taps and native Simscape logging only", ...
    "extraction_only", true, ...
    "contains_score_decisions", false, ...
    "evidence_complete", false, ...
    "load_pass", false, ...
    "update_pass", false, ...
    "compile_pass", false, ...
    "nominal_smoke_pass", false, ...
    "preflight", struct(), ...
    "adapter_repair_count", 0, ...
    "static_audit", struct(), ...
    "profile", localCompactProfile(), ...
    "output_columns", localOutputColumns(), ...
    "scenarios", struct([]), ...
    "errors", {{}}, ...
    "started_at", localNow());
localAtomicWriteJson(evidencePath, evidence);

try
    assert(isReference, "SimuVerity:F90:XFLUID05:ReferenceIdentity", ...
        "Pinned pump source identity differs.");
    load_system(modelPath);
    evidence.load_pass = true;
    localPrepareRuntimeModel(model);
    paths = localPaths(model);
    evidence.static_audit = localStaticAudit(model, paths);

    preflightPath = fullfile(outputDir, "preflight.json");
    evidence.preflight = localRunPreflight(model, modelPath, ...
        expectedBinding, official.scenarios(1), paths, preflightPath);
    evidence.update_pass = localCheckPassed(evidence.preflight, "model_update");
    evidence.compile_pass = localCheckPassed(evidence.preflight, "model_compile");
    localAtomicWriteJson(evidencePath, evidence);
    if ~evidence.preflight.pass
        evidence.errors{end + 1} = localIssue("preflight", "aggregate", ...
            "Full non-fail-fast preflight failed; smoke and scenarios were not started.");
        result = localFinalize(model, modelPath, expectedBinding, ...
            evidence, evidencePath);
        return;
    end

    try
        localClearOutputs();
        localApplyScenario(model, official.scenarios(1), paths);
        smokeOut = sim(model, "StopTime", "0.05", ...
            "ReturnWorkspaceOutputs", "on", "CaptureErrors", "on");
        assert(strlength(string(smokeOut.ErrorMessage)) == 0, ...
            "SimuVerity:F90:XFLUID05:SmokeSimulation", "%s", smokeOut.ErrorMessage);
        smoke = localExtractOutputs(smokeOut, 0.05, outputDir);
        smokeContract = localSmokeContract(smoke);
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
        result = localFinalize(model, modelPath, expectedBinding, ...
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
                "SimuVerity:F90:XFLUID05:ScenarioSimulation", "%s", ...
                simOut.ErrorMessage);
            outputs = localExtractOutputs(simOut, ...
                official.simulation.stop_s, outputDir);
            contract = localOutputContract(outputs, official.simulation.stop_s);
            metrics = localMetrics(outputs, scenario, applied);
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
result = localFinalize(model, modelPath, expectedBinding, evidence, evidencePath);
end

function evidence = localRunCandidate(modelPath, outputDir, official, generationRunId)
[~,model]=fileparts(modelPath); model=string(model);
evidencePath=fullfile(outputDir,"evidence.json");
evidence=struct("schema","simuverity.f90-xfluid05-evidence.v1", ...
    "task_id","F90-XFLUID-05","generation_run_id",generationRunId, ...
    "model_path",string(modelPath),"source_file_presence_before",localFilePresence(modelPath), ...
    "reference_direct_golden",false,"evaluation_subject","candidate", ...
    "extraction_only",true,"contains_score_decisions",false, ...
    "evidence_complete",false,"load_pass",false,"update_pass",false, ...
    "compile_pass",false,"nominal_smoke_pass",false,"static_audit",struct, ...
    "profile",localCompactProfile(),"output_columns",localOutputColumns(), ...
    "scenarios",struct([]),"errors",{{}},"started_at",localNow());
try
    addpath(fileparts(modelPath),"-begin"); load_system(modelPath);
    evidence.load_pass=true;
    localApplyCandidateScenario(official.scenarios(1));
    set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on", ...
        "LimitDataPoints","off","SimulationCommand","update");
    evidence.update_pass=true;
    feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    evidence.compile_pass=true; evidence.static_audit=localCandidateStaticAudit(model);
    smokeOut=sim(model,"StopTime","0.05","ReturnWorkspaceOutputs","on");
    evidence.nominal_smoke_pass=localAllTrue(localSmokeContract( ...
        localExtractCandidateOutputs(smokeOut)));
    rows=repmat(localEmptyScenario(),numel(official.scenarios),1);
    for index=1:numel(official.scenarios)
        scenario=official.scenarios(index); row=localEmptyScenario();
        row.id=string(scenario.id); row.class=string(scenario.class);
        row.requested_inputs=localScenarioInputs(scenario);
        try
            applied=localApplyCandidateScenario(scenario);
            simOut=sim(model,"StopTime",string(official.simulation.stop_s), ...
                "ReturnWorkspaceOutputs","on");
            outputs=localExtractCandidateOutputs(simOut);
            row.output_contract=localOutputContract(outputs,official.simulation.stop_s);
            row.metrics=localMetrics(outputs,scenario,applied);
            row.simulation_pass=true; row.valid=localAllTrue(row.output_contract);
        catch exception
            row.error=localIssue("scenario",string(exception.identifier),exception.message);
        end
        rows(index)=row;
    end
    evidence.scenarios=rows;
    evidence.evidence_complete=evidence.load_pass&&evidence.update_pass&& ...
        evidence.compile_pass&&evidence.nominal_smoke_pass&& ...
        evidence.static_audit.core_path_qualified&&all([rows.valid]);
catch exception
    evidence.errors{end+1}=localIssue("session",string(exception.identifier),exception.message);
end
try, close_system(model,0); catch, end
localAtomicWriteJson(evidencePath,evidence);
end

function applied=localApplyCandidateScenario(scenario)
names=["PumpSpeed_rpm","FlowDemandScale","LoadOpeningScale"];
for name=names, assignin("base",name,double(scenario.(name))); end
applied=localScenarioInputs(scenario);
end

function outputs=localExtractCandidateOutputs(simOut)
service=localCandidateTs(simOut,"pump_service",3);
control=localCandidateTs(simOut,"control_state",3);
pistons=localCandidateTs(simOut,"piston_kinematics",10);
time=service.time;
outputs=struct("time_s",time,"pump_service",service.values, ...
    "control_state",localInterpolate(control,time), ...
    "piston_kinematics",localInterpolate(pistons,time), ...
    "native_paths",struct("adapter","candidate_public_timeseries_contract"));
end

function output=localCandidateTs(simOut,name,width)
value=simuverity_public_output_compatibility( ...
 simOut,string(name),width,AllowBaseWorkspace=true);
raw=squeeze(double(value.Data)); if isvector(raw),raw=raw(:);end
if size(raw,1)~=numel(value.Time)&&size(raw,2)==numel(value.Time),raw=raw';end
assert(size(raw,2)==width&&all(isfinite(raw),"all"));
output=struct("time",double(value.Time(:)),"values",raw);
end

function audit=localCandidateStaticAudit(model)
inventory=localCandidateInventory(model);
source=inventory.source_file; maskType=inventory.mask_type;
blockType=inventory.block_type;

swash=localCandidateSourceMatch(source, ...
    "pumps_motors.auxiliary_components.swash_plate");
valvePlate=localCandidateSourceMatch(source, ...
    "pumps_motors.auxiliary_components.valve_plate_orifice");
converter=localCandidateSourceMatch(source, ...
    "elements.translational_mechanical_converter");
mass=localCandidateSourceMatch(source, "mechanical.translational.mass");
angularSource=localCandidateSourceMatch(source, ...
    "mechanical.sources.angular_velocity");
pressureSource=localCandidateSourceMatch(source, ...
    "isothermal_liquid.sources.pressure_source");
flowSensor=localCandidateSourceMatch(source, ...
    "isothermal_liquid.sensors.flow_rate_sensor");
reservoir=localCandidateSourceMatch(source, ...
    "isothermal_liquid.elements.reservoir");
chamber=localCandidateSourceMatch(source, ...
    "isothermal_liquid.elements.constant_volume_chamber");
plainOrifice=localCandidateSourceMatch(source, ...
    "valves_orifices.orifices.orifice");
pilotActuator=localCandidateSourceMatch(source, ...
    "valve_actuators_forces.pilot_valve_actuator");
spoolOrifice=localCandidateSourceMatch(source, ...
    "valves_orifices.orifices.spool_orifice");
pressureSensor=localCandidateSourceMatch(source, ...
    "isothermal_liquid.sensors.pressure_sensor");
simulinkToPhysical=contains(lower(maskType),"simulink-ps");
profileSource=strcmpi(blockType,"Lookup_n-D")|strcmpi(blockType,"FromWorkspace");

% A piston branch is identified by actual Simscape component identity and
% direct physical-network membership.  User-chosen block names are never
% consulted.  The control cylinder is therefore not mistaken for a piston.
pistonBranch=false(size(converter));
for index=find(converter(:))'
    pistonBranch(index)= ...
        localCandidateConnectedCount(inventory,index,swash)>=1&& ...
        localCandidateConnectedCount(inventory,index,mass)>=1&& ...
        localCandidateConnectedCount(inventory,index,valvePlate)>=2;
end
fivePistons=sum(pistonBranch)>=5&&sum(swash)>=5&&sum(valvePlate)>=10;

boosterToPump=false;
for index=find(pressureSource(:))'
    boosterToPump=boosterToPump|| ...
        localCandidateConnectedCount(inventory,index,valvePlate)>=5;
end
pumpToFlowSensor=false;
for index=find(flowSensor(:))'
    pumpToFlowSensor=pumpToFlowSensor|| ...
        localCandidateConnectedCount(inventory,index,valvePlate)>=5;
end

profileToPhysicalOrifice=false;
loadOrificeToReservoir=false;
flowSensorToMeter=false;
for index=find(plainOrifice(:))'
    converterDriven=inventory.physical_port_count(index)>=3&& ...
        localCandidateConnectedCount(inventory,index,simulinkToPhysical)>=1;
    if converterDriven
        driverIndex=find(ismember(inventory.blocks,inventory.neighbors{index})& ...
            simulinkToPhysical);
        for driver=driverIndex(:)'
            profileToPhysicalOrifice=profileToPhysicalOrifice|| ...
                localCandidateConnectedCount(inventory,driver,profileSource)>=1;
        end
    end
    loadOrificeToReservoir=loadOrificeToReservoir|| ...
        (converterDriven&& ...
        localCandidateConnectedCount(inventory,index,reservoir)>=1);
    flowSensorToMeter=flowSensorToMeter|| ...
        localCandidateConnectedCount(inventory,index,flowSensor)>=1;
end
realFluidPowerPath=boosterToPump&&pumpToFlowSensor&& ...
    flowSensorToMeter&&loadOrificeToReservoir;

shaftSpeedDrivesPump=false;
for index=find(angularSource(:))'
    shaftSpeedDrivesPump=shaftSpeedDrivesPump|| ...
        localCandidateConnectedCount(inventory,index,swash)>=5;
end

pilotOnOutlet=0; pilotToSpool=0;
for index=find(pilotActuator(:))'
    pilotOnOutlet=pilotOnOutlet+double( ...
        localCandidateConnectedCount(inventory,index,valvePlate)>=5|| ...
        localCandidateConnectedCount(inventory,index,flowSensor)>=1);
    pilotToSpool=pilotToSpool+double( ...
        localCandidateConnectedCount(inventory,index,spoolOrifice)>=1);
end
controlConverterToYoke=false;
for index=find(converter(:)&~pistonBranch(:))'
    controlConverterToYoke=controlConverterToYoke|| ...
        (localCandidateConnectedCount(inventory,index,swash)>=5&& ...
        localCandidateConnectedCount(inventory,index,chamber)>=1);
end
pressureToYoke=pilotOnOutlet>=2&&pilotToSpool>=2&& ...
    controlConverterToYoke&&sum(pressureSensor)>=2;

corePath=fivePistons&&realFluidPowerPath&&profileToPhysicalOrifice&& ...
    shaftSpeedDrivesPump&&pressureToYoke;
audit=struct( ...
    "audit_method","f90-xfluid05-name-neutral-structure", ...
    "candidate_structure_scan",true, ...
    "five_physical_pistons",fivePistons, ...
    "real_fluid_power_path",realFluidPowerPath, ...
    "load_profile_drives_real_orifice",profileToPhysicalOrifice, ...
    "shaft_speed_drives_pump",shaftSpeedDrivesPump, ...
    "pressure_to_yoke_control_path",pressureToYoke, ...
    "core_path_qualified",corePath, ...
    "component_counts",struct( ...
        "qualified_piston_branches",sum(pistonBranch), ...
        "swash_plates",sum(swash),"valve_plate_orifices",sum(valvePlate), ...
        "pilot_actuators",sum(pilotActuator),"spool_orifices",sum(spoolOrifice), ...
        "pressure_sensors",sum(pressureSensor)), ...
    "path_checks",struct( ...
        "booster_to_piston_inlets",boosterToPump, ...
        "piston_outlets_to_flow_sensor",pumpToFlowSensor, ...
        "flow_sensor_to_metering_orifice",flowSensorToMeter, ...
        "variable_load_orifice_to_reservoir",loadOrificeToReservoir, ...
        "two_pressure_control_branches",pilotOnOutlet>=2&&pilotToSpool>=2, ...
        "control_converter_to_five_swash_plates",controlConverterToYoke));
end

function inventory=localCandidateInventory(model)
blocks=string(find_system(model,"SearchDepth",1,"FollowLinks","on", ...
    "LookUnderMasks","all","Type","Block"));
blocks=blocks(:); count=numel(blocks);
sourceFile=strings(count,1); maskType=strings(count,1);
blockType=strings(count,1); physicalPortCount=zeros(count,1);
neighbors=cell(count,1);
for index=1:count
    block=blocks(index);
    sourceFile(index)=localCandidateBlockParam(block,"SourceFile");
    maskType(index)=localCandidateBlockParam(block,"MaskType");
    blockType(index)=localCandidateBlockParam(block,"BlockType");
    portHandles=get_param(block,"PortHandles"); physical=[];
    if isfield(portHandles,"LConn"),physical=[physical;portHandles.LConn(:)];end
    if isfield(portHandles,"RConn"),physical=[physical;portHandles.RConn(:)];end
    physicalPortCount(index)=numel(physical);
    connected=strings(0,1);
    portConnectivity=get_param(block,"PortConnectivity");
    for portIndex=1:numel(portConnectivity)
        handles=[portConnectivity(portIndex).SrcBlock(:); ...
            portConnectivity(portIndex).DstBlock(:)];
        for handle=reshape(handles,1,[])
            if handle>0
                try, connected(end+1,1)=string(getfullname(handle)); catch, end %#ok<AGROW>
            end
        end
    end
    neighbors{index}=unique(connected,"stable");
end
inventory=struct("blocks",blocks,"source_file",lower(sourceFile), ...
    "mask_type",maskType,"block_type",blockType, ...
    "physical_port_count",physicalPortCount,"neighbors",{neighbors});
end

function value=localCandidateBlockParam(block,name)
value="";
try, value=string(get_param(block,name)); catch, end
end

function matched=localCandidateSourceMatch(source,patterns)
matched=false(size(source));
for pattern=string(patterns(:))'
    matched=matched|contains(lower(source),lower(pattern));
end
end

function count=localCandidateConnectedCount(inventory,index,targetMask)
connected=ismember(inventory.blocks,inventory.neighbors{index});
count=sum(connected&targetMask(:));
end

function localPrepareRuntimeModel(model)
set_param(model, ...
    "SimulationMode", "normal", ...
    "ReturnWorkspaceOutputs", "on", ...
    "LimitDataPoints", "off", ...
    "SimscapeLogType", "all", ...
    "SimscapeLogName", "simlog_F90_XFLUID05", ...
    "SimscapeLogLimitData", "off");
set(groot, "defaultFigureVisible", "off");
paths = localPaths(model);
localInstallTap(model, paths.load_from, "F90_LoadOpening", 1);
localInstallTap(model, paths.yoke_from, "F90_YokePosition", 2);
localInstallTap(model, paths.flow_from, "F90_DeliveredFlow", 3);
end

function report = localRunPreflight(model, modelPath, expectedBinding, ...
        nominal, paths, reportPath)
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
        @() localBooleanResult(strcmpi(localFilePresence(modelPath), expectedBinding), ...
        localFilePresence(modelPath), "Pinned source binding differs."));
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
    localCheckDef("bus_contract", "bus", ...
        @() localCheckBusContract(paths, compilePass, compileDetail));
    localCheckDef("logging_contract", "logging", @() localCheckLogging(model));
    localCheckDef("runtime_path_contract", "path", ...
        @() localCheckRuntimePath(reportPath));
    localCheckDef("api_contract", "api", @() localCheckApis());
    localCheckDef("causal_path_contract", "locator", ...
        @() localBooleanResult(audit.core_path_qualified, ...
        "core_path_qualified", ...
        "Required five-piston pump and pressure-to-yoke path is incomplete."))
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
required = ["PumpSpeed_rpm", "FlowDemandScale", "LoadOpeningScale"];
present = arrayfun(@(name) evalin("base", ...
    "exist('" + name + "','var') == 1"), required);
valid = arrayfun(@(name) isvarname(char(name)) && ...
    ~iskeyword(char(name)) && strlength(name) <= namelengthmax, required);
result = localBooleanResult(all(present) && all(valid), ...
    "present=" + sum(present) + "/3;valid_names=" + sum(valid) + "/3", ...
    "Required workspace inputs are absent or invalid.");
end

function paths = localPaths(model)
paths = struct( ...
    "pump", model + "/Axial-Piston Pump", ...
    "booster", model + "/Booster" + newline + "Pump", ...
    "pipe", model + "/Pipe (IL)", ...
    "control", model + "/Pressure//Flow Control Unit", ...
    "flow_sensor", model + "/Flow Sensor", ...
    "load_orifice", model + "/Load" + newline + "Orifice", ...
    "reservoir", model + "/Reservoir (IL)", ...
    "speed", model + "/Pump" + newline + "Speed", ...
    "shaft_source", model + "/Ideal Angular" + newline + "Velocity Source", ...
    "load_profile", model + "/Spool Pos", ...
    "opening", model + "/Spool Pos/Opening", ...
    "load_converter", model + "/Simulink-PS" + newline + "Converter", ...
    "load_from", model + "/From", ...
    "yoke_from", model + "/From1", ...
    "flow_from", model + "/From2", ...
    "flow_orifice", model + "/Pressure//Flow Control Unit/Flow Control Orifice", ...
    "pilot", model + "/Pressure//Flow Control Unit/Pilot Valve" + newline + "Actuator", ...
    "directional", model + "/Pressure//Flow Control Unit/3-Way Directional" + newline + "Valve", ...
    "servo", model + "/Pressure//Flow Control Unit/Servo Cylinder", ...
    "relief", model + "/Pressure//Flow Control Unit/Pressure Relief" + newline + "Valve (IL)");
paths.pistons = strings(5, 1);
paths.cylinders = strings(5, 1);
paths.swash = strings(5, 1);
for index = 1:5
    paths.pistons(index) = paths.pump + "/Piston " + index;
    paths.cylinders(index) = paths.pistons(index) + "/Piston Cylinder";
    paths.swash(index) = paths.pistons(index) + "/Swash Plate";
end
end

function result = localCheckLocators(paths)
core = [paths.pump, paths.booster, paths.pipe, paths.control, ...
    paths.flow_sensor, paths.load_orifice, paths.reservoir, paths.speed, ...
    paths.shaft_source, paths.load_profile, paths.opening, ...
    paths.load_converter, ...
    paths.load_from, paths.yoke_from, paths.flow_from, ...
    paths.flow_orifice, paths.pilot, paths.directional, paths.servo, ...
    paths.relief, paths.pistons', paths.cylinders', paths.swash'];
present = arrayfun(@(path) getSimulinkBlockHandle(path, false) > 0, core);
result = localBooleanResult(all(present), ...
    "present=" + sum(present) + "/" + numel(core), ...
    "A required source locator is missing.");
end

function result = localCheckPorts(paths)
signals = [paths.load_from, paths.yoke_from, paths.flow_from];
signalPass = true;
for block = signals
    handles = get_param(block, "PortHandles");
    signalPass = signalPass && numel(handles.Outport) == 1;
end
pump = get_param(paths.pump, "PortHandles");
control = get_param(paths.control, "PortHandles");
physicalPass = localConservingCount(pump) >= 4 && ...
    localConservingCount(control) >= 4;
result = localBooleanResult(signalPass && physicalPass, ...
    "signal_outputs=3/3;pump_conserving=" + localConservingCount(pump) + ...
    ";control_conserving=" + localConservingCount(control), ...
    "Required signal or conserving ports are unavailable.");
end

function count = localConservingCount(handles)
count = 0;
for field = ["LConn", "RConn"]
    if isfield(handles, field)
        count = count + numel(handles.(char(field)));
    end
end
end

function result = localCheckCompiledDimensions(paths, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
blocks = [paths.load_from, paths.yoke_from, paths.flow_from];
observed = strings(size(blocks));
passed = true;
for index = 1:numel(blocks)
    dims = get_param(blocks(index), "CompiledPortDimensions");
    encoded = double(dims.Outport(:));
    observed(index) = mat2str(encoded');
    passed = passed && ~isempty(encoded) && ...
        all(isfinite(encoded)) && ~any(encoded == -1);
end
result = localBooleanResult(passed, join(observed, ";"), ...
    "One or more compiled dimensions are unresolved.");
end

function result = localCheckCompiledTypes(paths, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
blocks = [paths.load_from, paths.yoke_from, paths.flow_from];
types = strings(size(blocks));
passed = true;
for index = 1:numel(blocks)
    value = get_param(blocks(index), "CompiledPortDataTypes");
    types(index) = string(value.Outport{1});
    passed = passed && strlength(types(index)) > 0;
end
result = localBooleanResult(passed, join(types, ","), ...
    "One or more compiled types are unresolved.");
end

function result = localCheckBusContract(paths, compilePass, detail)
if ~compilePass
    result = localBooleanResult(false, "compile_unavailable", detail);
    return;
end
blocks = [paths.load_from, paths.yoke_from, paths.flow_from];
types = strings(size(blocks));
for index = 1:numel(blocks)
    value = get_param(blocks(index), "CompiledPortDataTypes");
    types(index) = string(value.Outport{1});
end
result = localBooleanResult(all(~startsWith(types, "Bus:")), ...
    join(types, ","), "Required evidence signal unexpectedly compiles as a bus.");
end

function result = localCheckLogging(model)
names = ["LoadOpening", "YokePosition", "DeliveredFlow"];
present = arrayfun(@(name) getSimulinkBlockHandle( ...
    model + "/__F90_" + name, false) > 0, names);
variables = "F90_" + names;
valid = arrayfun(@(name) isvarname(char(name)) && ...
    strlength(name) <= namelengthmax, variables);
result = localBooleanResult(all(present) && all(valid), ...
    "bound=" + sum(present) + "/3", ...
    "Required non-invasive signal taps are unavailable.");
end

function result = localCheckRuntimePath(reportPath)
paths = [string(reportPath), string(getenv("MATLAB_PREFDIR")), ...
    string(getenv("SIMULINK_CACHE_FOLDER")), ...
    string(getenv("SIMULINK_CODEGEN_FOLDER"))];
lengths = strlength(paths);
result = localBooleanResult(all(lengths > 0) && max(lengths) < 220, ...
    "lengths=" + join(string(lengths), ","), ...
    "Runtime path is empty or unsafe for the Windows worker.");
end

function result = localCheckApis()
names = ["formal90_nonfailfast_preflight", "sim", "jsonencode", ...
    "timeseries", "interp1", "Simulink.fileGenControl"];
present = arrayfun(@(name) ~isempty(which(name)), names);
result = localBooleanResult(all(present), join(names(present), ","), ...
    "One or more required APIs are unavailable.");
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

function applied = localApplyScenario(model, scenario, paths)
speed = double(scenario.PumpSpeed_rpm);
flowScale = double(scenario.FlowDemandScale);
loadScale = double(scenario.LoadOpeningScale);
assignin("base", "PumpSpeed_rpm", speed);
assignin("base", "FlowDemandScale", flowScale);
assignin("base", "LoadOpeningScale", loadScale);
set_param(paths.speed, "constant", num2str(speed, 15));
set_param(paths.control, "orifice_opening", ...
    num2str(0.00265 * flowScale, 17));
    % The native repeating-sequence mask keeps a terminal point at 3 s even
    % though this task stops at 1.5 s; output and time vectors must stay equal.
    profile = loadScale * [2 2 5 5 7 7 3 3 1 1 4 4 2] * 1e-3;
set_param(paths.opening, "rep_seq_y", mat2str(profile, 17));
set_param(model, "StopTime", "1.5");
applied = struct( ...
    "PumpSpeed_rpm", speed, ...
    "FlowDemandScale", flowScale, ...
    "LoadOpeningScale", loadScale, ...
    "flow_control_orifice_opening_m", 0.00265 * flowScale, ...
    "load_opening_profile_m", profile);
end

function localInstallTap(parent, source, variable, index)
assert(getSimulinkBlockHandle(source, false) > 0, ...
    "SimuVerity:F90:XFLUID05:TapSource", "Missing tap source %s.", source);
tap = parent + "/__F90_" + erase(variable, "F90_");
if getSimulinkBlockHandle(tap, false) < 0
    add_block("simulink/Sinks/To Workspace", tap, ...
        "VariableName", variable, "SaveFormat", "Timeseries", ...
        "MaxDataPoints", "inf", ...
        "Position", [700, 390 + 40*index, 845, 415 + 40*index]);
    sourceHandles = get_param(source, "PortHandles");
    tapHandles = get_param(tap, "PortHandles");
    add_line(parent, sourceHandles.Outport(1), tapHandles.Inport(1), ...
        "autorouting", "on");
end
end

function outputs = localExtractOutputs(simOut, stopTime, outputDir)
loadOpening = localTimeseries(simOut, "F90_LoadOpening");
yoke = localTimeseries(simOut, "F90_YokePosition");
flow = localTimeseries(simOut, "F90_DeliveredFlow");
simlog = localGetSimlog(simOut);

[pressureA, pressureAPath] = localFirstNative(simlog, {
    ["Pressure_Flow_Control_Unit", "Flow_Control_Orifice", "A", "p"], ...
    ["Pipe_IL", "p_I"], ...
    ["Flow_Sensor", "Flow_Rate_Sensor_IL", "A", "p"]}, "Pa");
[pressureB, pressureBPath] = localFirstNative(simlog, {
    ["Pressure_Flow_Control_Unit", "Flow_Control_Orifice", "B", "p"], ...
    ["Flow_Sensor", "Flow_Rate_Sensor_IL", "B", "p"], ...
    ["Load_Orifice", "A", "p"]}, "Pa");
[spool, spoolPath] = localFirstNative(simlog, {
    ["Pressure_Flow_Control_Unit", "x3_Way_Directional_Valve", "S"], ...
    ["Pressure_Flow_Control_Unit", "Pilot_Valve_Actuator", "S"], ...
    ["Pressure_Flow_Control_Unit", "Servo_Cylinder", "hard_stop", "x"]}, "m");

pistons = cell(5, 1);
pistonPaths = strings(5, 1);
for index = 1:5
    pistonName = "Piston_" + index;
    [pistons{index}, pistonPaths(index)] = localFirstNative(simlog, {
        ["Axial_Piston_Pump", pistonName, "Piston_Cylinder", "hard_stop", "x"], ...
        ["Axial_Piston_Pump", pistonName, "Piston_Cylinder", ...
            "chamber", "interface_displacement"], ...
        ["Axial_Piston_Pump", pistonName, "Swash_Plate", ...
            "actuator_displacement"]}, "m");
end
missing = isempty(pressureA.time) || isempty(pressureB.time) || ...
    isempty(spool.time) || any(cellfun(@(item) isempty(item.time), pistons));
if missing
    inventory = localSimlogInventory(simlog, 6, 700);
    localAtomicWriteJson(fullfile(outputDir, "native_inventory.json"), ...
        struct("pressure_A_path", pressureAPath, ...
        "pressure_B_path", pressureBPath, "spool_path", spoolPath, ...
        "piston_paths", pistonPaths, "inventory", inventory));
    error("SimuVerity:F90:XFLUID05:NativeLocator", ...
        "One or more required native Simscape series are unresolved; inspect native_inventory.json.");
end

time = linspace(0, double(stopTime), ...
    max(3, round(1000 * double(stopTime)) + 1))';
position = zeros(numel(time), 5);
for index = 1:5
    position(:, index) = localInterpolate(pistons{index}, time);
end
velocity = zeros(size(position));
for index = 1:5
    velocity(:, index) = gradient(position(:, index), time);
end
outputs = struct( ...
    "time_s", time, ...
    "pump_service", [localInterpolate(loadOpening, time), ...
        localInterpolate(flow, time), ...
        localInterpolate(pressureA, time)], ...
    "control_state", [localInterpolate(yoke, time), ...
        localInterpolate(pressureA, time) - ...
        localInterpolate(pressureB, time), ...
        localInterpolate(spool, time)], ...
    "piston_kinematics", [position, velocity], ...
    "native_paths", struct( ...
        "pressure_A", pressureAPath, "pressure_B", pressureBPath, ...
        "pilot_spool", spoolPath, "pistons", pistonPaths));
end

function simlog = localGetSimlog(simOut)
simlog = [];
try, simlog = simOut.get("simlog_F90_XFLUID05"); catch, end
if isempty(simlog)
    try, simlog = evalin("base", "simlog_F90_XFLUID05"); catch, end
end
assert(~isempty(simlog), "SimuVerity:F90:XFLUID05:Simlog", ...
    "Required native Simscape log is missing.");
end

function [output, path] = localFirstNative(root, candidates, unit)
output = struct("time", [], "values", []);
path = "";
for index = 1:numel(candidates)
    ids = string(candidates{index});
    node = root;
    try
        for part = ids
            node = node.(char(part));
        end
        native = node.series;
        time = double(native.time);
        values = double(native.values(char(unit)));
        time = time(:);
        values = squeeze(values);
        if isvector(values), values = values(:); end
        if numel(time) >= 2 && size(values, 1) == numel(time) && ...
                size(values, 2) == 1 && all(isfinite(time)) && ...
                all(isfinite(values), "all")
            output = struct("time", time, "values", values);
            path = join(ids, ".");
            return;
        end
    catch
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
assert(isa(value, "timeseries"), "SimuVerity:F90:XFLUID05:Timeseries", ...
    "Required output %s is not a Timeseries.", variable);
raw = squeeze(double(value.Data));
if isvector(raw), raw = raw(:); end
if size(raw, 1) ~= numel(value.Time) && size(raw, 2) == numel(value.Time)
    raw = raw.';
end
assert(size(raw, 1) == numel(value.Time) && size(raw, 2) == 1, ...
    "SimuVerity:F90:XFLUID05:TimeseriesShape", ...
    "Required output %s has unexpected dimensions.", variable);
output = struct("time", double(value.Time(:)), "values", raw);
end

function values = localInterpolate(series, time)
[sourceTime, indices] = unique(double(series.time(:)), "stable");
sourceValues = double(series.values(indices, :));
assert(~isempty(sourceTime) && all(isfinite(sourceTime)) && ...
    all(isfinite(sourceValues), "all"), ...
    "SimuVerity:F90:XFLUID05:Interpolation", "Required series is invalid.");
if numel(sourceTime) == 1
    values = repmat(sourceValues(1, :), numel(time), 1);
else
    values = interp1(sourceTime, sourceValues, time, "linear", "extrap");
end
end

function contract = localSmokeContract(outputs)
contract = struct( ...
    "time_nonempty", numel(outputs.time_s) >= 2, ...
    "time_starts_at_zero", abs(outputs.time_s(1)) <= 1e-9, ...
    "time_reaches_smoke_end", outputs.time_s(end) >= 0.049, ...
    "service_width_3", size(outputs.pump_service, 2) == 3, ...
    "control_width_3", size(outputs.control_state, 2) == 3, ...
    "piston_width_10", size(outputs.piston_kinematics, 2) == 10, ...
    "all_finite", all(isfinite([outputs.pump_service(:); ...
        outputs.control_state(:); outputs.piston_kinematics(:)])));
end

function contract = localOutputContract(outputs, stopTime)
contract = struct( ...
    "time_strictly_increasing", all(diff(outputs.time_s) > 0), ...
    "time_starts_at_zero", abs(outputs.time_s(1)) <= 1e-9, ...
    "complete_interval", outputs.time_s(end) >= double(stopTime) - 1e-6, ...
    "sample_count_sufficient", numel(outputs.time_s) >= 1001, ...
    "service_width_3", size(outputs.pump_service, 2) == 3, ...
    "control_width_3", size(outputs.control_state, 2) == 3, ...
    "piston_width_10", size(outputs.piston_kinematics, 2) == 10, ...
    "all_finite", all(isfinite([outputs.pump_service(:); ...
        outputs.control_state(:); outputs.piston_kinematics(:)])));
end

function metrics = localMetrics(outputs, scenario, applied)
time = outputs.time_s;
opening = outputs.pump_service(:, 1);
flow = outputs.pump_service(:, 2);
pressure = outputs.pump_service(:, 3);
yoke = outputs.control_state(:, 1);
deltaP = outputs.control_state(:, 2);
spool = outputs.control_state(:, 3);
position = outputs.piston_kinematics(:, 1:5);
velocity = outputs.piston_kinematics(:, 6:10);
windows = [0.30 0.43; 0.60 0.73; 0.85 0.98; 1.13 1.23; 1.34 1.48];
flowMean = zeros(1, size(windows, 1));
flowRipple = zeros(size(flowMean));
pressureMean = zeros(size(flowMean));
deltaPMean = zeros(size(flowMean));
yokeMean = zeros(size(flowMean));
for index = 1:size(windows, 1)
    mask = time >= windows(index, 1) & time <= windows(index, 2);
    flowMean(index) = mean(flow(mask));
    flowRipple(index) = std(flow(mask)) / max(abs(flowMean(index)), 1e-9);
    pressureMean(index) = mean(pressure(mask));
    deltaPMean(index) = mean(deltaP(mask));
    yokeMean(index) = mean(yoke(mask));
end
phasors = zeros(1, 5);
omega = 2*pi*double(scenario.PumpSpeed_rpm)/60;
phaseMask = time >= 0.55 & time <= 0.95;
phaseTime = time(phaseMask);
for index = 1:5
    signal = position(phaseMask, index);
    signal = signal - mean(signal);
    phasors(index) = sum(signal .* exp(-1i*omega*phaseTime));
end
phases = sort(mod(angle(phasors), 2*pi));
gaps = diff([phases, phases(1) + 2*pi]);
phaseUniformity = sqrt(mean((rad2deg(gaps) - 72).^2));
amplitudes = 0.5*(max(position(phaseMask, :), [], 1) - ...
    min(position(phaseMask, :), [], 1));
transitionTimes = [0.25 0.55 0.80 1.10 1.30];
settling = zeros(size(transitionTimes));
for index = 1:numel(transitionTimes)
    startTime = transitionTimes(index);
    stop = windows(index, 2);
    targetMask = time >= stop - 0.04 & time <= stop;
    target = mean(flow(targetMask));
    band = max(0.08*abs(target), 5e-5);
    candidates = find(time >= startTime & time <= stop);
    settling(index) = stop - startTime;
    for positionIndex = candidates'
        remainder = candidates(candidates >= positionIndex);
        if all(abs(flow(remainder) - target) <= band)
            settling(index) = time(positionIndex) - startTime;
            break;
        end
    end
end
metrics = struct( ...
    "simulation_end_s", time(end), ...
    "steady_window_flow_m3_s", flowMean, ...
    "steady_window_flow_ripple_fraction", flowRipple, ...
    "steady_window_pressure_Pa", pressureMean, ...
    "steady_window_flow_control_delta_pressure_Pa", deltaPMean, ...
    "steady_window_yoke_position_m", yokeMean, ...
    "maximum_outlet_pressure_Pa", max(pressure), ...
    "minimum_outlet_pressure_Pa", min(pressure), ...
    "maximum_abs_flow_m3_s", max(abs(flow)), ...
    "maximum_flow_ripple_fraction", max(flowRipple), ...
    "mean_load_sensing_delta_pressure_Pa", mean(deltaPMean([1 2 3 5])), ...
    "pressure_limited_flow_m3_s", flowMean(4), ...
    "nonlimited_mean_flow_m3_s", mean(flowMean([1 2 3 5])), ...
    "pressure_limit_flow_reduction_fraction", ...
        max(0, 1 - flowMean(4)/max(mean(flowMean([1 2 3 5])), 1e-9)), ...
    "yoke_position_range_m", max(yoke) - min(yoke), ...
    "pilot_spool_range_m", max(spool) - min(spool), ...
    "minimum_piston_amplitude_m", min(amplitudes), ...
    "maximum_piston_amplitude_m", max(amplitudes), ...
    "piston_phase_gap_rmse_deg", phaseUniformity, ...
    "maximum_piston_speed_m_s", max(abs(velocity), [], "all"), ...
    "maximum_load_transition_settling_s", max(settling), ...
    "mean_load_transition_settling_s", mean(settling), ...
    "load_opening_summary", localSummary([time, opening]), ...
    "service_summary", localSummary([time, flow, pressure]), ...
    "control_summary", localSummary([time, yoke, deltaP, spool]), ...
    "piston_summary", localSummary([time, position, velocity]), ...
    "native_paths", outputs.native_paths, ...
    "requested_scenario_id", string(scenario.id), ...
    "applied_inputs", applied);
end

function audit = localStaticAudit(model, paths)
pistonPresent = false(5, 1);
cylinderPresent = false(5, 1);
swashPresent = false(5, 1);
for index = 1:5
    pistonPresent(index) = getSimulinkBlockHandle(paths.pistons(index), false) > 0;
    cylinderPresent(index) = localSourceFileIs(paths.cylinders(index), ...
        "fluids.isothermal_liquid.actuators.single_actuator");
    swashPresent(index) = localSourceFileIs(paths.swash(index), ...
        "fluids.isothermal_liquid.pumps_motors.auxiliary_components.swash_plate");
end
audit = struct( ...
    "five_physical_pistons", all(pistonPresent) && ...
        all(cylinderPresent) && all(swashPresent), ...
    "booster_to_pump", localConnected(paths.booster, paths.pump), ...
    "pump_to_pipe", localConnected(paths.pump, paths.pipe), ...
    "pipe_to_control", localConnected(paths.pipe, paths.control), ...
    "control_to_flow_sensor", localConnected(paths.control, paths.flow_sensor), ...
    "flow_sensor_to_load", localConnected(paths.flow_sensor, paths.load_orifice), ...
    "load_profile_drives_real_orifice", ...
        localConnected(paths.load_profile, paths.load_converter) && ...
        localConnected(paths.load_converter, paths.load_orifice), ...
    "shaft_speed_drives_pump", localConnected(paths.speed, paths.shaft_source) && ...
        localConnected(paths.shaft_source, paths.pump), ...
    "flow_control_orifice_present", localSourceFileIs(paths.flow_orifice, ...
        "fluids.isothermal_liquid.valves_orifices.orifices.spool_orifice"), ...
    "pilot_actuator_present", localSourceFileIs(paths.pilot, ...
        "fluids.isothermal_liquid.valves_orifices.valve_actuators_forces.pilot_valve_actuator"), ...
    "directional_valve_present", localSourceFileIs(paths.directional, ...
        "fluids.isothermal_liquid.valves_orifices.directional_control_valves.directional_valve_3_way"), ...
    "servo_yoke_actuator_present", localSourceFileIs(paths.servo, ...
        "fluids.isothermal_liquid.actuators.double_actuator"), ...
    "pressure_limit_valve_present", localSourceFileIs(paths.relief, ...
        "fluids.isothermal_liquid.valves_orifices.pressure_control_valves.pressure_relief_valve"), ...
    "pressure_limit_setting_25MPa", ...
        abs(str2double(get_param(paths.relief, "p_set_differential")) - 25) <= 1e-9, ...
    "six_level_load_profile", localSixLevelProfile(paths.opening), ...
    "core_path_qualified", false);
values = struct2cell(rmfield(audit, "core_path_qualified"));
audit.core_path_qualified = all(cellfun(@logical, values));
end

function passed = localSixLevelProfile(opening)
passed = false;
try
    values = eval(get_param(opening, "rep_seq_y"));
    values = values(:)';
    plateau = values([1 3 5 7 9 11]);
    passed = numel(unique(round(plateau, 9))) == 6;
catch
end
end

function passed = localSourceFileIs(path, expected)
passed = false;
try, passed = string(get_param(path, "SourceFile")) == string(expected); catch, end
end

function passed = localConnected(source, destination)
passed = false;
try
    target = getSimulinkBlockHandle(destination, false);
    connectivity = get_param(source, "PortConnectivity");
    for index = 1:numel(connectivity)
        destinations = connectivity(index).DstBlock;
        if ~isempty(destinations) && any(destinations == target)
            passed = true;
            return;
        end
    end
catch
end
end

function profile = localCompactProfile()
profile = struct( ...
    "plant", "five evenly phased single-acting Isothermal Liquid piston cylinders connected through valve-plate orifices to a driven swash-plate pump", ...
    "control", "pump outlet pressure differential mechanically pilots a three-way valve and servo cylinder that moves the swash-plate yoke; a relief branch limits pressure", ...
    "causal_path", "0.5 MPa booster -> five-piston pump -> pipe -> pressure/flow control -> flow sensor -> six-stage load orifice -> reservoir", ...
    "native_stop_time_s", 1.5, ...
    "nominal_rated_flow_m3_s", 1.1e-3, ...
    "nominal_maximum_pressure_Pa", 27e6, ...
    "official_coverage", ["nominal six loads", "lower shaft speed", ...
        "capacity boundary", "reduced flow demand", ...
        "open load", "restrictive pressure-limited load"]);
end

function columns = localOutputColumns()
columns = struct( ...
    "pump_service", ["load_orifice_opening_m", ...
        "delivered_flow_m3_s", "pump_outlet_pressure_Pa"], ...
    "control_state", ["yoke_position_m", ...
        "flow_control_differential_pressure_Pa", ...
        "pilot_valve_spool_position_m"], ...
    "piston_kinematics", ["piston_1_displacement_m", ...
        "piston_2_displacement_m", "piston_3_displacement_m", ...
        "piston_4_displacement_m", "piston_5_displacement_m", ...
        "piston_1_velocity_m_s", "piston_2_velocity_m_s", ...
        "piston_3_velocity_m_s", "piston_4_velocity_m_s", ...
        "piston_5_velocity_m_s"]);
end

function input = localScenarioInputs(scenario)
input = struct( ...
    "PumpSpeed_rpm", double(scenario.PumpSpeed_rpm), ...
    "FlowDemandScale", double(scenario.FlowDemandScale), ...
    "LoadOpeningScale", double(scenario.LoadOpeningScale));
end

function row = localEmptyScenario()
row = struct("id", "", "class", "", "requested_inputs", struct(), ...
    "simulation_pass", false, "output_contract", struct(), ...
    "metrics", struct(), "raw_log_path", "", "valid", false, ...
    "wall_seconds", 0, "error", struct());
end

function passed = localAllTrue(value)
fields = fieldnames(value);
passed = ~isempty(fields) && all(cellfun(@(name) ...
    logical(value.(name)), fields));
end

function localClearOutputs()
names = ["F90_LoadOpening", "F90_YokePosition", "F90_DeliveredFlow", ...
    "simlog_F90_XFLUID05"];
for name = names
    try, evalin("base", "clear " + name); catch, end
end
end

function result = localFinalize(model, modelPath, expectedBinding, ...
        evidence, evidencePath)
bindingAfter = localFilePresence(modelPath);
evidence.source_file_presence_after = bindingAfter;
evidence.reference_binding_preserved = strcmpi(bindingAfter, expectedBinding);
try, close_system(model, 0); catch, end
evidence.model_closed_without_save = ~bdIsLoaded(model);
evidence.finished_at = localNow();
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
fprintf("F90_XFLUID05_EVIDENCE load=%d update=%d compile=%d smoke=%d valid=%d/%d complete=%d path=%s\n", ...
    evidence.load_pass, evidence.update_pass, evidence.compile_pass, ...
    evidence.nominal_smoke_pass, validCount, ...
    numel(evidence.scenarios), evidence.evidence_complete, evidencePath);
result = evidence;
end

function localAtomicSaveRaw(path, outputs, applied)
temporary = path + ".tmp.mat";
save(temporary, "outputs", "applied", "-v7");
movefile(temporary, path, "f");
end

function localAtomicWriteJson(path, value)
temporary = path + ".tmp";
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XFLUID05:JsonOpen", ...
    "Unable to open %s.", temporary);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, "%s\n", jsonencode(value, PrettyPrint=true));
clear cleanup
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

function root = localProjectRoot()
root = fileparts(fileparts(fileparts(fileparts(fileparts( ...
    mfilename("fullpath"))))));
end

function value = localSummary(input)
flat = double(input(:));
indices = (1:numel(flat))';
value = sum(flat .* mod(indices * 7919, 104729));
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
value = string(getReport(exception, "extended", "hyperlinks", "off"));
end
