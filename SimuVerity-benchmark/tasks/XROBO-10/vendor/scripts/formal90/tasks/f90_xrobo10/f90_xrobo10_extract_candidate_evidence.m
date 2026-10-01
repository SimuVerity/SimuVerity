function evidence = f90_xrobo10_extract_candidate_evidence( ...
        candidatePath, outDir)
%f90_xrobo10_extract_candidate_evidence Candidate-only replay.
% SCORING_CORE corrects line_supervisor to the 19 channels explicitly required by
% the public specification and the delivered Agent prompt.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
[taskRoot,sharedRoot]=localRoots("F90-XROBO-10");
addpath(sharedRoot,"-begin");cleanup=onCleanup(@()rmpath(sharedRoot)); %#ok<NASGU>
official=jsondecode(fileread(simuverity_official_scenarios_path()));
spec=struct("schema","simuverity.f90-xrobo10-evidence.v1", ...
    "task_id","F90-XROBO-10","scenarios",official.scenarios, ...
    "output_contract",localOutputs,"input_builder",@localInputs, ...
    "requested_input_builder",@localInputs, ...
    "stop_time",@(~,~)double(official.simulation.stop_s), ...
    "postprocess",@localPostprocess,"static_audit",@localAudit, ...
    "evidence_sample_s",double(official.simulation.evidence_resample_s));
evidence=simuverity_run_candidate_evidence(candidatePath,outDir,spec);
end
function rows=localOutputs
names=["robot1_joint_reference","robot1_joint_state","robot1_joint_torque", ...
    "robot2_joint_reference","robot2_joint_state","robot2_joint_torque", ...
    "line_supervisor","task_state","actor_transfer_state"];
widths=[18 18 6 18 18 6 19 2 5];
rows=repmat(struct("name","","evidence_name","","width",0, ...
    "interpolation","linear"),numel(names),1);
for k=1:numel(names),rows(k).name=names(k);rows(k).evidence_name=names(k); ...
    rows(k).width=widths(k);end
for k=[7 8 9],rows(k).interpolation="previous";end
end
function inputs=localInputs(s,~),inputs=rmfield(s,"id");end
function row=localPostprocess(row,outputs,~,~)
state=double(outputs.actor_transfer_state);
line=double(outputs.line_supervisor);time=double(outputs.time_s(:));
codes=[1 3 4 6 8];events=zeros(0,3);
for channel=1:5
    rise=find(state(:,channel)>=0.5 & [true;state(1:end-1,channel)<0.5]);
    for index=reshape(rise,1,[])
        instance=round(line(index,17));
        if instance<=0,instance=1;end
        events(end+1,:)=[time(index),codes(channel),instance]; %#ok<AGROW>
    end
end
outputs.actor_event_log=events;
row.outputs=outputs;row.valid=row.output_contract.all_required_pass;
end
function audit=localAudit(model,spec)
structure=simuverity_candidate_structure( ...
    model,string({spec.output_contract.name})');
semantic=structure.semantic_types;
robot=nnz(contains(semantic,["multibody","rigid transform","revolute joint"]));
actuator=nnz(contains(semantic,["joint actuator","torque source"]));
supervisor=nnz(contains(semantic,["stateflow","matlab function","controller"]));
core=structure.connected_output_count==numel(spec.output_contract) && ...
    structure.nontrivial_output_source_count==numel(spec.output_contract) && ...
    structure.physical_connection_block_count>=8 && robot>=4 && ...
    actuator>=2 && supervisor>=1;
audit=struct("two_robot_workcells",robot>=4 && actuator>=2, ...
    "robot1_torque_to_dynamics",actuator>=2, ...
    "robot2_torque_to_dynamics",actuator>=2, ...
    "supervisory_logic_present",supervisor>=1, ...
    "connected_public_output_count",structure.connected_output_count, ...
    "core_path_qualified",core);
end
function [taskRoot,sharedRoot]=localRoots(taskId)
scriptRoot=fileparts(mfilename("fullpath"));tasksRoot=fileparts(scriptRoot);
sharedRoot=fullfile(tasksRoot,"_shared");repoRoot=tasksRoot;
for k=1:3,repoRoot=fileparts(repoRoot);end
taskRoot=string(getenv("SIMUVERITY_TASK_ROOT"));
end
