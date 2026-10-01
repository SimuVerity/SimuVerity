function evidence = f90_xrobo09_extract_candidate_evidence(candidatePath,outDir)
%f90_xrobo09_extract_candidate_evidence Bounded official-traffic extraction.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
[taskRoot,sharedRoot]=localRoots("F90-XROBO-09");
addpath(sharedRoot,"-begin");cleanup=onCleanup(@()rmpath(sharedRoot)); %#ok<NASGU>
official=jsondecode(fileread(simuverity_official_scenarios_path()));
spec=struct("schema","simuverity.f90-xrobo09-evidence.v1", ...
    "task_id","F90-XROBO-09","scenarios",official.scenarios, ...
    "output_contract",localOutputs,"input_builder",@(s,~)localInputs(s,taskRoot), ...
    "requested_input_builder",@localRequested, ...
    "stop_time",@(s,~)double(s.stop_time_s),"postprocess",@localPostprocess, ...
    "static_audit",@localAudit,"evidence_sample_s",0.1);
evidence=simuverity_run_candidate_evidence(candidatePath,outDir,spec);
end

function rows=localOutputs
names=["VesselState","GuidanceState","PropulsionState","TrafficState","OperatingState"];
evidence=["vessel_state","guidance_state","propulsion_state","traffic_state","operating_state"];
widths=[14 7 6 30 4];
rows=repmat(struct("name","","evidence_name","","width",0,"interpolation","linear"),numel(names),1);
for k=1:numel(names)
    rows(k).name=names(k);rows(k).evidence_name=evidence(k);rows(k).width=widths(k);
end
rows(2).interpolation="previous";rows(4).interpolation="previous";rows(5).interpolation="previous";
end

function inputs=localInputs(scenario,taskRoot)
inputs=localRequested(scenario,struct);inputs.TrafficMotion=localTrafficMotion(scenario,taskRoot);
end
function inputs=localRequested(scenario,~)
inputs=rmfield(scenario,intersect(fieldnames(scenario), ...
    {'id','class','scenario_mat','stop_time_s'}));
end

function value=localTrafficMotion(scenario,taskRoot)
fixture=fullfile(taskRoot,"reference","MarineVessel",string(scenario.scenario_mat));
assert(isfile(fixture), ...
    "SimuVerity:F90:XROBO09:OfficialFixture","Official traffic fixture is missing.");
payload=load(fixture);fields=string(fieldnames(payload));scene=[];
for field=fields'
    candidate=payload.(char(field));
    if isa(candidate,"uavScenario"),scene=candidate;break,end
end
assert(~isempty(scene),"SimuVerity:F90:XROBO09:OfficialFixture","Pinned traffic fixture contains no uavScenario.");
stop=double(scenario.stop_time_s);
assert(isscalar(stop)&&isfinite(stop)&&stop>0, ...
    "SimuVerity:F90:XROBO09:OfficialFixture","Scenario stop_time_s must be finite and positive.");
setup(scene); % Fresh exported scenario is already at t=0; pre-setup restart is invalid in R2025a.
platforms=scene.Platforms;names=strings(numel(platforms),1);
for k=1:numel(platforms),names(k)=string(platforms(k).Name);end
traffic=find(~contains(lower(names),"ego"));
if numel(traffic)==numel(platforms)&&numel(traffic)>1,traffic=traffic(2:end);end
traffic=traffic(1:min(3,numel(traffic)));
nativeTime=zeros(0,1);nativeData=zeros(0,18);
[nativeTime,nativeData]=localAppendTraffic(nativeTime,nativeData,double(scene.CurrentTime),platforms,traffic);
% Exported R2025a uavScenario fixtures intentionally use StopTime=Inf.  Bound
% advancement by the task-owned finite horizon instead of advancing forever.
while double(scene.CurrentTime)<stop && advance(scene)
    [nativeTime,nativeData]=localAppendTraffic(nativeTime,nativeData,double(scene.CurrentTime),platforms,traffic);
end
assert(double(scene.CurrentTime)>=stop-1/max(1,double(scene.UpdateRate)), ...
    "SimuVerity:F90:XROBO09:OfficialFixture","Traffic fixture ended before the task-owned horizon.");
[nativeTime,index]=unique(nativeTime,"stable");nativeData=nativeData(index,:);
time=(0:0.1:stop)';data=zeros(numel(time),18);
for vessel=1:3
    columns=(vessel-1)*6+(1:6);if vessel>numel(traffic),continue,end
    valid=nativeData(:,columns(6))>0.5 & all(isfinite(nativeData(:,columns(1:5))),2);
    assert(nnz(valid)>=2,"SimuVerity:F90:XROBO09:OfficialFixture","Traffic vessel %d lacks a valid trajectory.",vessel);
    for channel=1:4
        data(:,columns(channel))=interp1(nativeTime(valid),nativeData(valid,columns(channel)),time,"linear","extrap");
    end
    yaw=unwrap(nativeData(valid,columns(5)));
    data(:,columns(5))=mod(interp1(nativeTime(valid),yaw,time,"linear","extrap")+pi,2*pi)-pi;
    data(:,columns(6))=double(time>=nativeTime(find(valid,1)) & time<=nativeTime(find(valid,1,"last")));
end
value=timeseries(data,time);
end

function [time,data]=localAppendTraffic(time,data,current,platforms,traffic)
row=zeros(1,18);
for vessel=1:numel(traffic)
    motion=double(read(platforms(traffic(vessel))));columns=(vessel-1)*6+(1:6);
    if numel(motion)>=13&&all(isfinite(motion([1 2 4 5 10:13])))
        q=motion(10:13);yaw=atan2(2*(q(1)*q(4)+q(2)*q(3)),1-2*(q(3)^2+q(4)^2));
        row(columns)=[motion(1),motion(2),motion(4),motion(5),yaw,1];
    end
end
time(end+1,1)=current;data(end+1,:)=row;
end

function row=localPostprocess(row,outputs,~,~)
row.outputs=outputs;row.valid=row.output_contract.all_required_pass;
end

function audit=localAudit(model,spec)
fields=["vessel_platform_present","closed_loop_controller_present","six_dof_core_present", ...
    "hydrodynamic_core_present","hydrostatic_core_present","current_crossflow_core_present", ...
    "twin_propeller_thrust_core_present","traffic_ground_truth_assessment_present", ...
    "collision_avoidance_planning_present","waypoint_guidance_present", ...
    "control_allocation_present","controller_to_vessel_connected", ...
    "vessel_feedback_to_controller_connected","scenario_to_controller_connected", ...
    "environment_to_vessel_connected"];
audit=struct("audit_complete",false,"audit_error_identifier","","audit_error_message","");
for field=fields,audit.(char(field))=false;end
try
    structure=simuverity_candidate_structure(model,string({spec.output_contract.name})');
    semantic=string(structure.semantic_types);
    sixdof=nnz(contains(semantic,["6dof","six-dof","quaternion","rigid body"]));
    hydro=nnz(contains(semantic,["hydrodynamic","drag","added mass"]));
    propeller=nnz(contains(semantic,["propeller","thrust","motor"]));
    controller=nnz(contains(semantic,["controller","pid","stateflow"]));
    planning=nnz(contains(semantic,["collision","guidance","planner","matlab function","matlab system"]));
    connected=structure.connected_output_count==numel(spec.output_contract) && ...
        structure.nontrivial_output_source_count==numel(spec.output_contract);
    feedback=structure.signal_cycle_present && controller>=1;
    audit.audit_complete=true;
    audit.vessel_platform_present=sixdof>=1;audit.closed_loop_controller_present=feedback;
    audit.six_dof_core_present=sixdof>=1;audit.hydrodynamic_core_present=hydro>=1;
    audit.hydrostatic_core_present=sixdof>=1;audit.current_crossflow_core_present=hydro>=1;
    audit.twin_propeller_thrust_core_present=propeller>=2;
    audit.traffic_ground_truth_assessment_present=planning>=1;
    audit.collision_avoidance_planning_present=planning>=1;audit.waypoint_guidance_present=planning>=1;
    audit.control_allocation_present=controller>=1&&propeller>=2;
    audit.controller_to_vessel_connected=feedback;audit.vessel_feedback_to_controller_connected=feedback;
    audit.scenario_to_controller_connected=connected&&planning>=1;
    audit.environment_to_vessel_connected=connected&&hydro>=1;
catch ME
    audit.audit_error_identifier=string(ME.identifier);
    audit.audit_error_message=string(ME.message);
end
end

function [taskRoot,sharedRoot]=localRoots(taskId)
scriptRoot=fileparts(mfilename("fullpath"));tasksRoot=fileparts(scriptRoot);sharedRoot=fullfile(tasksRoot,"_shared");
repoRoot=tasksRoot;for k=1:3,repoRoot=fileparts(repoRoot);end
taskRoot=string(getenv("SIMUVERITY_TASK_ROOT"));
end

