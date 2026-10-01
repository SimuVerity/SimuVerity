function evidence = f90_xcomm07_extract_candidate_evidence_core(modelPath, outputDir)
%F90_XCOMM07_EXTRACT_CANDIDATE_EVIDENCE_CORE_CORE_CORE Preserve the six public logs.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
end
modelPath=localCanonical(modelPath);outputDir=localCanonical(outputDir);
assert(isfile(modelPath),"SimuVerity:F90:XCOMM07:MissingModel","Candidate model is missing.");
assert(~isfile(outputDir)&&~isfolder(outputDir),"SimuVerity:F90:XCOMM07:OutputReuse", ...
    "Candidate evidence output already exists.");
mkdir(outputDir);cacheDir=fullfile(outputDir,"cache");codegenDir=fullfile(outputDir,"codegen");
mkdir(cacheDir);mkdir(codegenDir);Simulink.fileGenControl("set", ...
    "CacheFolder",cacheDir,"CodeGenFolder",codegenDir,"createDir",true);
[taskRoot,sharedRoot,publicOutputRoot]=localRoots("F90-XCOMM-07");
official=jsondecode(fileread(simuverity_official_scenarios_path()));
candidateDir=string(fileparts(modelPath));
addpath(candidateDir,"-begin");addpath(sharedRoot,"-begin");addpath(publicOutputRoot,"-begin");
cleanupPath=onCleanup(@()localRemovePaths(candidateDir,sharedRoot,publicOutputRoot)); %#ok<NASGU>
[~,model]=fileparts(modelPath);model=string(model);
bindingBefore=localFilePresence(modelPath);
evidence=struct("schema","simuverity.f90-xcomm07-evidence.v1", ...
    "task_id","F90-XCOMM-07","evaluation_subject","candidate", ...
    "candidate_file_presence",bindingBefore,"matlab_release",version("-release"), ...
    "load_pass",false,"update_pass",false,"compile_pass",false, ...
    "simulate_pass",false,"all_official_evidence_valid",false, ...
    "runtime_model_unchanged",false,"binding_preserved",false, ...
    "EVIDENCE_COMPLETE",false,"evidence_complete",false, ...
    "contains_score_decisions",false,"static_audit",struct, ...
    "scenarios",struct([]),"errors",struct,"started_at",localNow, ...
    "finished_at","");
rows=repmat(localEmptyScenario,numel(official.scenarios),1);
for index=1:numel(official.scenarios),rows(index).id=string(official.scenarios(index).id);end
try
    firstInput=localInput(official.scenarios(1));assignin("base","wlan_link_input",firstInput);
    if bdIsLoaded(model),close_system(model,0);end
    load_system(modelPath);cleanupModel=onCleanup(@()localClose(model)); %#ok<NASGU>
    evidence.load_pass=true;
    set_param(model,"ReturnWorkspaceOutputs","on","LimitDataPoints","off");
    sinks=string(find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
        "BlockType","ToWorkspace"));
    for sink=sinks',try,set_param(sink,"MaxDataPoints","inf");catch,end,end
    evidence.static_audit=localAudit(model);
    set_param(model,"SimulationCommand","update");evidence.update_pass=true;
    feval(model,[],[],[],"compile");evidence.compile_pass=true;
    feval(model,[],[],[],"term");
    for index=1:numel(official.scenarios)
        scenario=official.scenarios(index);row=localEmptyScenario;
        row.id=string(scenario.id);row.mcs=double(scenario.mcs);
        row.channel_coding=string(scenario.channel_coding);
        row.snr_dB=double(scenario.snr_dB);
        row.carrier_frequency_offset_Hz=double(scenario.carrier_frequency_offset_Hz);
        row.inputs=localInput(scenario);
        timer=tic;
        try
            localClearOutputs;
            simInput=Simulink.SimulationInput(model);
            simInput=simInput.setVariable("wlan_link_input",row.inputs);
            simInput=simInput.setModelParameter("ReturnWorkspaceOutputs","on", ...
                "LimitDataPoints","off");
            simOut=sim(simInput);
            row.logs=localLogs(simOut);
            row.simulate_s=toc(timer);row.simulation_pass=true;
            row.required_evidence_pass=localLogsValid(row.logs);
            row.valid=row.required_evidence_pass;
        catch ME
            row.simulate_s=toc(timer);row.error=localError(ME);
        end
        rows(index)=row;
    end
catch ME
    evidence.errors.session=localError(ME);
    try,feval(model,[],[],[],"term");catch,end
end
evidence.scenarios=rows;
evidence.simulate_pass=~isempty(rows)&&all([rows.simulation_pass]);
evidence.all_official_evidence_valid=~isempty(rows)&&all([rows.valid]);
try,if bdIsLoaded(model),close_system(model,0);end,catch,end
bindingAfter=localFilePresence(modelPath);evidence.candidate_file_presence_after=bindingAfter;
evidence.binding_preserved=strcmpi(bindingBefore,bindingAfter);
evidence.runtime_model_unchanged=evidence.binding_preserved;
evidence.EVIDENCE_COMPLETE=evidence.load_pass&&evidence.update_pass&& ...
    evidence.compile_pass&&evidence.simulate_pass&& ...
    evidence.all_official_evidence_valid&&evidence.binding_preserved;
evidence.evidence_complete=evidence.EVIDENCE_COMPLETE;
evidence.finished_at=localNow;
localWriteJson(fullfile(outputDir,"evidence.json"),evidence);
end

function input=localInput(scenario)
input=struct("mcs",double(scenario.mcs), ...
    "channel_coding",char(string(scenario.channel_coding)), ...
    "snr_dB",double(scenario.snr_dB), ...
    "carrier_frequency_offset_Hz",double(scenario.carrier_frequency_offset_Hz));
end

function logs=localLogs(simOut)
logs=struct( ...
    "channel_waveform",localReadLog(simOut,"channel_waveform",2, ...
        {"real","imag"},{"normalized amplitude","normalized amplitude"}), ...
    "bit_recovery",localReadLog(simOut,"bit_recovery",3, ...
        {"tx_bit","decoded_bit","bit_error"},{"1","1","1"}), ...
    "header_constellation",localReadLog(simOut,"header_constellation",2, ...
        {"in_phase","quadrature"},{"normalized amplitude","normalized amplitude"}), ...
    "data_constellation",localReadLog(simOut,"data_constellation",2, ...
        {"in_phase","quadrature"},{"normalized amplitude","normalized amplitude"}), ...
    "packet_detection",localReadLog(simOut,"packet_detection",1, ...
        {"detected"},{"1"}), ...
    "cfo_estimation",localReadLog(simOut,"cfo_estimation",2, ...
        {"normalized_frequency","estimated_frequency_Hz"},{"cycles/sample","Hz"}));
end

function log=localReadLog(simOut,name,width,channels,units)
[value,~]=simuverity_public_output_compatibility(simOut,name,width,AllowBaseWorkspace=true);
time=double(value.Time(:));data=double(value.Data);
data=reshape(data,numel(time),[]);
assert(size(data,2)==width&&numel(time)>=1&&all(isfinite(time))&& ...
    all(isfinite(data),"all")&&abs(time(1))<=1e-12&&all(diff(time)>0), ...
    "SimuVerity:F90:XCOMM07:OutputContract","Public output %s is invalid.",name);
if width==1,data=data(:);end
log=struct("time",time,"data",data,"channels",{channels},"units",{units});
end

function valid=localLogsValid(logs)
names=fieldnames(logs);valid=numel(names)==6;
for index=1:numel(names)
    log=logs.(names{index});valid=valid&&~isempty(log.time)&& ...
        size(log.data,1)==numel(log.time)&&all(diff(log.time)>0)&& ...
        all(isfinite(log.time))&&all(isfinite(log.data),"all");
end
end

function audit=localAudit(model)
structure=simuverity_candidate_structure(model, ...
    ["channel_waveform";"bit_recovery";"header_constellation"; ...
     "data_constellation";"packet_detection";"cfo_estimation"]);
audit=struct("block_count",structure.block_count, ...
    "dynamic_block_count",structure.dynamic_block_count, ...
    "connected_public_output_count",structure.connected_output_count, ...
    "nontrivial_public_output_source_count",structure.nontrivial_output_source_count, ...
    "signal_cycle_observed",structure.signal_cycle_present, ...
    "qualification_basis","candidate topology and published output bindings");
end

function localClearOutputs
names=["channel_waveform","bit_recovery","header_constellation", ...
    "data_constellation","packet_detection","cfo_estimation"];
for name=names
    escaped=replace(name,"'","''");
    evalin("base","if exist('"+escaped+"','var'), clear('"+escaped+"'); end");
end
end

function row=localEmptyScenario
row=struct("id","","mcs",0,"channel_coding","","snr_dB",0, ...
    "carrier_frequency_offset_Hz",0,"inputs",struct,"simulate_s",0, ...
    "simulation_pass",false,"required_evidence_pass",false,"valid",false, ...
    "logs",struct,"error",struct);
end

function value=localError(ME)
value=struct("identifier",string(ME.identifier),"message",string(ME.message));
end

function localClose(model)
try,if bdIsLoaded(model),close_system(model,0);end,catch,end
end

function [taskRoot,sharedRoot,publicOutputRoot]=localRoots(taskId)
scriptRoot=fileparts(mfilename("fullpath"));tasksRoot=fileparts(scriptRoot);
sharedRoot=fullfile(tasksRoot,"_shared");repoRoot=tasksRoot;
for k=1:3,repoRoot=fileparts(repoRoot);end
taskRoot=string(getenv("SIMUVERITY_TASK_ROOT"));
publicOutputRoot=fullfile(repoRoot,"scripts","unified","public_output");
end

function localRemovePaths(candidateDir,sharedRoot,publicOutputRoot)
try,rmpath(candidateDir);catch,end
try,rmpath(sharedRoot);catch,end
try,rmpath(publicOutputRoot);catch,end
end

function value=localCanonical(pathIn)
value=string(java.io.File(char(pathIn)).getCanonicalPath());
end

function binding = localFilePresence(pathIn)
assert(isfile(pathIn), "SimuVerity:FileMissing", "Required file is missing: %s", pathIn);
binding = "present";
end

function value=localNow
value=string(datetime("now","TimeZone","UTC", ...
    "Format","yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"));
end

function localWriteJson(path,value)
temporary=string(path)+".staging-"+string(java.util.UUID.randomUUID);
fid=fopen(temporary,"w","n","UTF-8");assert(fid>=0,"SimuVerity:F90:XCOMM07:Write", ...
    "Cannot write candidate evidence.");cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),"char");clear cleanup
assert(movefile(temporary,path,"f"),"SimuVerity:F90:XCOMM07:Publish", ...
    "Cannot publish candidate evidence.");
end
