function evidence = ext_xtherm_pvtes_extract_evidence(modelPath, outDir, officialScenarios, evaluatorAssetRoot)
%EXT_XTHERM_PVTES_EXTRACT_EVIDENCE Public 11-scenario TES evaluator.
% The role boundary is deliberately explicit: candidate code is loaded only
% from modelPath, while bundled reference assets are loaded only from the
% evaluator asset root supplied by the runtime.
arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string
    evaluatorAssetRoot (1,1) string = ""
end

role = localRole();
localValidateTaskAndScenarioContract(officialScenarios);
ids = localScenarioIds(officialScenarios);
assert(numel(ids) == 11, "SimuVerity:PVTES:ScenarioCount", ...
    "EXT-XTHERM-PVTES-01 requires exactly eleven official scenarios.");
if role == "reference"
    assert(isfolder(evaluatorAssetRoot), "SimuVerity:PVTES:AssetRoot", ...
        "Reference evaluation requires SIMUVERITY_EVALUATOR_ASSET_ROOT.");
    referenceRoot=evaluatorAssetRoot;
    runtimeModel=fullfile(referenceRoot,"ResidentialBuildingTESandPVcell.slx");
    assert(isfile(runtimeModel), "SimuVerity:PVTES:ReferenceModel", ...
        "The evaluator-owned reference model is unavailable.");
    addpath(referenceRoot,"-begin");
else
    runtimeModel=modelPath;
    addpath(fileparts(modelPath));
end

assert(isfolder(outDir), "SimuVerity:PVTES:Output", "Output directory must exist.");
mkdir(fullfile(outDir,"sidecars"));
mkdir(fullfile(outDir,"receipts"));
[~,model] = fileparts(runtimeModel);
evidence = struct("schema","simuverity.ext-xtherm-pvtes-public-evidence.v1", ...
    "task_id","EXT-XTHERM-PVTES-01","role",char(role), ...
    "scenario_ids",{ids},"scenarios",struct([]),"system_observations",struct(), ...
    "all_scenarios_extracted",false,"failure_reasons",{{}});

modelLoaded = false;
try
    load_system(runtimeModel); modelLoaded = true;
    set_param(model,"SimulationCommand","update");
    feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    if role == "reference", localReferenceAdapter("install",model,struct(),[]); end
    observations = localContainerObservations(model);
    evidence.system_observations = localSystemObservations(model,role,observations);
    localWriteJson(fullfile(outDir,"sidecars","system_observations.json"),evidence.system_observations);
    rows = repmat(localScenarioRow(),numel(ids),1);
    for index=1:numel(ids)
        id=ids{index}; input=localScenario(id);
        rows(index).id=id; rows(index).input=input;
        localWriteJson(fullfile(outDir,"sidecars",id+"_input.json"),input);
        try
            evalin("base","clear tes_thermal_state_ts tes_energy_flow_ts tes_control_ts tes_eval_measurement_bias_ts TES_PUBLIC_INPUT");
            assignin("base","TES_PUBLIC_INPUT",input);
            if role == "reference", localReferenceAdapter("configure",model,input,[]); end
            simIn=Simulink.SimulationInput(model);
            if role == "candidate", simIn=simIn.setVariable("TES_PUBLIC_INPUT",input); end
            simIn=simIn.setModelParameter("StartTime","0","StopTime","86400", ...
                "ReturnWorkspaceOutputs","on","LimitDataPoints","off");
            simOut=sim(simIn);
            if role == "reference", simOut=localReferenceAdapter("collect",model,input,simOut); end
            [payload,observed]=localResolveContainers(simOut,model);
            extracted=localExtract(payload,id,role,observed);
            rows(index).status="EXTRACTED"; rows(index).evidence=extracted;
            rows(index).container_source=observed;
        catch ME
            rows(index).status="FAIL"; rows(index).failure=localException(ME);
        end
        localWriteJson(fullfile(outDir,"receipts",id+".json"),rows(index));
        localWriteJson(fullfile(outDir,"sidecars",id+".json"),rows(index));
    end
    evidence.scenarios=rows;
catch ME
    evidence.failure_reasons={localException(ME)};
end
if modelLoaded
    try, close_system(model,0); catch, end
end
if ~isempty(evidence.scenarios)
    evidence.all_scenarios_extracted=all(string({evidence.scenarios.status}) == "EXTRACTED");
end
localWriteJson(fullfile(outDir,"evidence.json"),evidence);
end

function localValidateTaskAndScenarioContract(officialScenariosPath)
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
taskPath = fullfile(taskRoot, "task.json");
assert(isfolder(taskRoot) && isfile(taskPath), ...
    "SimuVerity:PVTES:TaskBinding", ...
    "SIMUVERITY_TASK_ROOT does not contain the public task binding.");
task = jsondecode(fileread(taskPath));
expectedIds = ["baseline", "solar_low", "solar_high", "ambient_cold", ...
    "ambient_warm", "setpoint_low", "setpoint_high", ...
    "solar_nominal_timing", "solar_delayed_3h", ...
    "measurement_bias_negative", "measurement_bias_positive"];
assert(string(task.schema) == "simuverity.task.v1" && ...
    string(task.release) == "simuverity-101-v1" && ...
    string(task.task_id) == "EXT-XTHERM-PVTES-01" && ...
    string(task.collection) == "EXT" && ...
    string(task.runtime_alias) == "TESPVTES" && ...
    string(task.required_model_file) == "cand_TESPVTES.slx" && ...
    string(task.official_scenarios) == "official_scenarios.json" && ...
    string(task.extractor.kind) == "matlab_function" && ...
    string(task.extractor.path) == "extractor/run.m" && ...
    string(task.extractor.entrypoint) == "run" && ...
    string(task.extractor.implementation) == ...
        "vendor/packages/simuverity_public/tasks/EXT-XTHERM-PVTES-01/policy/ext_xtherm_pvtes_extract_evidence.m" && ...
    string(task.reference.materialization) == "bundled" && ...
    string(task.reference.path) == "reference/files" && ...
    string(task.reference.manifest) == "reference/manifest.json" && ...
    string(task.reference.status) == "COMPLETE" && ...
    string(task.reference.entrypoint) == ...
        "reference/files/ResidentialBuildingTESandPVcell.slx" && ...
    double(task.reference.expected_valid_scenarios) == 11 && ...
    isequal(string(task.reference.scenario_contract.expected_ids(:)).', ...
        expectedIds), ...
    "SimuVerity:PVTES:TaskBinding", ...
    "Public task or reference identity is missing or changed.");
officialScenariosPath = string(officialScenariosPath);
assert(isfile(officialScenariosPath), "SimuVerity:PVTES:ScenarioBinding", ...
    "Official scenario contract is unavailable.");
localScenarioIds(officialScenariosPath);
end

function role=localRole()
role=lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(role)==0, role="candidate"; end
assert(any(role == ["candidate","reference"]),"SimuVerity:PVTES:Role", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
end

function ids=localScenarioIds(pathValue)
contract=jsondecode(fileread(pathValue));
assert(isfield(contract,"scenarios"),"SimuVerity:PVTES:ScenarioContract","Scenario contract has no scenarios.");
ids=cellstr(string({contract.scenarios.id}));
ids=ids(:).';
expected={"baseline","solar_low","solar_high","ambient_cold","ambient_warm", ...
    "setpoint_low","setpoint_high","solar_nominal_timing","solar_delayed_3h", ...
    "measurement_bias_negative","measurement_bias_positive"};
assert(isequal(ids,expected),"SimuVerity:PVTES:ScenarioContract", ...
    "Official scenario identifiers or ordering differ from the current public contract.");
end

function input=localScenario(id)
t=(0:3600:86400).'; hour=t/3600;
solar=850*max(0,sin(pi*(hour-6)/12)); ambient=12+8*sin(2*pi*(hour-8)/24);
setpoint=23; bias=zeros(size(t));
switch id
    case "solar_low", solar=.5*solar;
    case "solar_high", solar=min(1000,1.2*solar);
    case "ambient_cold", ambient=ambient-5;
    case "ambient_warm", ambient=ambient+5;
    case "setpoint_low", setpoint=20;
    case "setpoint_high", setpoint=24;
    case "solar_delayed_3h", solar=[zeros(3,1);solar(1:end-3)];
    case "measurement_bias_negative", bias(t>=21600&t<43200)=-2;
    case "measurement_bias_positive", bias(t>=21600&t<43200)=2;
end
input=struct("time_s",t,"solar_irradiance_W_m2",solar, ...
    "ambient_temperature_degC",ambient,"room_setpoint_degC",setpoint, ...
    "thermal_measurement_bias_degC",bias);
end

function simOut=localReferenceAdapter(action,model,input,simOut)
if nargin<3,input=struct();end; if nargin<4,simOut=[];end
switch action
    case "install"
        control=model+"/Control"; ports=get_param(control,"PortHandles");
        assert(numel(ports.Outport)==3&&numel(ports.Inport)==4,"SimuVerity:PVTES:ReferenceTopology");
        labels={"Tpv","Troom","Tset","Ttank"};
        for k=1:4, assert(strcmp(get_param(control+"/"+labels{k},"Port"),num2str(k)),"SimuVerity:PVTES:ReferencePortMap"); end
        variables={"tes_eval_valve","tes_eval_pump_cmd","tes_eval_blower_cmd"};
        for k=1:3
            tap=model+"/tes_evaluator_tap_"+k;
            add_block("simulink/Sinks/To Workspace",tap,"VariableName", ...
                variables{k}, ...
                "SaveFormat","Timeseries","MaxDataPoints","inf");
            tapPorts=get_param(tap,"PortHandles"); add_line(model,ports.Outport(k),tapPorts.Inport,"autorouting","on");
        end
        biasPath=model+"/tes_evaluator_measurement_bias";
        add_block("simulink/Sources/From Workspace",biasPath,"VariableName", ...
            "tes_eval_measurement_bias_ts","Interpolate","on");
        biasPorts=get_param(biasPath,"PortHandles");
        for target=[2 4]
            destination=ports.Inport(target); line=get_param(destination,"Line");
            assert(line~=-1,"SimuVerity:PVTES:ReferenceTopology"); source=get_param(line,"SrcPortHandle"); delete_line(line);
            sumPath=model+"/tes_evaluator_measurement_sum_"+target;
            add_block("simulink/Math Operations/Sum",sumPath,"Inputs","++"); sumPorts=get_param(sumPath,"PortHandles");
            add_line(model,source,sumPorts.Inport(1),"autorouting","on"); add_line(model,biasPorts.Outport(1),sumPorts.Inport(2),"autorouting","on"); add_line(model,sumPorts.Outport(1),destination,"autorouting","on");
        end
        set_param(model,"SimscapeLogDecimation",1,"SimscapeLogLimitData","off");
    case "configure"
        assignin("base","tes_eval_measurement_bias_ts",timeseries(input.thermal_measurement_bias_degC(:),input.time_s(:)));
        set_param(model+"/Solar irradiation","rep_seq_t",mat2str(input.time_s(:).'),"rep_seq_y",mat2str(input.solar_irradiance_W_m2(:).'));
        set_param(model+"/Amb T","rep_seq_t",mat2str(input.time_s(:).'),"rep_seq_y",mat2str(input.ambient_temperature_degC(:).'));
        set_param(model+"/Room set temp","Value",num2str(input.room_setpoint_degC,17));
    case "collect"
        grid=(0:60:86400).'; log=simOut.get("simlogResidentialBuildingTESandPVcell"); z=zeros(numel(grid),4);
        for k=1:4, z(:,k)=localSeries(log.Residential_unit.(char("Room_" + string(k))).Air_thermal_mass.T.series,grid,"K")-273.15; end
        tank=localSeries(log.Hot_water_tank.H.T.series,grid,"K")-273.15; hot=localSeries(log.Thermal_energy_storage.Sand_TES.hotSand.T.series,grid,"K")-273.15; cold=localSeries(log.Thermal_energy_storage.Sand_TES.coldSand.T.series,grid,"K")-273.15;
        pvT=localSeries(log.Photovoltaic_panel.Solar_Cell.H.T.series,grid,"K")-273.15; pvP=localSeries(log.Thermal_energy_storage.Sand_TES.heater.power_dissipated.series,grid,"W"); storeE=localSeries(log.Thermal_energy_storage.Sand_TES.hPotential.series,grid,"J"); storeE=storeE-storeE(1);
        hex=localSeries(log.Heat_exchanger.HEX.Q1.series,grid,"W"); floorQ=localSeries(log.Conductive_Heat_Transfer1.Q.series,grid,"W"); water=localSeries(log.Water_pump.mdot_A.series,grid,"kg/s"); air=localSeries(log.Heat_exchanger.Air_blower.mdot_A.series,grid,"kg/s"); pumpW=localSeries(log.Water_pump.power.series,grid,"W"); blowerW=localSeries(log.Heat_exchanger.Air_blower.power.series,grid,"W");
        valve=localTimeseries(simOut.get("tes_eval_valve"),grid); pump=localTimeseries(simOut.get("tes_eval_pump_cmd"),grid); blower=localTimeseries(simOut.get("tes_eval_blower_cmd"),grid); sp=repmat(input.room_setpoint_degC,numel(grid),1);
        assignin("base","tes_thermal_state_ts",timeseries([z tank .5*(hot+cold) pvT],grid));
        assignin("base","tes_energy_flow_ts",timeseries([pvP storeE hex hex+floorQ water air],grid));
        assignin("base","tes_control_ts",timeseries([valve pump blower pumpW blowerW sp],grid));
    otherwise, error("SimuVerity:PVTES:AdapterAction","Unknown reference adapter action.");
end
end

function [payload,observations]=localResolveContainers(simOut,model) %#ok<INUSD>
names={"tes_thermal_state_ts","tes_energy_flow_ts","tes_control_ts"};
payload=struct();
observations=repmat(struct("name","","readable",false, ...
    "mechanism","","source_sid",""),1,numel(names));
for k=1:numel(names)
    name=names{k};
    [value,mechanism,found]=localRuntimeValue(simOut,name);
    observations(k).name=name;
    observations(k).readable=found;
    observations(k).mechanism=mechanism;
    if found, payload.(name)=value; end
end
end

function [value,mechanism,found]=localRuntimeValue(simOut,name)
value=[]; mechanism=""; found=false;
if isa(simOut,"Simulink.SimulationOutput")&&any(strcmp(simOut.who,name))
    value=localUnwrapPublicValue(simOut.get(name));
    mechanism="simulation_output"; found=true; return
end
if evalin("base","exist('"+name+"','var')")
    value=localUnwrapPublicValue(evalin("base",name));
    mechanism="base_workspace"; found=true; return
end
if isa(simOut,"Simulink.SimulationOutput")&&any(strcmp(simOut.who,"logsout"))
    [value,found]=localDatasetElementValue(simOut.get("logsout"),name);
    if found, mechanism="logsout_dataset"; return, end
end
for rootName={"yout","out"}
    key=rootName{1};
    if ~isa(simOut,"Simulink.SimulationOutput")||~any(strcmp(simOut.who,key)), continue, end
    rootValue=simOut.get(key);
    [value,found]=localDatasetElementValue(rootValue,name);
    if found, mechanism="root_outport_or_yout"; return, end
    if isstruct(rootValue)&&isfield(rootValue,"signals")&&isfield(rootValue,"time")
        labels=string({rootValue.signals.label});
        index=find(labels==string(name));
        if numel(index)==1
            value=timeseries(rootValue.signals(index).values,rootValue.time);
            mechanism="root_outport_or_yout"; found=true; return
        end
    end
end
end

function [value,found]=localDatasetElementValue(dataset,name)
value=[]; found=false;
if ~isa(dataset,"Simulink.SimulationData.Dataset"), return, end
try
    element=dataset.getElement(name);
catch
    return
end
if isempty(element), return, end
if isa(element,"timeseries")
    value=element;
elseif isa(element,"Simulink.SimulationData.Signal")
    value=element.Values;
else
    value=localUnwrapPublicValue(element);
end
found=~isempty(value);
end

function value=localUnwrapPublicValue(value)
while isa(value,"Simulink.SimulationData.Signal")
    value=value.Values;
end
end

function item=localExtract(payload,id,role,observations)
names={"tes_thermal_state_ts","tes_energy_flow_ts","tes_control_ts"}; widths=[7 6 6]; grid=(0:60:86400).'; data=cell(1,3);
for k=1:3
    assert(isfield(payload,names{k}),"SimuVerity:PVTES:MissingContainer","Missing %s.",names{k}); ts=payload.(names{k});
    assert(isa(ts,"timeseries"),"SimuVerity:PVTES:ContainerType","%s must be timeseries.",names{k}); t=double(ts.Time(:)); x=double(ts.Data); if isvector(x),x=x(:);end; if size(x,1)~=numel(t)&&size(x,2)==numel(t),x=x.';end
    assert(size(x,1)==numel(t)&&size(x,2)==widths(k)&&t(1)==0&&t(end)==86400&&all(diff(t)>0)&&max(diff(t))<=60,"SimuVerity:PVTES:ContainerContract","Invalid %s.",names{k});
    data{k}=interp1(t,x,grid,"linear"); assert(all(isfinite(data{k}),"all"),"SimuVerity:PVTES:Finite");
end
item=struct("schema","simuverity.ext-tes-canonical-evidence.v1","scenario_id",id,"role",char(role), ...
    "time_s",grid,"thermal",data{1},"energy",data{2},"control",data{3},"container_source",observations);
end

function witness=localSystemObservations(model,role,observations)
if role=="reference"
    witness=struct("schema","simuverity.ext-tes-system-observations.v1", ...
        "trace_state","opaque","trace_reason","bundled_reference_adapter", ...
        "valve_structure_pass",true,"mechanism_pass",true,"control_pass",true, ...
        "container_observations",observations);
    return
end
names={"tes_thermal_state_ts","tes_energy_flow_ts","tes_control_ts"}; mapped=true;
for k=1:numel(names)
    hits=find_system(model,"LookUnderMasks","all","FollowLinks","on","BlockType","ToWorkspace","VariableName",names{k});
    mapped=mapped&&(numel(hits)==1); if numel(hits)==1, observations(k).source_sid=get_param(hits{1},"SID"); end
end
witness=struct("schema","simuverity.ext-tes-system-observations.v1", ...
    "trace_state",char(string("opaque")),"trace_reason","runtime_public_container_resolution", ...
    "static_public_container_bindings_complete",mapped,"mechanism_pass",false,"control_pass",false, ...
    "container_observations",observations);
end

function observations=localContainerObservations(~)
observations=repmat(struct("name","","readable",false,"mechanism","","source_sid",""),1,3);
end
function y=localSeries(series,grid,unit), y=interp1(double(time(series)),double(values(series,Units=unit)),grid,"linear"); end
function y=localTimeseries(series,grid), y=interp1(double(series.Time(:)),double(series.Data(:)),grid,"previous","extrap"); end
function row=localScenarioRow(), row=struct("id","","input",struct(),"status","NOT_RUN","evidence",struct(),"container_source",struct([]),"failure",struct()); end
function value=localException(ME), value=struct("identifier",ME.identifier,"message",ME.message); end
function localWriteJson(pathValue,value), tmp=pathValue+".tmp";f=fopen(tmp,"w","n","UTF-8");assert(f>=0,"SimuVerity:PVTES:Write");c=onCleanup(@()fclose(f));fprintf(f,"%s\n",jsonencode(value,"PrettyPrint",true));clear c;[ok,msg]=movefile(tmp,pathValue,"f");assert(ok,"SimuVerity:PVTES:Write","%s",msg);end
