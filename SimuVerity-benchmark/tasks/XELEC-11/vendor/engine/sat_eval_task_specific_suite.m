function reports = sat_eval_task_specific_suite(spec,suite)
%SAT_EVAL_TASK_SPECIFIC_SUITE Static cross-scenario task dispatch.

task=upper(string(spec.id));
switch task
    case "D008"
        reports=sat_check_D008_q_load_response_witness_group(spec,suite);
    case "D022"
        reports=sat_check_D022_ballast_load_response_witness_group(spec,suite);
    otherwise
        reports=empty_reports();return;
end
reports=validate_reports(reports,task);
end

function rows=validate_reports(rows,task)
assert(isstruct(rows)&&~isempty(rows),'SimuVerity:TaskDispatch:ReportSchema', ...
    'Suite evaluator must emit at least one report.');
required={'task','id','kind','semantic_kind','scenario','layer','evaluated', ...
    'mandatory','ok','valid','score','detail','evidence'};
for i=1:numel(rows)
    row=rows(i);assert(all(isfield(row,required)),'SimuVerity:TaskDispatch:ReportSchema', ...
        'Suite evaluator row is missing required fields.');
    assert(string(row.task)==task&&string(row.kind)=="task_specific" ...
        &&string(row.scenario)=="suite"&&string(row.layer)=="robustness", ...
        'SimuVerity:TaskDispatch:ReportOwnership','Suite report ownership/location mismatch.');
    fields={'evaluated','mandatory','ok','valid'};
    for q=1:numel(fields),assert(islogical(row.(fields{q}))&&isscalar(row.(fields{q})), ...
            'SimuVerity:TaskDispatch:ReportLogical','%s must be scalar logical.',fields{q});end
    assert(isnumeric(row.score)&&isscalar(row.score)&&isfinite(row.score) ...
        &&row.score>=0&&row.score<=1,'SimuVerity:TaskDispatch:ReportScore', ...
        'Suite task report score must be a finite scalar in [0,1].');
end
ids=string({rows.id});assert(numel(unique(ids))==numel(ids), ...
    'SimuVerity:TaskDispatch:DuplicateReport','Suite evaluator emitted duplicate report IDs.');
end
function rows=empty_reports()
rows=struct('task',{},'id',{},'kind',{},'semantic_kind',{},'scenario',{}, ...
    'layer',{},'evaluated',{},'mandatory',{},'ok',{},'valid',{}, ...
    'score',{},'detail',{},'evidence',{});
end
