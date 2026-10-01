function evidence = ext_xfluid_wec_desal_extract_evidence(modelPath,outDir,officialScenarios,evaluatorAssetRoot)
% Dual-role evidence adapter. Exact reference reads native logs; candidates
% are evaluated only through the public base input and public Timeseries.
arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end
taskId="EXT-XFLUID-WEC-DESAL";
referencePresence="present";
spec=localOfficialSpec(taskId); modelPresence=localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
if ~isfolder(outDir),mkdir(outDir);end
taskFolder=fileparts(mfilename("fullpath")); restoredefaultpath; addpath(taskFolder,"-begin");
oldFolder=pwd; cleanupFolder=onCleanup(@()cd(oldFolder)); %#ok<NASGU>
stage=struct("setup",false,"load",false,"update",false,"compile",false,"smoke",false);
timing=struct("setup_s",0,"load_s",0,"update_s",0,"compile_s",0,"smoke_s",0, ...
    "scenarios_s",0,"total_s",0); started=tic;
if isReference
    assert(isfolder(evaluatorAssetRoot),"SimuVerity:EXT:DESALReferenceAssetRoot","Evaluator-owned reference asset root is missing.");
    referenceRoot=evaluatorAssetRoot;
    runtimeRoot=fullfile(outDir,"runtime_reference");
    timer=tic; [ok,message]=copyfile(referenceRoot,runtimeRoot);
    assert(ok,"SimuVerity:EXT:DESALRuntimeCopy","Cannot copy reference project: %s",message);
    timing.setup_s=toc(timer); stage.setup=true;
    runtimeCase=fullfile(runtimeRoot,"applications","Desalination");
    runtimeWec=fullfile(runtimeRoot,"wec_sim");
    runtimeModel=fullfile(runtimeCase,"OSWEC_RO.slx");
    cd(runtimeWec); run(fullfile(runtimeWec,"addWecSimSource.m"));
    scenarioItems=cell(numel(spec.scenarios),1); structure=struct; scenarioTimer=tic;
    for index=1:numel(spec.scenarios)
        scenario=spec.scenarios(index);
        [logs,preflight,audit]=localRunNative(runtimeModel,runtimeCase,scenario,index==1);
        if index==1
            stage.load=preflight.load; stage.update=preflight.update;
            stage.compile=preflight.compile; stage.smoke=preflight.smoke;
            timing.load_s=preflight.load_s; timing.update_s=preflight.update_s;
            timing.compile_s=preflight.compile_s; timing.smoke_s=preflight.smoke_s;
            structure=audit;
        end
        item=localScenarioEvidence(scenario,logs,toc(scenarioTimer));
        scenarioItems{index}=item;
        localWriteJsonAtomic(fullfile(outDir,"scenario_"+string(scenario.id)+".json"),item);
        scenarioTimer=tic;
    end
    scenarios=vertcat(scenarioItems{:});
    runtimePresenceAfter=localFilePresence(runtimeModel);
    runtimeUnchanged=strcmpi(runtimePresenceAfter,referencePresence);
else
    stage.setup=true; modelFolder=fileparts(modelPath); addpath(genpath(modelFolder),"-begin"); cd(modelFolder);
    [~,model]=fileparts(modelPath); timer=tic; load_system(modelPath);
    timing.load_s=toc(timer); stage.load=true; cleanupModel=onCleanup(@()localClose(model)); %#ok<NASGU>
    set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on","LimitDataPoints","off");
    structure=localCandidateAudit(model); localAssignCommand(spec.scenarios(1));
    timer=tic; set_param(model,"SimulationCommand","update"); timing.update_s=toc(timer); stage.update=true;
    timer=tic; feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    timing.compile_s=toc(timer); stage.compile=true;
    timer=tic; sim(model,"StopTime","0.2","SrcWorkspace","base","ReturnWorkspaceOutputs","on");
    timing.smoke_s=toc(timer); stage.smoke=true;
    scenarioItems=cell(numel(spec.scenarios),1); scenarioTimer=tic;
    for index=1:numel(spec.scenarios)
        scenario=spec.scenarios(index); localClearPublicOutputs(); localAssignCommand(scenario);
        try
            simOut=sim(model,"StopTime","60","SrcWorkspace","base","ReturnWorkspaceOutputs","on");
            logs=localCandidateLogsPartial(simOut); item=localScenarioEvidence(scenario,logs,toc(scenarioTimer));
        catch exception
            item=localInvalidScenario(scenario,exception,toc(scenarioTimer));
        end
        scenarioItems{index}=item;
        localWriteJsonAtomic(fullfile(outDir,"scenario_"+string(scenario.id)+".json"),item);
        scenarioTimer=tic;
    end
    scenarios=vertcat(scenarioItems{:});
    runtimeModel=char(modelPath); runtimePresenceAfter=modelPresence; runtimeUnchanged=true;
end
timing.scenarios_s=sum([scenarios.wall_seconds]); timing.total_s=toc(started);
simulationValid=~isempty(scenarios)&&all([scenarios.simulation_valid]);valid=~isempty(scenarios)&&all([scenarios.valid]);
evidence=struct("schema","simuverity.ext-xfluid-wec-desal-evidence.v1", ...
    "task_id",taskId,"scoring_run_id",string(getenv("SIMUVERITY_SCORING_RUN_ID")), ...
    "source_model_path",modelPath,"source_model_file_presence",modelPresence, ...
    "runtime_model_path",string(runtimeModel),"runtime_model_file_presence_after",runtimePresenceAfter, ...
    "runtime_model_unchanged",runtimeUnchanged, ...
    "adapter_role",localTernary(isReference,"reference_native_outputs","candidate_public_contract_only"), ...
    "reference_native_locator_used",isReference,"candidate_contract_only",~isReference, ...
    "public_input_name","desal_command", ...
    "public_output_names",["desal_mechanical_response","desal_hydraulic_response","desal_recovery_response"], ...
    "stages",stage,"timings",timing,"structural_audit",structure, ...
    "scenario_count",numel(scenarios),"scenarios",scenarios,"all_scenarios_valid",valid,"all_scenarios_simulation_valid",simulationValid, ...
    "required_outputs_complete",valid,"EVIDENCE_COMPLETE",all([stage.setup stage.load stage.update stage.compile stage.smoke])&&simulationValid&&runtimeUnchanged);
localWriteJsonAtomic(fullfile(outDir,"evidence.json"),evidence);
end

function [logs,preflight,audit]=localRunNative(modelPath,caseDir,scenario,doPreflight)
mcr=struct;
mcr.header={'waves.height','waves.period','waves.phaseSeed','simu.endTime','simu.rampTime','simu.dt','simu.dtOut','simu.explorer'};
mcr.cases={double(scenario.wave_height_m),double(scenario.wave_period_s),1,60,15,0.01,0.1,'off'};
assignin("base","mcr",mcr); assignin("base","imcr",1); cd(caseDir);
timer=tic; evalin("base",'initializeWecSim'); initializationSeconds=toc(timer);
localRestoreFileGeneration(); [~,model]=fileparts(modelPath);
preflight=struct("load",true,"update",false,"compile",false,"smoke",false, ...
    "load_s",initializationSeconds,"update_s",0,"compile_s",0,"smoke_s",0);
set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on","LimitDataPoints","off");
for sink=find_system(model,"LookUnderMasks","all","FollowLinks","on","BlockType","ToWorkspace")'
    try,set_param(sink{1},"MaxDataPoints","inf");catch,end
end
audit=localReferenceAudit(model);
if doPreflight
    timer=tic; set_param(model,"SimulationCommand","update"); preflight.update_s=toc(timer); preflight.update=true;
    timer=tic; feval(model,[],[],[],"compile"); feval(model,[],[],[],"term");
    preflight.compile_s=toc(timer); preflight.compile=true;
    set_param(model,"StopTime","0.2"); localClearNativeOutputs();
    timer=tic; sim(model,"SrcWorkspace","base","ReturnWorkspaceOutputs","on"); preflight.smoke_s=toc(timer); preflight.smoke=true;
end
set_param(model,"StopTime","60"); localClearNativeOutputs();
simOut=sim(model,"SrcWorkspace","base","ReturnWorkspaceOutputs","on");
mechanical=localNativeOutput(simOut,"simout"); hydraulic=localNativeOutput(simOut,"simout1");
logs=localNativeLogs(mechanical,hydraulic); localClose(model);
end

function value=localNativeOutput(simOut,name)
% To Workspace variables created by a sim invoked from this function are
% owned by SimulationOutput when ReturnWorkspaceOutputs is on.  Retain a
% base-workspace fallback for releases that explicitly export there.
value=[];try,value=simOut.get(name);catch,end
if isempty(value)&&evalin("base","exist('"+name+"','var')~=0"),value=evalin("base",name);end
assert(~isempty(value),"SimuVerity:EXT:DESALNativeOutputs","Native desalination output %s is missing.",name);
end

function logs=localNativeLogs(mechanical,hydraulic)
t=double(mechanical.time(:)); m=double(mechanical.signals.values);
th=double(hydraulic.time(:)); h=double(hydraulic.signals.values);
assert(size(m,2)>=3&&size(h,2)>=7,"SimuVerity:EXT:DESALNativeWidth","Native desalination output width is incomplete.");
assert(numel(th)==numel(t)&&max(abs(th-t))<1e-8,"SimuVerity:EXT:DESALNativeTime","Native output time vectors differ.");
logs=struct("time_s",t,"desal_mechanical_response",m(:,1:3), ...
    "desal_hydraulic_response",h(:,[1 2 3 6]),"desal_recovery_response",h(:,[4 5 7]));
end

function logs=localCandidateLogsPartial(simOut)
[tm,m,ma]=localOptionalPublic(simOut,"desal_mechanical_response",3);[th,h,ha]=localOptionalPublic(simOut,"desal_hydraulic_response",4);[tr,r,ra]=localOptionalPublic(simOut,"desal_recovery_response",3);
if ma,t=tm;elseif ha,t=th;elseif ra,t=tr;else,t=[];end
if ma&&~isequal(tm,t),m=interp1(tm,m,t,"linear");end;if ha&&~isequal(th,t),h=interp1(th,h,t,"linear");end;if ra&&~isequal(tr,t),r=interp1(tr,r,t,"linear");end
logs=struct("time_s",t,"desal_mechanical_response",m,"desal_hydraulic_response",h,"desal_recovery_response",r,"mechanical_available",ma,"hydraulic_available",ha,"recovery_available",ra);
end
function [time,data,ok]=localOptionalPublic(simOut,name,width)
time=[];data=[];ok=false;value=[];try,value=simOut.get(name);catch,end
if~isa(value,"timeseries"),return;end
try,[time,data]=localTimeseriesMatrix(value,width);ok=time(1)<=1e-8&&time(end)>=59.9&&max(diff(time))<=0.100000001;catch,time=[];data=[];ok=false;end
end

function item=localScenarioEvidence(scenario,logs,wallSeconds)
t=double(logs.time_s(:)); m=double(logs.desal_mechanical_response); h=double(logs.desal_hydraulic_response); r=double(logs.desal_recovery_response);
ma=~isempty(m);ha=~isempty(h);ra=~isempty(r);if isfield(logs,"mechanical_available"),ma=logs.mechanical_available;ha=logs.hydraulic_available;ra=logs.recovery_available;end
finiteAvailable=all(isfinite(t))&&(~ma||all(isfinite(m),"all"))&&(~ha||all(isfinite(h),"all"))&&(~ra||all(isfinite(r),"all"));
valid=ma&&ha&&ra&&numel(t)>=500&&t(1)<=1e-8&&t(end)>=59.9&&all(diff(t)>0)&&max(diff(t))<=0.100000001&& ...
    size(m,1)==numel(t)&&size(m,2)==3&&size(h,1)==numel(t)&&size(h,2)==4&& ...
    size(r,1)==numel(t)&&size(r,2)==3&&finiteAvailable;
item=struct("id",string(scenario.id),"valid",valid,"simulation_valid",true,"mechanical_available",ma,"hydraulic_available",ha,"recovery_available",ra,"wall_seconds",wallSeconds, ...
    "input",struct("wave_height_m",double(scenario.wave_height_m),"wave_period_s",double(scenario.wave_period_s)), ...
    "time_s",t,"desal_mechanical_response",m,"desal_hydraulic_response",h, ...
    "desal_recovery_response",r,"sample_count",numel(t), ...
    "maximum_sample_interval_s",localMaxDiff(t),"failure_identifier","","failure_message","");
end

function item=localInvalidScenario(scenario,exception,wallSeconds)
item=struct("id",string(scenario.id),"valid",false,"wall_seconds",wallSeconds, ...
    "input",struct("wave_height_m",double(scenario.wave_height_m),"wave_period_s",double(scenario.wave_period_s)), ...
    "time_s",[],"desal_mechanical_response",[],"desal_hydraulic_response",[], ...
    "desal_recovery_response",[],"sample_count",0,"maximum_sample_interval_s",Inf, ...
    "failure_identifier",string(exception.identifier),"failure_message",string(exception.message));
item.simulation_valid=false;item.mechanical_available=false;item.hydraulic_available=false;item.recovery_available=false;
end

function audit=localReferenceAudit(model)
blocks=find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");
text=strings(numel(blocks),1); connected=false(numel(blocks),1);
for index=1:numel(blocks)
    text(index)=lower(localSafeGet(blocks{index},"Name")+" "+localSafeGet(blocks{index},"SourceBlock"));
    connected(index)=localConnected(blocks{index});
end
hydro=contains(text,"hydrodynamic body")|contains(text,"wecsim_lib_body_elements/rigid body");
pto=contains(text,"pto"); cylinder=contains(text,"hydraulic cylinder");
membrane=contains(text,"ro membrane"); exchanger=contains(text,"pressure exchanger"); accumulator=contains(text,"gas-charged");
paths=[any(hydro&connected),any(pto&connected),any(cylinder&connected),any(membrane&connected),any(exchanger&connected),any(accumulator&connected)];
audit=struct("expanded_block_count",numel(blocks),"hydrodynamic_body_connected",paths(1), ...
    "pto_connected",paths(2),"hydraulic_cylinder_connected",paths(3),"ro_membrane_connected",paths(4), ...
    "pressure_exchanger_connected",paths(5),"accumulator_connected",paths(6), ...
    "mechanical_to_hydraulic_path",all(paths(1:4)),"brine_energy_recovery_path",all(paths([4 5 6])), ...
    "structure_qualified",all(paths));
end

function audit=localCandidateAudit(model)
blocks=find_system(model,"LookUnderMasks","all","FollowLinks","on","Type","Block");connected=0;
for index=1:numel(blocks),connected=connected+double(localConnected(blocks{index}));end
audit=struct("expanded_block_count",numel(blocks),"connected_block_count",connected,"method","implementation_neutral_connectivity_metadata_only","structure_qualified",false,"qualification_deferred_to_public_conservation_and_intervention_evidence",true);
end

function tf=localConnected(block)
tf=false;
try
    ports=get_param(block,"PortConnectivity");
    for index=1:numel(ports)
        if (~isempty(ports(index).SrcBlock)&&any(ports(index).SrcBlock~=-1))|| ...
                (~isempty(ports(index).DstBlock)&&any(ports(index).DstBlock~=-1))
            tf=true; return
        end
    end
catch
end
end

function localAssignCommand(scenario)
assignin("base","desal_command",struct("wave_height_m",double(scenario.wave_height_m), ...
    "wave_period_s",double(scenario.wave_period_s)));
end

function value=localPublicOutput(simOut,name)
value=[]; try,value=simOut.get(name);catch,end
if isempty(value)&&evalin("base","exist('"+name+"','var')~=0"),value=evalin("base",name);end
assert(isa(value,"timeseries"),"SimuVerity:EXT:DESALRequiredOutput","Required public Timeseries %s is missing.",name);
end

function [time,data]=localTimeseriesMatrix(value,width)
time=double(value.Time(:)); data=squeeze(double(value.Data));
if size(data,1)~=numel(time)&&size(data,2)==numel(time),data=data.';end
assert(size(data,1)==numel(time)&&size(data,2)==width,"SimuVerity:EXT:DESALOutputWidth","Expected %d channels.",width);
assert(all(isfinite(time))&&all(diff(time)>0),"SimuVerity:EXT:DESALTime","Invalid output time vector.");
end

function localClearNativeOutputs()
evalin("base",'clear simout simout1 response output');
end

function localClearPublicOutputs()
evalin("base",'clear desal_mechanical_response desal_hydraulic_response desal_recovery_response');
end

function localRestoreFileGeneration()
cache=string(getenv("SIMULINK_CACHE_FOLDER")); codegen=string(getenv("SIMULINK_CODEGEN_FOLDER"));
assert(strlength(cache)>0&&strlength(codegen)>0,"SimuVerity:EXT:DESALIsolation","Missing isolated file-generation paths.");
if ~isfolder(cache),mkdir(cache);end
if ~isfolder(codegen),mkdir(codegen);end
Simulink.fileGenControl("set","CacheFolder",cache,"CodeGenFolder",codegen,"createDir",true);
end

function spec=localOfficialSpec(taskId)
root=fileparts(mfilename("fullpath")); for level=1:4,root=fileparts(root);end
spec=jsondecode(fileread(simuverity_official_scenarios_path()));
end

function value=localSafeGet(block,parameter)
try,value=string(get_param(block,parameter));catch,value="";end
end

function value=localMaxDiff(time)
if numel(time)<2,value=Inf;else,value=max(diff(time));end
end

function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

function localWriteJsonAtomic(path,value)
temporary=tempname(fileparts(path))+".json"; fid=fopen(temporary,"w");
assert(fid>=0,"SimuVerity:EXT:DESALEvidenceWrite","Cannot write evidence."); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,"%s\n",jsonencode(value,PrettyPrint=true)); clear cleanup; movefile(temporary,path,"f");
end

function localClose(model)
try,if bdIsLoaded(model),close_system(model,0);end,catch,end
end

function value=localTernary(condition,yesValue,noValue)
if condition,value=yesValue;else,value=noValue;end
end
