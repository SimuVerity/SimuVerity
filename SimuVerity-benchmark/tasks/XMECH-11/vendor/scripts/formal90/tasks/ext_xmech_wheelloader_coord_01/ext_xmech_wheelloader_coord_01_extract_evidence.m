function evidence = ext_xmech_wheelloader_coord_01_extract_evidence(modelPath,outDir,officialScenarios,evaluatorAssetRoot)
% Dual-role evidence extractor. Reference internals are used only after an
% exact file binding match and only inside an evaluator-owned complete-project copy.
arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end
taskId = "EXT-XMECH-WHEELLOADER-COORD-01";
referencePresence = "present";
sourcePresence = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
spec = localOfficialSpec(taskId);
if ~isfolder(outDir), mkdir(outDir); end
taskFolder = fileparts(mfilename("fullpath"));
restoredefaultpath; addpath(taskFolder,"-begin");
localReloadCandidateDependencies(isReference);
oldFolder = pwd; folderCleanup = onCleanup(@()cd(oldFolder)); %#ok<NASGU>
baseSnapshot = localSnapshotBase(); baseCleanup = onCleanup(@()localRestoreBase(baseSnapshot)); %#ok<NASGU>
localConfigureFileGeneration();
started=tic; loaded=false; project=[]; runtimeRoot="";
stage=struct("setup",false,"load",false,"update",false,"compile",false,"smoke",false);
timing=struct("setup_s",0,"load_s",0,"update_s",0,"compile_s",0,"smoke_s",0,"scenarios_s",0,"total_s",0);
try
    timer=tic;
    if isReference
        assert(isfolder(evaluatorAssetRoot),"SimuVerity:EXT:WheelReferenceAssetRoot","Evaluator-owned reference asset root is missing.");
        referenceRoot=evaluatorAssetRoot;
        runtimeRoot=string(tempname);
        [ok,message]=copyfile(referenceRoot,runtimeRoot); assert(ok,"SimuVerity:EXT:WheelRuntimeCopy","%s",message);
        runtimeCleanup=onCleanup(@()localRemoveRuntime(runtimeRoot)); %#ok<NASGU>
        runtimeModel=fullfile(runtimeRoot,"Models","Vehicle","sm_wheel_loader.slx");
        assert(strcmpi(localFilePresence(runtimeModel),referencePresence),"SimuVerity:EXT:WheelRuntimePresence","Reference file binding mismatch after copy.");
        cd(runtimeRoot); project=openProject(fullfile(runtimeRoot,"Wheel_Loader_Simscape.prj"));
    else
        runtimeModel=char(modelPath); modelFolder=fileparts(modelPath); cd(modelFolder); addpath(modelFolder,"-begin");
    end
    timing.setup_s=toc(timer); stage.setup=true;
    [~,model]=fileparts(runtimeModel);
    timer=tic; load_system(runtimeModel); timing.load_s=toc(timer); stage.load=true; loaded=true;
    modelCleanup=onCleanup(@()localClose(model)); %#ok<NASGU>
    set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on", ...
        "SignalLogging","on","LimitDataPoints","off");
    if isReference
        localConfigureReference(model);
        defaults=localReferenceDefaults();
        [commandTime,commandValues]=localCommandProfile(double(spec.scenarios(1).stop_time_s));
        localApplyReferenceScenario(spec.scenarios(1),defaults);
    else
        defaults=struct();
        [commandTime,commandValues]=localCommandProfile(double(spec.scenarios(1).stop_time_s));
        localAssignCandidateScenario(spec.scenarios(1),commandTime,commandValues);
    end
    timer=tic; set_param(model,"SimulationCommand","update"); timing.update_s=toc(timer); stage.update=true;
    timer=tic; feval(model,[],[],[],"compile"); feval(model,[],[],[],"term"); timing.compile_s=toc(timer); stage.compile=true;
    timer=tic; smoke=sim(model,"StopTime","0.1","SimulationMode","normal", ...
        "SrcWorkspace","base","ReturnWorkspaceOutputs","on","CaptureErrors","on");
    if strlength(string(smoke.ErrorMessage))>0, error("SimuVerity:EXT:WheelSmoke","%s",string(smoke.ErrorMessage)); end
    timing.smoke_s=toc(timer); stage.smoke=true;
catch exception
    timing.total_s=toc(started);
    evidence=localAssemble(taskId,modelPath,sourcePresence,isReference,"",false,stage,timing,struct([]),exception);
    localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
    if isReference, rethrow(exception); end
    return
end

items=cell(numel(spec.scenarios),1); timer=tic;
for index=1:numel(spec.scenarios)
    scenario=spec.scenarios(index); scenarioTimer=tic;
    try
        localClearPublicOutputs();
        [commandTime,commandValues]=localCommandProfile(double(scenario.stop_time_s));
        if isReference
            simulationInput=localReferenceSimulationInput(model,scenario,defaults);
        else
            simulationInput=localCandidateSimulationInput(model,scenario,commandTime,commandValues);
        end
        simulation=sim(simulationInput);
        if strlength(string(simulation.ErrorMessage))>0, error("SimuVerity:EXT:WheelScenario","%s",string(simulation.ErrorMessage)); end
        if isReference
            logs=localReferenceLogs(simulation,double(scenario.stop_time_s));
        else
            logs=localCandidateLogs(simulation,double(scenario.stop_time_s));
        end
        item=localScenarioEvidence(scenario,commandTime,commandValues,logs,toc(scenarioTimer));
    catch exception
        item=localInvalidScenario(scenario,toc(scenarioTimer),exception);
        if isReference
            localWriteJsonAtomic(fullfile(outDir,"scenario_"+string(scenario.id)+".json"),item);
            rethrow(exception);
        end
    end
    items{index}=item;
    localWriteJsonAtomic(fullfile(outDir,"scenario_"+string(scenario.id)+".json"),item);
end
scenarios=vertcat(items{:}); timing.scenarios_s=toc(timer); timing.total_s=toc(started);
runtimePresence=localFilePresence(runtimeModel); runtimeUnchanged=strcmpi(runtimePresence,sourcePresence);
evidence=localAssemble(taskId,modelPath,sourcePresence,isReference,runtimePresence,runtimeUnchanged,stage,timing,scenarios,[]);
localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
if ~isempty(project), try, close(project); catch, end, end
end

function localConfigureReference(model)
set_param(model+"/Wheel Loader","popup_engine","Droop", ...
    "popup_driveline","1D, CV Joints","popup_cvt","Power Split Hydromechanical", ...
    "popup_actuator_model","Hydraulic","popup_surface","Plane (Spheres)");
sm_wheel_loader_config_impl(char(model),"Bucket Load");
end

function defaults=localReferenceDefaults()
defaults=struct("HMPST",evalin("base","HMPST"), ...
    "HydFcnParams",evalin("base","HydFcnParams"),"testInput",evalin("base","testInput"));
end

function localApplyReferenceScenario(scenario,defaults)
[hmpst,hydraulic,testInput]=localReferenceScenarioValues(scenario,defaults);
assignin("base","HMPST",hmpst); assignin("base","HydFcnParams",hydraulic); assignin("base","testInput",testInput);
end

function simulationInput=localReferenceSimulationInput(model,scenario,defaults)
[hmpst,hydraulic,testInput]=localReferenceScenarioValues(scenario,defaults);
simulationInput=localScenarioSimulationInput(model,double(scenario.stop_time_s));
simulationInput=simulationInput.setVariable("HMPST",hmpst);
simulationInput=simulationInput.setVariable("HydFcnParams",hydraulic);
simulationInput=simulationInput.setVariable("testInput",testInput);
end

function [hmpst,hydraulic,testInput]=localReferenceScenarioValues(scenario,defaults)
hmpst=defaults.HMPST; hydraulic=defaults.HydFcnParams; testInput=defaults.testInput;
hmpst.Tire.Contact.sphere.muStatic=double(scenario.tire_mu_static);
hmpst.Tire.Contact.sphere.muDynamic=double(scenario.tire_mu_dynamic);
hmpst.HRB.Accumulator.pPrecharge=double(scenario.hrb_precharge_pressure_MPa);
hydraulic.pump.displacement=defaults.HydFcnParams.pump.displacement*double(scenario.implement_pump_scale);
hydraulic.pump.maxFlow=defaults.HydFcnParams.pump.maxFlow*double(scenario.implement_pump_scale);
testInput.BucketYCycle.bucketLoad.z=defaults.testInput.BucketYCycle.bucketLoad.z*double(scenario.payload_scale);
testInput.Active=testInput.BucketYCycle;
end

function localAssignCandidateScenario(scenario,commandTime,commandValues)
[command,environment]=localCandidateScenarioValues(scenario,commandTime,commandValues);
assignin("base","wheel_loader_command",command);
assignin("base","wheel_loader_environment",environment);
end

function simulationInput=localCandidateSimulationInput(model,scenario,commandTime,commandValues)
[command,environment]=localCandidateScenarioValues(scenario,commandTime,commandValues);
simulationInput=localScenarioSimulationInput(model,double(scenario.stop_time_s));
simulationInput=simulationInput.setVariable("wheel_loader_command",command);
simulationInput=simulationInput.setVariable("wheel_loader_environment",environment);
end

function [command,environment]=localCandidateScenarioValues(scenario,commandTime,commandValues)
command=timeseries(commandValues,commandTime);
environment=struct("payload_scale",double(scenario.payload_scale), ...
    "tire_mu_static",double(scenario.tire_mu_static),"tire_mu_dynamic",double(scenario.tire_mu_dynamic), ...
    "implement_pump_scale",double(scenario.implement_pump_scale), ...
    "hrb_precharge_pressure_MPa",double(scenario.hrb_precharge_pressure_MPa));
end

function simulationInput=localScenarioSimulationInput(model,stopTime)
simulationInput=Simulink.SimulationInput(model);
simulationInput=simulationInput.setModelParameter("StopTime",num2str(stopTime,17), ...
    "SimulationMode","normal","ReturnWorkspaceOutputs","on","CaptureErrors","on");
end

function [time,values]=localCommandProfile(stopTime)
profilePath=fullfile(fileparts(mfilename("fullpath")),"wheel_loader_operator_profiles.json");
profile=jsondecode(fileread(profilePath)).profiles.BucketYCycle;
names=["vVehPcnt","LiftCmd","TiltCmd","SteerCmd"];
time=0;
for name=names
    time=union(time,double(profile.(name).time_s(:)));
end
time=unique([time(time<=stopTime);stopTime]);
values=zeros(numel(time),4);
for index=1:4
    sourceTime=double(profile.(names(index)).time_s(:)); sourceValue=double(profile.(names(index)).values(:));
    values(:,index)=interp1(sourceTime,sourceValue,time,"linear","extrap");
end
end

function logs=localReferenceLogs(simulation,stopTime)
grid=(0:.05:stopTime).'; simlog=simulation.get("simlog_sm_wheel_loader");
dataset=simulation.get("logsout_sm_wheel_loader"); mVehicle=dataset.get("mVehicle").Values;
wheelRoot=simlog.Wheel_Loader.Vehicle.Driveline.Driveline.Driveline_1D;
radius=evalin("base","HMPST.Tire.Rad");
wheels=[ ...
    localSimscapeAt(wheelRoot.Planetary_FL.Revolute_Ring_Carrier.Rz.w,"rad/s",grid), ...
    localSimscapeAt(wheelRoot.Planetary_FR.Revolute_Ring_Carrier.Rz.w,"rad/s",grid), ...
    localSimscapeAt(wheelRoot.Planetary_RL.Revolute_Ring_Carrier.Rz.w,"rad/s",grid), ...
    localSimscapeAt(wheelRoot.Planetary_RR.Revolute_Ring_Carrier.Rz.w,"rad/s",grid)]*radius*3.6;
vx=localSimscapeAt(simlog.Wheel_Loader.Body_to_World.Px.v,"km/hr",grid);
vy=localSimscapeAt(simlog.Wheel_Loader.Body_to_World.Py.v,"km/hr",grid);
vehicle=sqrt(vx.^2+vy.^2).*sign(sum(wheels,2)+eps);
x=localSimscapeAt(simlog.Wheel_Loader.Body_to_World.Px.p,"m",grid);
y=localSimscapeAt(simlog.Wheel_Loader.Body_to_World.Py.p,"m",grid);
articulation=localSimscapeAt(simlog.Wheel_Loader.Vehicle.Revolute_Front_Rear.Rz.q,"deg",grid);
liftPosition=localTimeseriesAt(mVehicle.Linkage.Lift.p,grid);
tiltPosition=localTimeseriesAt(mVehicle.Linkage.Tilt.p,grid);
liftForce=localTimeseriesAt(mVehicle.Linkage.Lift.force,grid);
tiltForce=localTimeseriesAt(mVehicle.Linkage.Tilt.force,grid);
hydraulic=simlog.Wheel_Loader.Vehicle.Actuators.Hydraulic;
hydraulicMatrix=[liftForce,tiltForce, ...
    localSimscapeAt(hydraulic.Actuator_Linkage.Actuator_LiftL.A.p,"bar",grid), ...
    localSimscapeAt(hydraulic.Actuator_Linkage.Actuator_LiftL.B.p,"bar",grid), ...
    localSimscapeAt(hydraulic.Actuator_Linkage.Actuator_Tilt.A.p,"bar",grid), ...
    localSimscapeAt(hydraulic.Actuator_Linkage.Actuator_Tilt.B.p,"bar",grid), ...
    localSimscapeAt(hydraulic.Actuator_Linkage.Actuator_LiftL.chamber_A.mdot_A,"kg/s",grid), ...
    localSimscapeAt(hydraulic.Actuator_Linkage.Actuator_Tilt.chamber_A.mdot_A,"kg/s",grid), ...
    localSimscapeAt(hydraulic.Pump_Impl.p_diff,"bar",grid)];
transmission=simlog.Wheel_Loader.Transmission.Power_Split_Hydromech;
power=[ ...
    localSimscapeAt(simlog.Wheel_Loader.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t,"N*m",grid), ...
    localSimscapeAt(transmission.Power_Sensor1_CVT_In.Power_Sensor.P,"kW",grid), ...
    localSimscapeAt(transmission.Power_Sensor2_HS_In.Power_Sensor.P,"kW",grid), ...
    localSimscapeAt(transmission.Power_Sensor3_HS_Out.Power_Sensor.P,"kW",grid), ...
    localSimscapeAt(transmission.Power_Sensor6_CVT_Out.Power_Sensor.P,"kW",grid), ...
    localSimscapeAt(transmission.Power_Sensor4c_HRB.Power_Sensor.P,"kW",grid), ...
    localSimscapeAt(transmission.HRB.Gas_Charged_Accumulator.p_I,"MPa",grid), ...
    localSimscapeAt(transmission.Hydrostatic.Pump.D,"cm^3/rev",grid)];
clutchNames=["K1","K2","K3","K4","Kb","Kv","Kr"]; clutch=zeros(numel(grid),7);
for index=1:7
    clutch(:,index)=min(max(localSimscapeAt(transmission.(clutchNames(index)).Clutch.P,"Pa",grid)/1e6,0),1);
end
logs=struct("time_s",grid,"wheel_loader_motion_response",[vehicle,x,y,articulation,wheels,liftPosition,tiltPosition], ...
    "wheel_loader_hydraulic_response",hydraulicMatrix,"wheel_loader_powertrain_response",power, ...
    "wheel_loader_clutch_response",clutch,"container_availability",struct( ...
    "wheel_loader_motion_response",true(1,10),"wheel_loader_hydraulic_response",true(1,9), ...
    "wheel_loader_powertrain_response",true(1,8),"wheel_loader_clutch_response",true(1,7)));
end

function logs=localCandidateLogs(simulation,stopTime)
grid=(0:.05:stopTime).'; names=["wheel_loader_motion_response","wheel_loader_hydraulic_response", ...
    "wheel_loader_powertrain_response","wheel_loader_clutch_response"]; widths=[10 9 8 7];
logs=struct("time_s",grid);
for index=1:numel(names)
    [matrix,availability]=localPublicMatrixAt(simulation,names(index),widths(index),grid,stopTime);
    logs.(names(index))=matrix; logs.container_availability.(names(index))=availability;
end
end

function [matrix,availability]=localPublicMatrixAt(simulation,name,width,grid,stopTime)
matrix=zeros(numel(grid),width); availability=false(1,width); value=[];
try, value=simulation.get(name); catch, end
if isempty(value)&&evalin("base","exist('"+name+"','var')~=0"), value=evalin("base",name); end
if ~isa(value,"timeseries"), return, end
time=double(value.Time(:)); data=squeeze(double(value.Data));
if isvector(data), data=data(:); end
if size(data,1)~=numel(time)&&size(data,2)==numel(time), data=data.'; end
if size(data,1)~=numel(time)||isempty(time)||~all(isfinite(time))||~all(diff(time)>0), return, end
if time(1)>1e-8||time(end)<stopTime-5e-3||max(diff(time))>.0500001, return, end
channels=min(width,size(data,2));
for index=1:channels
    if all(isfinite(data(:,index)))
        matrix(:,index)=interp1(time,data(:,index),grid,"linear","extrap"); availability(index)=true;
    end
end
end

function value=localSimscapeAt(variable,unit,grid)
series=variable.series;
time=double(series.time); time=time(:);
data=double(series.values(unit)); data=squeeze(data);
if isvector(data), data=data(:); end
value=interp1(time,data,grid,"linear","extrap");
assert(size(value,2)==1&&all(isfinite(value)),"SimuVerity:EXT:WheelSimscape","Invalid Simscape series.");
end

function value=localTimeseriesAt(series,grid)
time=double(series.Time(:)); data=squeeze(double(series.Data)); if isvector(data),data=data(:);end
value=interp1(time,data,grid,"linear","extrap");
assert(size(value,2)==1&&all(isfinite(value)),"SimuVerity:EXT:WheelTimeseries","Invalid Timeseries.");
end

function item=localScenarioEvidence(scenario,commandTime,commandValues,logs,wallSeconds)
input=scenario; input.command_time_s=double(commandTime(:)); input.command_values=double(commandValues);
item=struct("id",string(scenario.id),"valid",true,"wall_seconds",wallSeconds,"input",input, ...
    "time_s",double(logs.time_s(:)),"wheel_loader_motion_response",double(logs.wheel_loader_motion_response), ...
    "wheel_loader_hydraulic_response",double(logs.wheel_loader_hydraulic_response), ...
    "wheel_loader_powertrain_response",double(logs.wheel_loader_powertrain_response), ...
    "wheel_loader_clutch_response",double(logs.wheel_loader_clutch_response), ...
    "container_availability",logs.container_availability,"failure_identifier","","failure_message","");
end

function item=localInvalidScenario(scenario,wallSeconds,exception)
item=struct("id",string(scenario.id),"valid",false,"wall_seconds",wallSeconds,"input",scenario, ...
    "time_s",[],"wheel_loader_motion_response",[],"wheel_loader_hydraulic_response",[], ...
    "wheel_loader_powertrain_response",[],"wheel_loader_clutch_response",[],"container_availability",struct( ...
    "wheel_loader_motion_response",false(1,10),"wheel_loader_hydraulic_response",false(1,9), ...
    "wheel_loader_powertrain_response",false(1,8),"wheel_loader_clutch_response",false(1,7)), ...
    "failure_identifier",string(exception.identifier),"failure_message",string(exception.message));
end

function evidence=localAssemble(taskId,modelPath,sourcePresence,isReference,runtimePresence,runtimeUnchanged,stage,timing,scenarios,exception)
valid=~isempty(scenarios)&&all([scenarios.valid]);
evidence=struct("schema","simuverity.ext-xmech-wheelloader-coord-evidence.v1", ...
    "task_id",taskId,"scoring_run_id",string(getenv("SIMUVERITY_SCORING_RUN_ID")), ...
    "source_model_path",modelPath,"source_model_file_presence",sourcePresence, ...
    "runtime_model_file_presence_before",sourcePresence,"runtime_model_file_presence_after",runtimePresence, ...
    "runtime_model_unchanged",runtimeUnchanged,"adapter_role",localTernary(isReference, ...
    "reference_native_project","candidate_public_contract_only"), ...
    "reference_native_locator_used",isReference,"candidate_contract_only",~isReference, ...
    "public_input_names",["wheel_loader_command","wheel_loader_environment"], ...
    "public_output_names",["wheel_loader_motion_response","wheel_loader_hydraulic_response", ...
    "wheel_loader_powertrain_response","wheel_loader_clutch_response"], ...
    "stages",stage,"timings",timing,"scenario_count",numel(scenarios),"scenarios",scenarios, ...
    "all_scenarios_valid",valid,"evaluator_runtime_change_manifest",struct( ...
    "saved_file_changes",false,"reference_unsaved_parameter_interventions",isReference, ...
    "in_memory_limit_data_points_disabled",true), ...
    "EVIDENCE_COMPLETE",all([stage.setup stage.load stage.update stage.compile stage.smoke])&&valid&&runtimeUnchanged);
if ~isempty(exception)
    evidence.failure_identifier=string(exception.identifier); evidence.failure_message=string(exception.message);
    evidence.failure_report=string(getReport(exception,"extended","hyperlinks","off"));
end
end

function localConfigureFileGeneration()
cache=string(getenv("SIMULINK_CACHE_FOLDER")); codegen=string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache)>0&&strlength(codegen)>0,"SimuVerity:EXT:WheelIsolation","Missing isolated file-generation paths.");
if ~isfolder(cache),mkdir(cache);end;if ~isfolder(codegen),mkdir(codegen);end
Simulink.fileGenControl("set","CacheFolder",cache,"CodeGenFolder",codegen,"createDir",true);
end
function spec=localOfficialSpec(taskId)
root=fileparts(mfilename("fullpath")); for level=1:4,root=fileparts(root);end
spec=jsondecode(fileread(simuverity_official_scenarios_path()));
end
function localClearPublicOutputs()
names=["wheel_loader_motion_response","wheel_loader_hydraulic_response","wheel_loader_powertrain_response","wheel_loader_clutch_response"];
for name=names,evalin("base","clear "+name);end
end
function snapshot=localSnapshotBase(),snapshot=evalin("base","whos");end
function localRestoreBase(snapshot)
before=string({snapshot.name});after=string(evalin("base","who"));created=setdiff(after,before);
for index=1:numel(created),evalin("base","clear "+created(index));end
end
function localClose(model),try,if bdIsLoaded(model),close_system(model,0);end,catch,end,end

function localRemoveRuntime(runtimeRoot)
try
    if strlength(runtimeRoot)>0 && isfolder(runtimeRoot), rmdir(runtimeRoot,"s"); end
catch
end
end
function localWriteJsonAtomic(pathName,value)
folder=fileparts(pathName);if ~isfolder(folder),mkdir(folder);end
temporary=pathName+".tmp."+string(feature("getpid"));fid=fopen(temporary,"w","n","UTF-8");assert(fid~=-1,"SimuVerity:EXT:WheelJson","Cannot write JSON.");
cleanup=onCleanup(@()localSafeFclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(value,"PrettyPrint",true));fclose(fid);clear cleanup;movefile(temporary,pathName,"f");
end
function localSafeFclose(fid),try,fclose(fid);catch,end,end
function binding = localFilePresence(pathName)
assert(isfile(pathName), "SimuVerity:FileMissing", "Required file is missing: %s", pathName);
binding = "present";
end

function value=localTernary(condition,yes,no),if condition,value=yes;else,value=no;end,end

function localReloadCandidateDependencies(isReference)
if isReference, return, end
helperRoot = string(getenv("SIMUVERITY_CANDIDATE_CLOSURE_HELPER_ROOT"));
assert(strlength(helperRoot)>0 && isfolder(helperRoot), ...
    "SimuVerity:EXT:WheelDependencyHelper", ...
    "Evaluator-owned candidate dependency helper root is unavailable.");
addpath(helperRoot,"-begin");
loaded = unified_reload_candidate_dependencies();
assert(string(loaded.status)=="LOADED_BEFORE_PUBLIC_INPUTS", ...
    "SimuVerity:EXT:WheelDependencyReload", ...
    "Verified candidate dependencies were not reloaded before official inputs.");
end
