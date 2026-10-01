function report=sat_check_D008_q_load_response_witness_group(spec,suite)
%SAT_CHECK_D008_Q_LOAD_RESPONSE_WITNESS_GROUP D008-only directional oracle.
% The public group is deliberately not a generic witness-group alias.  It
% binds four exact D008 source witnesses and fails only when at least one
% source witness fails in each Q-load direction.

task="D008";targetId="D008.q_load_response_witness_group";
members=empty_members();complete=true;diagnostics=strings(0,1);
if ~isstruct(spec)||~isscalar(spec)||~isfield(spec,'id') ...
        ||~isscalar(string(spec.id))||string(spec.id)~=task
    complete=false;diagnostics(end+1)="SPEC_IDENTITY_MISMATCH";
end
if ~isstruct(suite)||~isscalar(suite)
    complete=false;diagnostics(end+1)="SUITE_SCHEMA_INVALID";
    scenarioRows={};
else
    scenarioRows=to_cell_field(suite,'scenario_results');
end

decls=[decl("D008.reactive_load_current_up","up","q_load_up", ...
        "reactive_load_current_up") ...
    decl("D008.compensation_current_up","up","q_load_up", ...
        "compensation_current_up") ...
    decl("D008.reactive_load_current_down","down","q_load_down", ...
        "reactive_load_current_down") ...
    decl("D008.compensation_current_down","down","q_load_down", ...
        "compensation_current_down")];

for i=1:numel(decls)
    d=decls(i);[source,count,sourceValid,reason]=find_source(scenarioRows,d);
    evaluated=count==1&&sourceValid;
    if evaluated,memberOk=logical(source.ok);detail=source_detail(source);
    else,memberOk=false;detail=reason;complete=false;diagnostics(end+1)=d.id+":"+reason;end %#ok<AGROW>
    evidence=struct('source_kind',"witness", ...
        'source_scenario',d.scenario,'source_report_id',d.report_id);
    members(end+1)=struct('id',d.id,'direction',d.direction, ... %#ok<AGROW>
        'evaluated',logical(evaluated),'ok',logical(memberOk), ...
        'detail',string(detail),'evidence',evidence);
end

up=members(string({members.direction})=="up");
down=members(string({members.direction})=="down");
upFailure=any([up.evaluated]&~[up.ok]);
downFailure=any([down.evaluated]&~[down.ok]);
allPass=complete&&all([members.evaluated])&&all([members.ok]);
ok=complete&&~(upFailure&&downFailure);
if ~complete,detail="INVALID_SOURCE_BINDING:"+strjoin(diagnostics,";");
elseif allPass,detail="OK";
elseif upFailure&&downFailure,detail="BOTH_Q_LOAD_DIRECTIONS_FAILED";
elseif upFailure,detail="UP_DIRECTION_ONLY_FAILED";
else,detail="DOWN_DIRECTION_ONLY_FAILED";
end
evidence=struct('members',members,'members_complete',logical(complete), ...
    'members_all_pass',logical(allPass),'up_direction_failed',logical(upFailure), ...
    'down_direction_failed',logical(downFailure));
report=make_report(targetId,true,complete,ok,detail,evidence);
end

function [row,count,valid,reason]=find_source(scenarios,d)
row=struct();count=0;valid=false;reason="SOURCE_MISSING";
matching={};
for i=1:numel(scenarios)
    scenario=scenarios{i};
    if ~isstruct(scenario)||~isscalar(scenario)||scenario_id(scenario)~=d.scenario,continue;end
    reports=to_cell_field(scenario,'witness_reports');
    for j=1:numel(reports)
        candidate=reports{j};
        if isstruct(candidate)&&isscalar(candidate)&&isfield(candidate,'id') ...
                &&isscalar(string(candidate.id))&&string(candidate.id)==d.report_id
            matching{end+1}=candidate; %#ok<AGROW>
        end
    end
end
count=numel(matching);
if count==0,return;end
if count~=1,reason="SOURCE_DUPLICATE";return;end
row=matching{1};
if ~isfield(row,'ok')||~logical01(row.ok)
    reason="SOURCE_OK_INVALID";return;
end
if isfield(row,'valid')&&~logical01(row.valid)
    reason="SOURCE_VALID_INVALID";return;
end
if isfield(row,'valid')&&~logical(row.valid)
    reason="SOURCE_EVIDENCE_INVALID";return;
end
valid=true;reason="OK";
end

function id=scenario_id(row)
id="";
if isfield(row,'scenario')&&isscalar(string(row.scenario)),id=string(row.scenario);
elseif isfield(row,'id')&&isscalar(string(row.id)),id=string(row.id);end
end
function value=source_detail(row)
if isfield(row,'message')&&isscalar(string(row.message)),value=string(row.message);
elseif isfield(row,'detail')&&isscalar(string(row.detail)),value=string(row.detail);
else,value="";end
end
function d=decl(id,direction,scenario,reportId)
d=struct('id',id,'direction',direction,'scenario',scenario,'report_id',reportId);
end
function r=make_report(id,evaluated,valid,ok,detail,evidence)
r=struct('task',"D008",'id',id,'kind',"task_specific", ...
    'semantic_kind',"witness_group",'scenario',"suite",'layer',"robustness", ...
    'evaluated',logical(evaluated),'mandatory',true,'ok',logical(ok), ...
    'valid',logical(valid),'score',double(ok),'detail',string(detail), ...
    'evidence',evidence);
end
function value=logical01(x)
value=isscalar(x)&&(islogical(x)||(isnumeric(x)&&isreal(x)&&isfinite(x)&&(x==0||x==1)));
end
function values=to_cell_field(row,name)
if ~isstruct(row)||~isfield(row,name)||isempty(row.(name)),values={};
elseif iscell(row.(name)),values=row.(name)(:).';
else,values=arrayfun(@(x)x,row.(name),'UniformOutput',false);end
end
function members=empty_members()
members=struct('id',{},'direction',{},'evaluated',{},'ok',{},'detail',{},'evidence',{});
end
