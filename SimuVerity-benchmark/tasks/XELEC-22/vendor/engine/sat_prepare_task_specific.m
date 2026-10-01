function state = sat_prepare_task_specific(modelName,spec,scenarioId)
%SAT_PREPARE_TASK_SPECIFIC Prepare evaluator-owned state before compile.
% Only explicitly routed tasks may mutate the loaded scoring copy.  D019's
% probe helper is statically named; all other tasks receive inert state.

task=upper(string(spec.id));scenarioId=string(scenarioId);
state=base_state(task,scenarioId,modelName);
scenarioTasks=["D002","D006","D007","D011","D012","D014","D015","D019","D021", ...
    "D022","D023","D025","D026","D027","D028"];
if any(task==scenarioTasks)&&scenarioId=="nominal"
    try
        state.model_graph=sat_model_graph(modelName);
    catch ex
        state.prepared=false;state.valid=false;state.detail="MODEL_GRAPH_PREPARE_ERROR";
        state.evidence=struct('identifier',string(ex.identifier), ...
            'message',string(strtrim(ex.message)));return;
    end
end
if task~="D019"||scenarioId~="nominal",return;end
checkSpec=find_check_spec(spec,"D019.internal_multilevel_stage_level_count");
if isempty(checkSpec)
    state.prepared=false;state.valid=false;state.detail="D019_CHECK_SPEC_MISSING";return;
end
try
    prepared=sat_prepare_D019_internal_probe(modelName,checkSpec);
    assert(isstruct(prepared)&&isscalar(prepared),'SimuVerity:TaskPrepare:D019Schema', ...
        'D019 probe helper must return one scalar struct.');
    state=merge_state(state,prepared);
    state.task=task;state.scenario=scenarioId;state.model=string(modelName);
catch ex
    state.prepared=false;state.valid=false;state.detail="D019_PREPARE_ERROR";
    state.evidence=struct('identifier',string(ex.identifier), ...
        'message',string(strtrim(ex.message)));
end
end

function state=base_state(task,scenario,model)
state=struct('task',string(task),'scenario',string(scenario),'model',string(model), ...
    'prepared',true,'valid',true,'detail',"NO_TASK_PREPARATION_REQUIRED", ...
    'evidence',struct(),'probe_handles',[],'probe_signals',struct(), ...
    'model_graph',struct());
end
function out=merge_state(base,extra)
out=base;fields=fieldnames(extra);
for i=1:numel(fields),out.(fields{i})=extra.(fields{i});end
required={'prepared','valid','detail','evidence','probe_handles','probe_signals'};
for i=1:numel(required)
    if ~isfield(out,required{i}),error('SimuVerity:TaskPrepare:D019Schema', ...
            'D019 probe state is missing %s.',required{i});end
end
assert(islogical(out.prepared)&&isscalar(out.prepared) ...
    &&islogical(out.valid)&&isscalar(out.valid), ...
    'SimuVerity:TaskPrepare:D019Schema','D019 prepared/valid must be scalar logicals.');
end
function row=find_check_spec(spec,id)
row=[];if ~isfield(spec,'task_specific_checks')||isempty(spec.task_specific_checks),return;end
items=to_cells(spec.task_specific_checks);
for i=1:numel(items)
    if isstruct(items{i})&&isfield(items{i},'id')&&string(items{i}.id)==string(id)
        if ~isempty(row),error('SimuVerity:TaskPrepare:DuplicateCheck','Duplicate task check %s.',id);end
        row=items{i};
    end
end
end
function items=to_cells(value)
if iscell(value),items=value(:)';elseif isstruct(value),items=num2cell(value(:)');else,items={};end
end
