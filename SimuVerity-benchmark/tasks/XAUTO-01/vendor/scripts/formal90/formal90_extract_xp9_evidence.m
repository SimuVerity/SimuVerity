function evidence = formal90_extract_xp9_evidence( ...
    specPath,modelPath,outDir,builderName,formalTaskId,opts)
%FORMAL90_EXTRACT_XP9_EVIDENCE Run scenarios and emit facts only.
% This entrypoint never resolves or invokes an XP9 score function.  The
% task-local builder may call only declared measurement helpers.
arguments
    specPath (1,1) string
    modelPath (1,1) string
    outDir (1,1) string
    builderName (1,1) string
    formalTaskId (1,1) string
    opts.SaveWaveforms (1,1) logical = true
end

spec=jsondecode(fileread(specPath));
assert(isfile(modelPath),'FORMAL90_MODEL_NOT_FOUND: %s',modelPath);
if ~isfolder(outDir),mkdir(outDir);end
[~,modelName]=fileparts(modelPath);modelName=string(modelName);
oldPath=path;pathCleanup=onCleanup(@() path(oldPath)); %#ok<NASGU>
formalRoot=fileparts(mfilename('fullpath'));
projectRoot=fileparts(fileparts(formalRoot));
xp9Root=fullfile(projectRoot,'scripts','xp9');
publicOutputRoot=fullfile(projectRoot,'scripts','unified','public_output');
restoredefaultpath;
closureHelperRoot=string(getenv('SIMUVERITY_CANDIDATE_CLOSURE_HELPER_ROOT'));
if strlength(closureHelperRoot)>0
    assert(isfolder(closureHelperRoot),'FORMAL90_CANDIDATE_CLOSURE_HELPER_ROOT_MISSING');
    addpath(closureHelperRoot,'-begin');
end
addpath(genpath(xp9Root),'-begin');
addpath(genpath(formalRoot),'-begin');
addpath(publicOutputRoot,'-begin');
simulationPath=path;
builderPath=string(which(char(builderName)));
assert(strlength(builderPath)>0,'FORMAL90_EVIDENCE_BUILDER_NOT_FOUND:%s',builderName);
builderPath=string(java.io.File(builderPath).getCanonicalPath());
bdclose('all');modelCleanup=onCleanup(@() local_close(modelName)); %#ok<NASGU>
baseSnapshot=local_snapshot_base();
baseCleanup=onCleanup(@() local_restore_base(baseSnapshot)); %#ok<NASGU>

nominalInputs=local_nominal_inputs(spec);
scenarios=[struct('id','nominal','values',struct()),local_scenarios(spec)];
runs=repmat(struct('scenario',"",'stage',"created",'error',"", ...
    'failure_attribution',"",'inputs',struct(),'solver',struct(), ...
    'outputs',struct(),'output_adapters',struct()),numel(scenarios),1);
for index=1:numel(scenarios)
    scenario=scenarios(index);values=nominalInputs;
    names=fieldnames(scenario.values);
    for key=1:numel(names),values.(names{key})=scenario.values.(names{key});end
    runs(index).scenario=string(scenario.id);runs(index).inputs=values;
    local_close(modelName);path(simulationPath);local_set_base(values);
    try
        load_system(modelPath);
        input=Simulink.SimulationInput(modelName);
        inputNames=fieldnames(values);
        for key=1:numel(inputNames)
            input=input.setVariable(inputNames{key},values.(inputNames{key}), ...
                'Workspace',modelName);
        end
        stepText=num2str(double(spec.sim.step),17);
        assert(isfinite(double(spec.sim.step))&&double(spec.sim.step)>0, ...
            'FORMAL90_SIM_STEP_INVALID');
        runs(index).solver=struct( ...
            'type_at_load',string(get_param(modelName,'SolverType')), ...
            'name_at_load',string(get_param(modelName,'Solver')), ...
            'fixed_step',double(spec.sim.step),'max_step',double(spec.sim.step));
        input=input.setModelParameter( ...
            'StopTime',num2str(double(spec.sim.stop),17), ...
            'FixedStep',stepText,'MaxStep',stepText, ...
            'ReturnWorkspaceOutputs','on');
        simOut=sim(input);runs(index).stage="simulated";
        runs(index).solver.type_after_sim=string(get_param(modelName,'SolverType'));
        runs(index).solver.name_after_sim=string(get_param(modelName,'Solver'));
        for key=1:numel(spec.outputs)
            output=local_elem(spec.outputs,key);name=char(string(output.name));
            [ts,adapter]=simuverity_public_output_compatibility( ...
                simOut,string(name),double(output.channels), ...
                AllowBaseWorkspace=true);
            outputKey=matlab.lang.makeValidName(name);
            runs(index).outputs.(outputKey)=ts;
            runs(index).output_adapters.(outputKey)=adapter;
            [~,data,ok,why]=xp9_series(runs(index),name,double(output.channels));
            assert(ok&&size(data,2)==double(output.channels), ...
                'FORMAL90_OUTPUT_INVALID:%s:%s',name,why);
        end
    catch ME
        if string(ME.identifier) == ...
                "SimuVerity:UnifiedOutput:EvaluatorContract"
            rethrow(ME)
        end
        if runs(index).stage=="simulated",runs(index).stage="contract_fail";
        else,runs(index).stage="simulation_fail";end
        runs(index).failure_attribution=localFailureAttribution(ME);
        runs(index).error=string(getReport(ME,'extended','hyperlinks','off'));
    end
    local_close(modelName);
end

path(simulationPath);
resolvedBuilder=string(which(char(builderName)));
resolvedBuilder=string(java.io.File(resolvedBuilder).getCanonicalPath());
assert(strcmpi(resolvedBuilder,builderPath), ...
    'FORMAL90_EVIDENCE_BUILDER_ROUTE_CHANGED');
builder=str2func(char(builderName));
facts=builder(runs,spec);
allRunsValid=all(string({runs.stage})=="simulated");
if ~allRunsValid
    facts.score_inputs_valid=false;
    facts.diagnostics_valid=false;
    reasons=string(facts.gate_reasons(:));
    facts.gate_reasons=unique([reasons;"RUN_OR_OUTPUT_CONTRACT_INVALID"],'stable');
end

weights=spec.groups.weights;
evidence=struct( ...
    'schema',"simuverity.formal90-evidence-input.v1", ...
    'formal_task_id',formalTaskId, ...
    'source_task_id',string(spec.id), ...
    'model_path',string(java.io.File(modelPath).getCanonicalPath()), ...
    'model_file_presence',xp9_file_presence_file(modelPath), ...
    'spec_path',string(java.io.File(specPath).getCanonicalPath()), ...
    'spec_file_presence',xp9_file_presence_file(specPath), ...
    'builder_path',builderPath, ...
    'builder_file_presence',xp9_file_presence_file(builderPath), ...
    'extractor_path',string(mfilename('fullpath'))+".m", ...
    'extractor_file_presence',xp9_file_presence_file(string(mfilename('fullpath'))+".m"), ...
    'output_compat_policy',localOutputCompatPolicy(publicOutputRoot), ...
    'generated_at',local_now(), ...
    'matlab_release',string(version('-release')), ...
    'platform_valid',allRunsValid, ...
    'group_weights',struct('A',double(weights.A),'Q',double(weights.Q), ...
        'M',double(weights.M),'R',double(weights.R),'D',double(weights.D)), ...
    'runs',local_run_summary(runs), ...
    'facts',facts, ...
    'score_fields_present',false);
if opts.SaveWaveforms
    save(fullfile(outDir,'waveforms.mat'),'runs','spec','-v7.3');
end
local_write(evidence,fullfile(outDir,'evidence.json'));
fprintf('FORMAL90_EVIDENCE task=%s platform=%d out=%s\n', ...
    formalTaskId,allRunsValid,outDir);
end

function rows=local_scenarios(spec)
rows=struct('id',{},'values',{});
if ~isfield(spec,'scenarios')||isempty(spec.scenarios),return;end
for index=1:numel(spec.scenarios)
    scenario=local_elem(spec.scenarios,index);
    rows(end+1)=struct('id',char(string(scenario.id)), ...
        'values',scenario.values); %#ok<AGROW>
end
end
function values=local_nominal_inputs(spec)
values=struct;
for index=1:numel(spec.public_inputs)
    row=local_elem(spec.public_inputs,index);
    values.(char(string(row.name)))=double(row.nominal);
end
end
function summary=local_run_summary(runs)
summary=repmat(struct('scenario',"",'stage',"",'error',"", ...
    'failure_attribution',"",'inputs',struct(),'solver',struct(), ...
    'output_adapters',struct()),numel(runs),1);
for index=1:numel(runs)
    summary(index).scenario=runs(index).scenario;
    summary(index).stage=runs(index).stage;
    summary(index).error=runs(index).error;
    summary(index).failure_attribution=runs(index).failure_attribution;
    summary(index).inputs=runs(index).inputs;
    summary(index).solver=runs(index).solver;
    summary(index).output_adapters=runs(index).output_adapters;
end
end
function value=localFailureAttribution(errorValue)
identifier=string(errorValue.identifier);
if startsWith(identifier,"SimuVerity:UnifiedOutput:CandidateContract")
    value="candidate";
else
    value="candidate_or_task_extractor";
end
end
function policy=localOutputCompatPolicy(publicOutputRoot)
helper=fullfile(publicOutputRoot,'simuverity_public_output_compatibility.m');
policy=struct('policy_id',"simuverity-101-v1:p9-xauto01:scoring", ...
    'lossless_only',true, ...
    'padding_truncation_interpolation_forbidden',true, ...
    'helper_path',string(java.io.File(helper).getCanonicalPath()), ...
    'helper_file_presence',xp9_file_presence_file(helper));
end
function e=local_elem(a,i),if iscell(a),e=a{i};else,e=a(i);end,end
function local_close(model)
try,if bdIsLoaded(model),close_system(model,0);end,catch,end
end
function local_set_base(values)
evalin('base','clearvars; clear global');
local_reload_candidate_dependencies();
names=fieldnames(values);
for index=1:numel(names),assignin('base',names{index},values.(names{index}));end
end
function local_reload_candidate_dependencies()
if strlength(string(getenv( ...
        'SIMUVERITY_CANDIDATE_DEPENDENCY_MANIFEST')))>0
    assert(exist('unified_reload_candidate_dependencies','file')==2, ...
        'FORMAL90_CANDIDATE_DEPENDENCY_RELOAD_HELPER_MISSING');
    unified_reload_candidate_dependencies();
end
end
function snapshot=local_snapshot_base()
names=evalin('base','who');values=cell(size(names));
for index=1:numel(names),values{index}=evalin('base',names{index});end
snapshot=struct('names',{names},'values',{values});
end
function local_restore_base(snapshot)
try
    evalin('base','clearvars');
    for index=1:numel(snapshot.names)
        assignin('base',snapshot.names{index},snapshot.values{index});
    end
catch
end
end
function value=local_now()
value=string(datetime('now','TimeZone','Asia/Shanghai', ...
    'Format','yyyy-MM-dd''T''HH:mm:ssXXX'));
end
function local_write(value,file)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0,'Cannot open %s',file);
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
