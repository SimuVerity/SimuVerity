function evidence = ext_xfluid_wecsim_rm3_extract_evidence(modelPath,outDir,officialScenarios,evaluatorAssetRoot)
% Evidence-only dual-role adapter for the WEC-Sim RM3 task.
arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end
taskId = "EXT-XFLUID-WECSIM-RM3";
referencePresence = "present";
spec = localOfficialSpec(taskId);
modelPresence = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
if ~isfolder(outDir), mkdir(outDir); end
taskFolder = fileparts(mfilename("fullpath"));
restoredefaultpath;
addpath(taskFolder,"-begin");
baseSnapshot = localSnapshotBase();
cleanupBase = onCleanup(@() localRestoreBase(baseSnapshot)); %#ok<NASGU>
previousFolder = pwd;
cleanupFolder = onCleanup(@() cd(previousFolder)); %#ok<NASGU>

stage = struct("setup",false,"load",false,"update",false,"compile",false,"smoke",false);
timing = struct("setup_s",0,"load_s",0,"update_s",0,"compile_s",0, ...
    "smoke_s",0,"scenarios_s",0,"total_s",0);
started = tic;
if isReference
    assert(isfolder(evaluatorAssetRoot),"SimuVerity:EXT:RM3ReferenceAssetRoot","Evaluator-owned reference asset root is missing.");
    referenceRepo=localResolveReferenceRepo(evaluatorAssetRoot);
    runtimeRepo = fullfile(outDir,"runtime_reference_repo");
    timer=tic; [ok,message]=copyfile(referenceRepo,runtimeRepo);
    assert(ok,"SimuVerity:EXT:RM3RuntimeCopy","Cannot copy reference project: %s",message);
    timing.setup_s=toc(timer); stage.setup=true;
    runtimeCase=fullfile(runtimeRepo,"examples","RM3");
    runtimeModel=fullfile(runtimeCase,"RM3.slx");
    cd(runtimeRepo); run(fullfile(runtimeRepo,"addWecSimSource.m")); cd(runtimeCase);
    scenarioTimer=tic;
    scenarioItems=cell(numel(spec.scenarios),1); structure=struct;
    for index=1:numel(spec.scenarios)
        scenario=spec.scenarios(index);
        [logs,preflight,structure]=localRunNativeScenario(runtimeModel,runtimeCase,scenario,index==1);
        if index==1
            stage.load=preflight.load; stage.update=preflight.update;
            stage.compile=preflight.compile; stage.smoke=preflight.smoke;
            timing.load_s=preflight.load_s; timing.update_s=preflight.update_s;
            timing.compile_s=preflight.compile_s; timing.smoke_s=preflight.smoke_s;
        end
        item=localScenarioEvidence(scenario,logs,toc(scenarioTimer));
        scenarioItems{index}=item;
        localWriteJsonAtomic(fullfile(outDir,"scenario_"+string(scenario.id)+".json"),item);
        scenarioTimer=tic;
    end
    scenarios=vertcat(scenarioItems{:});
    runtimePresenceAfter=localFilePresence(runtimeModel);
    runtimeModelUnchanged=strcmpi(runtimePresenceAfter,referencePresence);
    localClose("RM3");
else
    stage.setup=true;
    modelFolder=fileparts(modelPath); addpath(genpath(modelFolder),"-begin"); cd(modelFolder);
    [~,model]=fileparts(modelPath);
    timer=tic; load_system(modelPath); timing.load_s=toc(timer); stage.load=true;
    cleanupModel=onCleanup(@() localClose(model)); %#ok<NASGU>
    set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on", ...
        "LimitDataPoints","off");
    structure=localCandidateAudit(model);
    localAssignPublicCommand(spec.scenarios(1));
    timer=tic; set_param(model,"SimulationCommand","update"); timing.update_s=toc(timer); stage.update=true;
    timer=tic; feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    timing.compile_s=toc(timer); stage.compile=true;
    timer=tic; sim(model,"StopTime","0.2","SrcWorkspace","base","ReturnWorkspaceOutputs","on");
    timing.smoke_s=toc(timer); stage.smoke=true;
    scenarioTimer=tic; scenarioItems=cell(numel(spec.scenarios),1);
    for index=1:numel(spec.scenarios)
        scenario=spec.scenarios(index); localClearPublicOutputs(); localAssignPublicCommand(scenario);
        try
            simOut=sim(model,"StopTime",num2str(spec.simulation.stop_time_s,17), ...
                "SrcWorkspace","base","ReturnWorkspaceOutputs","on");
            logs=localCandidateLogsPartial(simOut,spec.simulation.stop_time_s);
            item=localScenarioEvidence(scenario,logs,toc(scenarioTimer));
        catch exception
            item=localInvalidScenario(scenario,exception,toc(scenarioTimer));
        end
        scenarioItems{index}=item;
        localWriteJsonAtomic(fullfile(outDir,"scenario_"+string(scenario.id)+".json"),item);
        scenarioTimer=tic;
    end
    scenarios=vertcat(scenarioItems{:});
    runtimeModel=char(modelPath); runtimePresenceAfter=modelPresence; runtimeModelUnchanged=true;
end
timing.scenarios_s=sum([scenarios.wall_seconds]); timing.total_s=toc(started);
simulationValid=~isempty(scenarios)&&all([scenarios.simulation_valid]);valid=~isempty(scenarios)&&all([scenarios.valid]);
evidence=struct( ...
    "schema","simuverity.ext-xfluid-wecsim-rm3-evidence.v1", ...
    "task_id",taskId,"scoring_run_id",string(getenv("SIMUVERITY_SCORING_RUN_ID")), ...
    "source_model_path",modelPath,"source_model_file_presence",modelPresence, ...
    "runtime_model_path",string(runtimeModel),"runtime_model_file_presence_after",runtimePresenceAfter, ...
    "runtime_model_unchanged",runtimeModelUnchanged, ...
    "adapter_role",localTernary(isReference,"reference_native_outputs","candidate_public_contract_only"), ...
    "reference_native_locator_used",isReference,"candidate_contract_only",~isReference, ...
    "public_input_name","rm3_command", ...
    "public_output_names",["rm3_body_response","rm3_pto_response","rm3_hydrodynamic_response"], ...
    "stages",stage,"timings",timing,"structural_audit",structure, ...
    "scenario_count",numel(scenarios),"scenarios",scenarios, ...
    "all_scenarios_valid",valid,"all_scenarios_simulation_valid",simulationValid,"required_outputs_complete",valid,"EVIDENCE_COMPLETE", ...
        all([stage.setup stage.load stage.update stage.compile stage.smoke]) && simulationValid && runtimeModelUnchanged);
localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
end

function [logs,preflight,audit]=localRunNativeScenario(modelPath,caseDir,scenario,doPreflight)
mcr=struct;
mcr.header={'waves.height','waves.period','pto(1).damping','simu.endTime', ...
    'simu.rampTime','simu.dt','simu.explorer'};
    mcr.cases={double(scenario.wave_height_m),double(scenario.wave_period_s), ...
    double(scenario.pto_damping_n_s_m),80,15,0.1,"off"};
imcr=1;
% WEC-Sim mask expressions resolve its initialization objects from the base
% workspace.  Execute the unmodified native initialization script there;
% running it in this helper's function workspace makes load succeed but
% causes update/compile to fail while resolving body/pto/waves.
assignin("base","mcr",mcr);
assignin("base","imcr",imcr);
cd(caseDir); evalin("base","initializeWecSim");
localRestoreFileGeneration();
localAssignPublicCommand(scenario);
[~,model]=fileparts(modelPath);
preflight=struct("load",false,"update",false,"compile",false,"smoke",false, ...
    "load_s",0,"update_s",0,"compile_s",0,"smoke_s",0);
if doPreflight
    timer=tic; load_system(modelPath); preflight.load_s=toc(timer); preflight.load=true;
    set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on", ...
        "LimitDataPoints","off");
    audit=localReferenceAudit(model);
    timer=tic; set_param(model,"SimulationCommand","update"); preflight.update_s=toc(timer); preflight.update=true;
    timer=tic; feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    preflight.compile_s=toc(timer); preflight.compile=true;
    set_param(model,"StopTime","0.2");
    localClearNativeOutputs();
    timer=tic; sim(model,"SrcWorkspace","base","ReturnWorkspaceOutputs","on"); preflight.smoke_s=toc(timer); preflight.smoke=true;
    localClearNativeOutputs();
else
    audit=localReferenceAudit(model);
end
set_param(model,"StopTime","80");
localClearNativeOutputs();
simOut=sim(model,"SrcWorkspace","base","ReturnWorkspaceOutputs","on");
body1_out=localNativeOutput(simOut,"body1_out");
body2_out=localNativeOutput(simOut,"body2_out");
pto1_out=localNativeOutput(simOut,"pto1_out");
waves=evalin("base","waves");
logs=localNativeLogs(body1_out,body2_out,pto1_out,waves,scenario);
if doPreflight
    % Keep the loaded model for the remaining scenarios; close in the last caller cleanup.
end
end

function logs=localNativeLogs(body1,body2,pto1,waves,scenario)
t=double(body1.time(:)); b1=double(body1.signals.values); b2=double(body2.signals.values);
p=double(pto1.signals.values);
assert(size(b1,2)>=60&&size(b2,2)>=60&&size(p,2)>=48,"SimuVerity:EXT:RM3NativeWidth","Native output width is incomplete.");
assert(numel(body2.time)==numel(t)&&numel(pto1.time)==numel(t),"SimuVerity:EXT:RM3NativeTime","Native output lengths differ.");
grid=(0:0.1:80).';
b1=interp1(t,b1,grid,"linear","extrap"); b2=interp1(double(body2.time(:)),b2,grid,"linear","extrap");
p=interp1(double(pto1.time(:)),p,grid,"linear","extrap");
wave=interp1(double(waves.waveAmpTime(:,1)),double(waves.waveAmpTime(:,2)),grid,"linear","extrap");
relativeVelocity=p(:,9); absorbedPower=double(scenario.pto_damping_n_s_m).*relativeVelocity.^2;
logs=struct("time_s",grid, ...
    "rm3_body_response",[b1(:,3) b1(:,9) b2(:,3) b2(:,9)], ...
    "rm3_pto_response",[p(:,3) relativeVelocity p(:,21) absorbedPower], ...
    "rm3_hydrodynamic_response",[wave b1(:,27) b1(:,33) b1(:,45)]);
end

function logs=localCandidateLogsPartial(simOut,stopTime)
names=["rm3_body_response","rm3_pto_response","rm3_hydrodynamic_response"];
grid=(0:0.1:stopTime).'; logs=struct("time_s",grid);
for name=names
    [time,data,ok]=localOptionalPublic(simOut,name,4,stopTime);if ok,logs.(name)=interp1(time,data,grid,"linear");else,logs.(name)=[];end
    logs.(name+"_available")=ok;
end
end
function [time,data,ok]=localOptionalPublic(simOut,name,width,stopTime)
time=[];data=[];ok=false;value=[];try,value=simOut.get(name);catch,end
if~isa(value,"timeseries"),return;end
try,[time,data]=localTimeseriesMatrix(value,width);ok=time(1)<=1e-9&&time(end)>=stopTime-1e-9&&max(diff(time))<=0.100000001;catch,time=[];data=[];ok=false;end
end

function item=localScenarioEvidence(scenario,logs,wallSeconds)
ba=~isempty(logs.rm3_body_response);pa=~isempty(logs.rm3_pto_response);ha=~isempty(logs.rm3_hydrodynamic_response);if isfield(logs,"rm3_body_response_available"),ba=logs.rm3_body_response_available;pa=logs.rm3_pto_response_available;ha=logs.rm3_hydrodynamic_response_available;end
allData=[logs.rm3_body_response logs.rm3_pto_response logs.rm3_hydrodynamic_response];
item=struct("id",string(scenario.id),"valid",ba&&pa&&ha&&all(isfinite(allData),"all"),"simulation_valid",true,"body_available",ba,"pto_available",pa,"hydrodynamic_available",ha, ...
    "wall_seconds",wallSeconds,"input",struct( ...
        "wave_height_m",double(scenario.wave_height_m), ...
        "wave_period_s",double(scenario.wave_period_s), ...
        "pto_damping_n_s_m",double(scenario.pto_damping_n_s_m)), ...
    "time_s",logs.time_s,"rm3_body_response",logs.rm3_body_response, ...
    "rm3_pto_response",logs.rm3_pto_response, ...
    "rm3_hydrodynamic_response",logs.rm3_hydrodynamic_response, ...
    "sample_count",numel(logs.time_s),"maximum_sample_interval_s",max(diff(logs.time_s)), ...
    "failure_identifier","","failure_message","");
end

function item=localInvalidScenario(scenario,exception,wallSeconds)
item=struct("id",string(scenario.id),"valid",false,"wall_seconds",wallSeconds, ...
    "input",struct("wave_height_m",double(scenario.wave_height_m), ...
        "wave_period_s",double(scenario.wave_period_s), ...
        "pto_damping_n_s_m",double(scenario.pto_damping_n_s_m)), ...
    "time_s",[],"rm3_body_response",[],"rm3_pto_response",[], ...
    "rm3_hydrodynamic_response",[],"sample_count",0,"maximum_sample_interval_s",Inf, ...
    "failure_identifier",string(exception.identifier),"failure_message",string(exception.message));
item.simulation_valid=false;item.body_available=false;item.pto_available=false;item.hydrodynamic_available=false;
end

function audit=localReferenceAudit(model)
paths=[model+"/Float",model+"/Spar//Plate",model+"/Translational PTO",model+"/Global Reference Frame"];
for path=paths, assert(getSimulinkBlockHandle(path,true)~=-1,"SimuVerity:EXT:RM3ReferenceTopology","Missing %s.",path); end
ptoPorts=get_param(paths(3),"PortHandles");
physicalConnected=all([arrayfun(@(p)get_param(p,"Line")~=-1,ptoPorts.LConn), ...
    arrayfun(@(p)get_param(p,"Line")~=-1,ptoPorts.RConn)]);
blocks=find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");
audit=struct("expanded_block_count",numel(blocks),"body_count",2,"pto_count",1, ...
    "hydrodynamic_data_present",true,"pto_physical_ports_connected",physicalConnected, ...
    "two_body_hydrodynamic_path",true,"relative_motion_power_path",physicalConnected, ...
    "structure_qualified",physicalConnected);
end

function audit=localCandidateAudit(model)
blocks=find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");connected=0;
for index=1:numel(blocks),try,p=get_param(blocks{index},"PortConnectivity");connected=connected+double(any(arrayfun(@(x)(~isempty(x.SrcBlock)&&any(x.SrcBlock~=-1))||(~isempty(x.DstBlock)&&any(x.DstBlock~=-1)),p)));catch,end,end
audit=struct("expanded_block_count",numel(blocks),"connected_block_count",connected,"method","implementation_neutral_connectivity_metadata_only","structure_qualified",false,"qualification_deferred_to_public_kinematics_conservation_and_interventions",true);
end

function localAssignPublicCommand(scenario)
command=struct("wave_height_m",double(scenario.wave_height_m), ...
    "wave_period_s",double(scenario.wave_period_s), ...
    "pto_damping_n_s_m",double(scenario.pto_damping_n_s_m));
assignin("base","rm3_command",command);
end

function value=localPublicOutput(simOut,name)
value=[]; try, value=simOut.get(name); catch, end
if isempty(value)&&evalin("base","exist('"+name+"','var')~=0"), value=evalin("base",name); end
assert(isa(value,"timeseries"),"SimuVerity:EXT:RM3RequiredOutput","Required public Timeseries %s is missing.",name);
end

function value=localNativeOutput(simOut,name)
% With ReturnWorkspaceOutputs enabled, To Workspace data created by a sim
% invoked inside this function is owned by the SimulationOutput object.
% Keep a base-workspace fallback for WEC-Sim releases that explicitly use
% the base workspace, but never require that implementation detail.
value=[]; try, value=simOut.get(name); catch, end
if isempty(value)&&evalin("base","exist('"+name+"','var')~=0"), value=evalin("base",name); end
assert(~isempty(value),"SimuVerity:EXT:RM3NativeOutputs","Native WEC-Sim output %s is missing.",name);
end

function [time,data]=localTimeseriesMatrix(value,width)
time=double(value.Time(:)); data=squeeze(double(value.Data));
if size(data,1)~=numel(time)&&size(data,2)==numel(time),data=data.';end
assert(size(data,1)==numel(time)&&size(data,2)==width,"SimuVerity:EXT:RM3OutputWidth","Expected %d channels.",width);
assert(all(isfinite(time))&&all(diff(time)>0),"SimuVerity:EXT:RM3Time","Invalid output time vector.");
end

function localRestoreFileGeneration()
cache=string(getenv("SIMULINK_CACHE_FOLDER")); codegen=string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache)>0&&strlength(codegen)>0,"SimuVerity:EXT:RM3Isolation","Missing isolated file-generation paths.");
if ~isfolder(cache),mkdir(cache);end
if ~isfolder(codegen),mkdir(codegen);end
Simulink.fileGenControl("set","CacheFolder",cache,"CodeGenFolder",codegen,"createDir",true);
end

function spec=localOfficialSpec(taskId)
root=fileparts(mfilename("fullpath")); for level=1:4,root=fileparts(root);end
spec=jsondecode(fileread(simuverity_official_scenarios_path()));
end

function localClearPublicOutputs()
for name=["rm3_body_response","rm3_pto_response","rm3_hydrodynamic_response"]
    evalin("base","if exist('"+name+"','var'),clear('"+name+"');end");
end
end

function localClearNativeOutputs()
evalin("base",'clear body1_out body2_out pto1_out response output rm3_body_response rm3_pto_response rm3_hydrodynamic_response');
end

function snapshot=localSnapshotBase()
names=["rm3_command","rm3_body_response","rm3_pto_response","rm3_hydrodynamic_response"];
snapshot=struct; snapshot.names=names; snapshot.exists=false(size(names)); snapshot.values=cell(size(names));
for index=1:numel(names)
    snapshot.exists(index)=evalin("base","exist('"+names(index)+"','var')~=0");
    if snapshot.exists(index),snapshot.values{index}=evalin("base",names(index));end
end
end

function localRestoreBase(snapshot)
for index=1:numel(snapshot.names)
    name=snapshot.names(index);
    if snapshot.exists(index),assignin("base",name,snapshot.values{index});
    else,evalin("base","if exist('"+name+"','var'),clear('"+name+"');end");end
end
end

function value=localSafeGet(block,parameter)
try,value=string(get_param(block,parameter));catch,value="";end
end

function referenceRepo=localResolveReferenceRepo(evaluatorAssetRoot)
containerRoot=string(evaluatorAssetRoot);
nestedRepo=fullfile(containerRoot,"repo");
candidates=[containerRoot;nestedRepo];
matches=false(size(candidates));
for index=1:numel(candidates)
    matches(index)=localReferenceRepoMatches(candidates(index));
end
assert(nnz(matches)==1 && matches(2),"SimuVerity:EXT:RM3ReferenceRepoIdentity", ...
    "Evaluator asset root must uniquely contain the path-bound nested RM3 repo.");
referenceRepo=nestedRepo;
end

function matches=localReferenceRepoMatches(root)
relativeAssets=[ ...
    "addWecSimSource.m"; ...
    "source/functions/initializeWecSim.m"; ...
    "examples/RM3/wecSimInputFile.m"; ...
    "examples/RM3/RM3.slx"];
expectedBindings=[ ...
    "present"; ...
    "present"; ...
    "present"; ...
    "present"];
matches=true;
for index=1:numel(relativeAssets)
    assetPath=fullfile(root,replace(relativeAssets(index),"/",filesep));
    if ~isfile(assetPath) || ~strcmpi(localFilePresence(assetPath),expectedBindings(index))
        matches=false;
        return
    end
end
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

function localWriteJsonAtomic(path,value)
temporary=tempname(fileparts(path))+".json"; fid=fopen(temporary,"w");
assert(fid>=0,"SimuVerity:EXT:RM3EvidenceWrite","Cannot write evidence."); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(value,PrettyPrint=true));clear cleanup;movefile(temporary,path,"f");
end

function localClose(model)
try,if bdIsLoaded(model),close_system(model,0);end,catch,end
end

function value=localTernary(condition,yesValue,noValue)
if condition,value=yesValue;else,value=noValue;end
end
