function reports = sat_eval_task_specific(modelName,spec,scenarioId,simOut,signals,baseReports,state)
%SAT_EVAL_TASK_SPECIFIC Static scenario-local task evaluator dispatch.
% Final engineering predicates remain in D-specific functions. Dynamic
% function lookup is forbidden so dependency closure remains auditable.

task=upper(string(spec.id));
% Every currently registered scenario-local task target is nominal. Official
% perturbation runs keep their source bands/witnesses and must not duplicate
% or relabel the nominal exact target.
if string(scenarioId)~="nominal"
    reports=empty_reports();return;
end
switch task
    case "D002"
        reports=sat_check_D002_active_npc_topology( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D006"
        reports=sat_check_D006_vdc_vsc_terminal_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D007"
        reports=sat_check_D007_active_current_feedback_ownership_core( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D011"
        reports=sat_check_D011_active_svpwm_gate_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D012"
        reports=sat_check_D012_active_speed_closed_loop_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D014"
        reports=sat_check_D014_measured_power_path_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D015"
        reports=sat_check_D015_active_svpwm_gate_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D019"
        reports=sat_check_D019_internal_multilevel_stage_level_count( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D021"
        reports=sat_check_D021_active_svpwm_gate_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D022"
        a=sat_check_D022_power_branch_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
        b=sat_check_D022_closed_loop_ballast_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
        c=sat_check_D022_energy_path_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
        reports=combine(combine(a,b),c);
    case "D023"
        reports=sat_check_D023_active_vsc_compensation_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D025"
        reports=sat_check_D025_active_power_feedback_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D026"
        a=sat_check_D026_split_dc_balance( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
        b=sat_check_D026_active_svpwm_gate_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
        reports=combine(a,b);
    case "D027"
        reports=sat_check_D027_active_current_feedback_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    case "D028"
        reports=sat_check_D028_active_phase_shift_branch_ownership( ...
            modelName,spec,scenarioId,simOut,signals,baseReports,state);
    otherwise
        reports=empty_reports();return;
end
reports=validate_reports(reports,task,string(scenarioId),false);
end

function out=combine(a,b)
if isempty(a),out=b;elseif isempty(b),out=a;else,out=[a(:);b(:)]';end
end
function rows=validate_reports(rows,task,scenario,isSuite)
if isempty(rows),rows=empty_reports();return;end
assert(isstruct(rows),'SimuVerity:TaskDispatch:ReportSchema','Task evaluator must return struct rows.');
required={'task','id','kind','semantic_kind','scenario','layer','evaluated', ...
    'mandatory','ok','valid','score','detail','evidence'};
for i=1:numel(rows)
    row=rows(i);assert(all(isfield(row,required)),'SimuVerity:TaskDispatch:ReportSchema', ...
        'Task evaluator row is missing required fields.');
    assert(string(row.task)==task&&string(row.kind)=="task_specific", ...
        'SimuVerity:TaskDispatch:ReportOwnership','Task report ownership/kind mismatch.');
    if ~isSuite,assert(string(row.scenario)==scenario, ...
            'SimuVerity:TaskDispatch:ReportScenario','Scenario-local report scenario mismatch.');end
    assert(any(string(row.layer)==["qualification","nominal","robustness"]), ...
        'SimuVerity:TaskDispatch:ReportLayer','Invalid task report layer.');
    assert_scalar_logical(row,'evaluated');assert_scalar_logical(row,'mandatory');
    assert_scalar_logical(row,'ok');assert_scalar_logical(row,'valid');
    assert(isnumeric(row.score)&&isscalar(row.score)&&isfinite(row.score) ...
        &&row.score>=0&&row.score<=1,'SimuVerity:TaskDispatch:ReportScore', ...
        'Task report score must be a finite scalar in [0,1].');
end
ids=string({rows.id});assert(numel(unique(ids))==numel(ids), ...
    'SimuVerity:TaskDispatch:DuplicateReport','Task evaluator emitted duplicate report IDs.');
end
function assert_scalar_logical(row,field)
assert(islogical(row.(field))&&isscalar(row.(field)), ...
    'SimuVerity:TaskDispatch:ReportLogical','%s must be scalar logical.',field);
end
function rows=empty_reports()
rows=struct('task',{},'id',{},'kind',{},'semantic_kind',{},'scenario',{}, ...
    'layer',{},'evaluated',{},'mandatory',{},'ok',{},'valid',{}, ...
    'score',{},'detail',{},'evidence',{});
end
