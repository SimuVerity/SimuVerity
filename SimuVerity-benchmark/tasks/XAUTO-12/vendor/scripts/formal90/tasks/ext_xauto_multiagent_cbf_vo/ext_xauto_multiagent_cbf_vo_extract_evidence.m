function evidence = ext_xauto_multiagent_cbf_vo_extract_evidence(modelPath,outDir,officialScenarios,evaluatorAssetRoot)
% Extract fixed per-scenario evidence; scoring is intentionally offline.
% Uses the candidate-independent rounded-pi official fixture binding.
arguments
    modelPath (1,1) string
    outDir (1,1) string
    officialScenarios (1,1) string = ""
    evaluatorAssetRoot (1,1) string = ""
end
taskId="EXT-XAUTO-MULTIAGENT-CBF-VO";key="ext_xauto_multiagent_cbf_vo";spec=localSpec(taskId);
[~,model]=fileparts(modelPath);isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
if isReference
    assert(isfolder(evaluatorAssetRoot),"SimuVerity:EXT:CBFReferenceAssetRoot","Evaluator-owned reference asset root is missing.");
    sourceRoot=fullfile(evaluatorAssetRoot,"source","car_dynamics");
    assert(isfolder(sourceRoot),"SimuVerity:EXT:CBFSourceTree","Sealed source tree is missing.");
    oldDirectory=string(pwd);cd(sourceRoot);directoryCleanup=onCleanup(@()cd(oldDirectory)); %#ok<NASGU>
    addpath(sourceRoot,genpath(fullfile(sourceRoot,"setup_functions")),genpath(fullfile(sourceRoot,"generated_functions")), ...
        genpath(fullfile(sourceRoot,"scenarios")),genpath(fullfile(sourceRoot,"tools")));
    pathCleanup=onCleanup(@() rmpath(sourceRoot,genpath(fullfile(sourceRoot,"setup_functions")), ...
        genpath(fullfile(sourceRoot,"generated_functions")),genpath(fullfile(sourceRoot,"scenarios")),genpath(fullfile(sourceRoot,"tools")))); %#ok<NASGU>
else
    addpath(fileparts(modelPath));pathCleanup=onCleanup(@() rmpath(fileparts(modelPath))); %#ok<NASGU>
end
load_system(modelPath);modelCleanup=onCleanup(@() close_system(model,0)); %#ok<NASGU>
set_param(model,"SimulationMode","normal","ReturnWorkspaceOutputs","on");
localApplyMission(spec.scenarios(1),isReference);
set_param(model,"SimulationCommand","update");feval(model,[],[],[],"compile");feval(model,[],[],[],"term");
items=cell(numel(spec.scenarios),1);
for index=1:numel(spec.scenarios)
    scenario=spec.scenarios(index);
    try
        localApplyMission(scenario,isReference);
        simOut=sim(model,"StopTime",num2str(scenario.duration_s,17),"ReturnWorkspaceOutputs","on");
        if isReference
            logs=localReferenceLogs(simOut);items{index}=localMetrics(scenario,logs);items{index}.simulation_valid=true;items{index}.state_available=true;items{index}.control_available=true;
        else
            logs=localCandidateLogsPartial(simOut);items{index}=localMetricsPartial(scenario,logs);
        end
    catch exception
        if isReference,rethrow(exception);end
        items{index}=localInvalid(scenario,exception);
    end
end
items=vertcat(items{:});
evidence=struct("schema","simuverity.ext-xauto-multiagent-cbf-vo-evidence.v1","task_id",taskId, ...
    "model_path",modelPath,"adapter_mode",string(localChoose(isReference,"reference_native_bus","public_contract")), ...
    "candidate_contract_only",~isReference,"load_ok",true,"update_ok",true,"compile_ok",true, ...
    "simulate_ok",all([items.simulation_valid]),"required_outputs_complete",all([items.state_available])&&all([items.control_available]),"scenario_count",numel(items),"scenarios",items);
localWrite(fullfile(outDir,"evidence.json"),evidence);
end

function spec=localSpec(taskId)
root=fileparts(mfilename("fullpath"));for level=1:4,root=fileparts(root);end
spec=jsondecode(fileread(simuverity_official_scenarios_path()));
end
function localApplyMission(s,isReference)
mission=rmfield(s,"id");assignin("base","multiagent_mission",mission);
% Candidate evaluation exposes only the public base-workspace contract.
% The source-native config/global bridge is reserved for the sealed reference file binding.
if~isReference,return;end
config=struct("t_max",s.duration_s,"timestep",0.05,"geometric_tol",0.1,"R_circle",20, ...
    "R_agent",s.agent_radius_m,"p0_std",0,"v_mod",s.preferred_speed_mps,"v_max",10, ...
    "u_max",s.maximum_acceleration_mps2,"tan_phi_max",s.maximum_steering_tangent, ...
    "alpha_vo",100,"alpha_c",10,"k_u",1,"k_vo",1,"P",[1/5;1/2],"D",[0;0.1], ...
    "goal_reached_tol",1,"consider_only_min_t_col",false,"include_VO_as_hard_constraint",false, ...
    "max_iterations_fail",3,"use_safe_cbf",true);
global agentsInfo
agentsInfo=cell(1,8);
for agent=1:8
    info=struct("p",[s.initial_positions_m(agent,:) 0].',"v",s.initial_speeds_mps(agent), ...
        "theta",s.initial_headings_rad(agent),"p_goal",[s.goal_positions_m(agent,:) 0].', ...
        "dim",[s.agent_radius_m;s.agent_radius_m],"debug",true,"passive",logical(s.passive_agents(agent)));
    agentsInfo{agent}=info;
end
assignin("base","config",config);assignin("base","n_agents",8);assignin("base","cameraTranslation",[0 0 50]);assignin("base","cameraRotation",[0 90 90]);
assignin("base","agentsInfo",agentsInfo);
assignin("base","Ts",config.timestep);
end
function logs=localReferenceLogs(simOut)
t=[];state=[];control=[];
for agent=1:8
    native=simOut.get("agent"+agent);
    [xt,x]=localNativeField(native,"x");[gt,goal]=localNativeField(native,"goal_reached");
    [ut,u]=localNativeField(native,"u");[ct,cost]=localNativeField(native,"cost");[et,exitFlag]=localNativeField(native,"exit_flag");
    if isempty(t),t=xt;end
    x=localAt(xt,x,t);goal=localAt(gt,goal,t);u=localAt(ut,u,t);cost=localAt(ct,cost,t);exitFlag=localAt(et,exitFlag,t);
    assert(size(x,2)>=5&&size(u,2)>=2,"SimuVerity:EXT:CBFNativeWidth","Unexpected native agent bus width.");
    state(:,(agent-1)*5+(1:5))=[x(:,1:2) x(:,4:5) goal(:,1)]; %#ok<AGROW>
    control(:,(agent-1)*4+(1:4))=[u(:,1:2) cost(:,1) exitFlag(:,1)]; %#ok<AGROW>
end
logs=struct("t",t,"state",state,"control",control);
end
function [t,data]=localNativeField(native,name)
assert(isstruct(native)&&isfield(native,name),"SimuVerity:EXT:CBFNativeField","Missing native bus field %s.",name);value=native.(name);
if isa(value,"timeseries"),t=double(value.Time(:));data=squeeze(double(value.Data));
elseif isstruct(value)&&isfield(value,"Time")&&isfield(value,"Data"),t=double(value.Time(:));data=squeeze(double(value.Data));
elseif isstruct(value)&&isfield(value,"time")&&isfield(value,"signals"),t=double(value.time(:));data=squeeze(double(value.signals.values));
else,error("SimuVerity:EXT:CBFNativeType","Unsupported native bus field representation for %s.",name);end
if isvector(data),data=data(:);end;if size(data,1)~=numel(t)&&size(data,2)==numel(t),data=data.';end
assert(size(data,1)==numel(t),"SimuVerity:EXT:CBFNativeTime","Native time/data mismatch.");
end
function logs=localCandidateLogsPartial(simOut)
[t,state,stateOk]=localOptionalTimeseries(simOut,"agent_state",40);[ct,control,controlOk]=localOptionalTimeseries(simOut,"agent_control",32);
if stateOk&&controlOk,control=localAt(ct,control,t);elseif~stateOk&&controlOk,t=ct;end
logs=struct("t",t,"state",state,"control",control,"state_available",stateOk,"control_available",controlOk);
end
function [t,data,ok]=localOptionalTimeseries(simOut,name,width)
t=[];data=[];ok=false;try,value=simOut.get(name);catch,value=[];end
if~isa(value,"timeseries"),return;end
try,[t,data]=localTimeseries(value,width);ok=true;catch,t=[];data=[];end
end
function value=localOutput(simOut,name)
try,value=simOut.get(name);catch,value=[];end
assert(isa(value,"timeseries"),"SimuVerity:EXT:CBFRequiredLog","Required Timeseries %s is missing.",name);
end
function [t,data]=localTimeseries(value,width)
t=double(value.Time(:));data=squeeze(double(value.Data));if size(data,1)~=numel(t)&&size(data,2)==numel(t),data=data.';end
assert(size(data,1)==numel(t)&&size(data,2)==width,"SimuVerity:EXT:CBFLogWidth","Expected %d channels.",width);
end
function data=localAt(sourceTime,data,targetTime)
if numel(sourceTime)~=numel(targetTime)||any(abs(sourceTime-targetTime)>1e-12),data=interp1(sourceTime,data,targetTime,"previous","extrap");end
end

function item=localMetricsPartial(s,logs)
if logs.state_available&&logs.control_available
    item=localMetrics(s,logs);
elseif logs.state_available
    padded=logs;padded.control=zeros(numel(logs.t),32);item=localMetrics(s,padded);
    item.control_rms=0;item.avoidance_modulation=0;item.control_bound_violation_fraction=1;item.solver_exit_fraction=1;item.passive_control_rms=Inf;
else
    item=localInvalid(s,MException("SimuVerity:EXT:CBFPartialOutput","Public state output is unavailable."));
end
item.valid=logs.state_available&&logs.control_available&&item.valid;item.simulation_valid=true;
item.state_available=logs.state_available;item.control_available=logs.control_available;
item.state_width=40*double(logs.state_available);item.control_width=32*double(logs.control_available);
end

function item=localMetrics(s,logs)
n=numel(logs.t);positions=zeros(n,8,2);speeds=zeros(n,8);headings=zeros(n,8);goalsReached=zeros(n,8);controls=zeros(n,8,4);
for agent=1:8
    cols=(agent-1)*5+(1:5);positions(:,agent,:)=logs.state(:,cols(1:2));speeds(:,agent)=logs.state(:,cols(3));headings(:,agent)=logs.state(:,cols(4));goalsReached(:,agent)=logs.state(:,cols(5));
    controls(:,agent,:)=logs.control(:,(agent-1)*4+(1:4));
end
pairDistances=[];nearRows=false(n,1);
for a=1:8,for b=a+1:8
    d=sqrt(sum((squeeze(positions(:,a,:))-squeeze(positions(:,b,:))).^2,2));pairDistances=[pairDistances d];nearRows=nearRows|(d<5*s.agent_radius_m); %#ok<AGROW>
end,end
initialDistance=sqrt(sum((s.initial_positions_m-s.goal_positions_m).^2,2));finalPosition=squeeze(positions(end,:,:));finalDistance=sqrt(sum((finalPosition-s.goal_positions_m).^2,2));
active=~logical(s.passive_agents(:));progress=(initialDistance-finalDistance)./max(initialDistance,1e-9);
dt=diff(logs.t);velocityFromPosition=diff(positions,1,1)./reshape(dt,[],1,1);velocityModel=zeros(n-1,8,2);
for agent=1:8,velocityModel(:,agent,1)=speeds(1:end-1,agent).*cos(headings(1:end-1,agent));velocityModel(:,agent,2)=speeds(1:end-1,agent).*sin(headings(1:end-1,agent));end
steering=squeeze(controls(:,:,1));acceleration=squeeze(controls(:,:,2));exitFlags=squeeze(controls(:,:,4));
if any(nearRows)&&any(~nearRows),avoidanceModulation=abs(localRms(steering(nearRows,:))-localRms(steering(~nearRows,:)));else,avoidanceModulation=std(steering,0,"all");end
passiveError=0;passiveControl=0;
for agent=find(~active).'
    expected=s.initial_positions_m(agent,:)+logs.t.*(s.initial_speeds_mps(agent)*[cos(s.initial_headings_rad(agent)) sin(s.initial_headings_rad(agent))]);
    passiveError=max(passiveError,sqrt(mean((squeeze(positions(:,agent,:))-expected).^2,"all")));passiveControl=max(passiveControl,localRms(controls(:,agent,1:2)));
end
activePosition=positions(:,active,:);activeGoal=reshape(s.goal_positions_m(active,:),1,sum(active),2);
copyFraction=mean(max(abs(activePosition-activeGoal),[],3)<=1e-9,"all");finiteAll=all(isfinite([logs.state(:);logs.control(:)]));coverage=logs.t(end)/s.duration_s;
item=struct("id",s.id,"valid",finiteAll&&logs.t(1)<=1e-9&&coverage>=0.999,"duration_s",s.duration_s, ...
    "coverage_fraction",coverage,"finite",finiteAll,"state_width",size(logs.state,2),"control_width",size(logs.control,2), ...
    "minimum_pair_distance_m",min(pairDistances,[],"all"),"minimum_separation_margin_m",min(pairDistances,[],"all")-2*s.agent_radius_m, ...
    "collision_fraction",mean(pairDistances<2*s.agent_radius_m,"all"),"mean_active_progress",mean(progress(active)), ...
    "worst_active_progress",min(progress(active)),"mean_terminal_goal_error_m",mean(finalDistance(active)), ...
    "kinematic_rmse_mps",sqrt(mean((velocityFromPosition-velocityModel).^2,"all")), ...
    "control_rms",localRms(controls(:,active,1:2)),"avoidance_modulation",avoidanceModulation, ...
    "control_bound_violation_fraction",mean(abs(steering(:,active))>s.maximum_steering_tangent+1e-6|abs(acceleration(:,active))>s.maximum_acceleration_mps2+1e-6,"all"), ...
    "solver_exit_fraction",mean(exitFlags(:,active)~=0,"all"),"passive_motion_rmse_m",passiveError,"passive_control_rms",passiveControl, ...
    "goal_copy_fraction",copyFraction,"mission_signature",[s.initial_positions_m(:).' s.goal_positions_m(:).'], ...
    "response_signature",[finalPosition(:).' mean(steering,1) mean(acceleration,1)], ...
    "failure_identifier","","failure_message","");
end
function item=localInvalid(s,e)
item=struct("id",s.id,"valid",false,"duration_s",s.duration_s,"coverage_fraction",0,"finite",false,"state_width",0,"control_width",0, ...
    "minimum_pair_distance_m",0,"minimum_separation_margin_m",-Inf,"collision_fraction",1,"mean_active_progress",0,"worst_active_progress",0, ...
    "mean_terminal_goal_error_m",Inf,"kinematic_rmse_mps",Inf,"control_rms",0,"avoidance_modulation",0, ...
    "control_bound_violation_fraction",1,"solver_exit_fraction",1,"passive_motion_rmse_m",Inf,"passive_control_rms",Inf, ...
    "goal_copy_fraction",1,"mission_signature",zeros(1,32),"response_signature",zeros(1,32), ...
    "failure_identifier",string(e.identifier),"failure_message",string(e.message));
item.simulation_valid=false;item.state_available=false;item.control_available=false;
end
function localWrite(path,value)
if~isfolder(fileparts(path)),mkdir(fileparts(path));end;tmp=tempname(fileparts(path))+".json";fid=fopen(tmp,"w");assert(fid>=0,"SimuVerity:EXT:CBFWrite","Cannot write evidence.");c=onCleanup(@()localSafeClose(fid));fprintf(fid,"%s\n",jsonencode(value,PrettyPrint=true));fclose(fid);clear c;movefile(tmp,path,"f");
end
function localSafeClose(fid),if fid>=0,try,fclose(fid);catch,end,end,end
function value=localRms(data),value=sqrt(mean(double(data).^2,"all"));end
function v=localChoose(c,a,b),if c,v=a;else,v=b;end,end
function binding = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
binding = "present";
end

