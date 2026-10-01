function evidence = f90_xrobo06_extract_candidate_evidence( ...
        candidatePath, outDir)
%f90_xrobo06_extract_candidate_evidence Candidate humanoid replay.
% SCORING_CORE only fixes the R2025a cellstr/string INTERSECT incompatibility in the
% scenario-field filtering used by the METRICS evaluator.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
[taskRoot,sharedRoot]=localRoots("F90-XROBO-06");
addpath(sharedRoot,"-begin");cleanup=onCleanup(@()rmpath(sharedRoot)); %#ok<NASGU>
official=jsondecode(fileread(simuverity_official_scenarios_path()));
spec=struct("schema","simuverity.f90-xrobo06-evidence.v1", ...
    "task_id","F90-XROBO-06","scenarios",official.scenarios, ...
    "output_contract",localOutputs,"input_builder",@localInputs, ...
    "requested_input_builder",@localRequested, ...
    "stop_time",@(s,~)double(s.stop_time_s), ...
    "postprocess",@localPostprocess,"static_audit",@localAudit, ...
    "evidence_sample_s",0.01);
evidence=simuverity_run_candidate_evidence(candidatePath,outDir,spec);
end
function rows=localOutputs
names=["TorsoState","JointState","FootContact","ControlAction", ...
    "JointTorque","TaskState"];evidenceNames=["torso_state","joint_state", ...
    "foot_contact","control_action","joint_torque","task_state"];
widths=[11 12 2 6 6 3];
rows=repmat(struct("name","","evidence_name","","width",0, ...
    "interpolation","linear"),numel(names),1);
for k=1:numel(names),rows(k).name=names(k); ...
    rows(k).evidence_name=evidenceNames(k);rows(k).width=widths(k);end
rows(3).interpolation="previous";rows(6).interpolation="previous";
end
function inputs=localInputs(s,~)
inputs=rmfield(s,intersect(fieldnames(s),{'id','class','stop_time_s'}));
end
function requested=localRequested(s,~)
requested=rmfield(s,intersect(fieldnames(s),{'id','class'}));
end
function row=localPostprocess(row,outputs,~,~)
joint=double(outputs.joint_state);torque=double(outputs.joint_torque);
rates=joint(:,2:2:12);task=double(outputs.task_state);
outputs.forward_position_m=task(:,1);
outputs.reward=task(:,2);
outputs.done=task(:,3);
outputs.power_w=sum(torque.*rates,2);
row.outputs=outputs;row.valid=row.output_contract.all_required_pass;
end
function audit=localAudit(model,spec)
structure=simuverity_candidate_structure(model,string({spec.output_contract.name})');
semantic=structure.semantic_types;
multibody=nnz(contains(semantic,["multibody","rigid transform"]));
contact=nnz(contains(semantic,["spatial contact","contact force"]));
actuator=nnz(contains(semantic,["joint actuator","torque source"]));
controller=nnz(contains(semantic,["policy","reinforcement","controller"]));
audit=struct("multibody_block_count",multibody,"foot_contact_count",contact, ...
    "actuation_count",actuator,"controller_count",controller, ...
    "core_path_qualified", ...
        structure.connected_output_count==numel(spec.output_contract)&& ...
        structure.nontrivial_output_source_count==numel(spec.output_contract)&& ...
        structure.physical_connection_block_count>=6&&multibody>=2&& ...
        contact>=2&&actuator>=6&&controller>=1&&structure.signal_cycle_present);
end
function [taskRoot,sharedRoot]=localRoots(taskId)
scriptRoot=fileparts(mfilename("fullpath"));tasksRoot=fileparts(scriptRoot);
sharedRoot=fullfile(tasksRoot,"_shared");repoRoot=tasksRoot;
for k=1:3,repoRoot=fileparts(repoRoot);end
taskRoot=string(getenv("SIMUVERITY_TASK_ROOT"));
end
