function evidence = f90_xrobo08_extract_candidate_evidence( ...
        candidatePath, outDir)
%f90_xrobo08_extract_candidate_evidence Public-contract adapter.
% SCORING_CORE only fixes the R2025a cellstr/string INTERSECT incompatibility.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
[taskRoot,sharedRoot]=localRoots("F90-XROBO-08");
addpath(sharedRoot,"-begin");cleanup=onCleanup(@()rmpath(sharedRoot)); %#ok<NASGU>
official=jsondecode(fileread(simuverity_official_scenarios_path()));
spec=struct("schema","simuverity.f90-xrobo08-evidence.v1", ...
    "task_id","F90-XROBO-08","scenarios",official.scenarios, ...
    "output_contract",localOutputs,"input_builder",@localInputs, ...
    "requested_input_builder",@localRequested, ...
    "stop_time",@(s,~)double(s.stop_time_s), ...
    "postprocess",@localPostprocess,"static_audit",@localAudit, ...
    "evidence_sample_s",0.01);
evidence=simuverity_run_candidate_evidence(candidatePath,outDir,spec);
end
function rows=localOutputs
names=["BallState","PlateState","ActuatedJointState","ControlState","TaskState"];
evidence=["ball_state","plate_state","actuated_joint_state","control_state", ...
    "task_state"]; widths=[4 8 4 4 2];
rows=repmat(struct("name","","evidence_name","","width",0, ...
    "interpolation","linear"),numel(names),1);
for k=1:numel(names),rows(k).name=names(k); ...
    rows(k).evidence_name=evidence(k);rows(k).width=widths(k);end
end
function inputs=localInputs(s,~)
inputs=rmfield(s,intersect(fieldnames(s),{'id','class','stop_time_s'}));
end
function inputs=localRequested(s,~)
inputs=rmfield(s,intersect(fieldnames(s),{'id','class'}));
end
function row=localPostprocess(row,outputs,scenario,~)
row.outputs=outputs;
row.applied_parameters=localInputs(scenario,struct);
row.valid=row.output_contract.all_required_pass;
end
function audit=localAudit(model,spec)
structure=simuverity_candidate_structure( ...
    model,string({spec.output_contract.name})');
semantic=structure.semantic_types;
multibody=nnz(contains(semantic,["multibody","simscape"]));
contact=nnz(contains(semantic,["spatial contact","contact force"]));
actuation=nnz(contains(semantic,["joint actuator","torque source"]));
controller=nnz(contains(semantic,["reinforcement","policy","controller","pid"]));
core=structure.connected_output_count==numel(spec.output_contract) && ...
    structure.nontrivial_output_source_count==numel(spec.output_contract) && ...
    structure.physical_connection_block_count>=4 && multibody>=2 && ...
    contact>=1 && actuation>=1 && controller>=1;
audit=struct("spatial_contact_present",contact>=1, ...
    "observation_to_controller",controller>=1 && ...
        structure.signal_cycle_present, ...
    "multibody_block_count",multibody,"actuation_count",actuation, ...
    "connected_public_output_count",structure.connected_output_count, ...
    "core_path_qualified",core);
end
function [taskRoot,sharedRoot]=localRoots(taskId)
scriptRoot=fileparts(mfilename("fullpath"));tasksRoot=fileparts(scriptRoot);
sharedRoot=fullfile(tasksRoot,"_shared");repoRoot=tasksRoot;
for k=1:3,repoRoot=fileparts(repoRoot);end
taskRoot=string(getenv("SIMUVERITY_TASK_ROOT"));
end
