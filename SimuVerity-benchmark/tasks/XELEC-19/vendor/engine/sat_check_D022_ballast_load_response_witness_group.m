function report = sat_check_D022_ballast_load_response_witness_group(spec,suite)
%SAT_CHECK_D022_BALLAST_LOAD_RESPONSE_WITNESS_GROUP
% D022-owned two-direction ballast response aggregation.  Only the two
% predeclared witness rows may contribute to this verdict.

report = base_report();
members = empty_members();
[lightRows,lightReason] = source_rows(suite,"light_load", ...
    "ballast_absorbs_more_under_light_load");
[heavyRows,heavyReason] = source_rows(suite,"heavy_load", ...
    "ballast_absorbs_less_under_heavy_load");

reasons = strings(0,1);
if strlength(lightReason)>0, reasons(end+1)=lightReason; end %#ok<AGROW>
if strlength(heavyReason)>0, reasons(end+1)=heavyReason; end %#ok<AGROW>
if isempty(reasons)
    [light,why] = make_member(lightRows,"D022.ballast_absorbs_more_under_light_load","light", ...
        "light_load","ballast_absorbs_more_under_light_load");
    if strlength(why)>0, reasons(end+1)=why; end %#ok<AGROW>
    [heavy,why] = make_member(heavyRows,"D022.ballast_absorbs_less_under_heavy_load","heavy", ...
        "heavy_load","ballast_absorbs_less_under_heavy_load");
    if strlength(why)>0, reasons(end+1)=why; end %#ok<AGROW>
    members = [light heavy];
end

complete = isempty(reasons) && numel(members)==2;
allPass = complete && all([members.ok]);
report.evidence = struct('members',members,'members_complete',logical(complete), ...
    'members_all_pass',logical(allPass));
if ~complete
    report.valid = false;
    report.ok = false;
    report.score = 0;
    if isempty(reasons), reasons="MEMBERS_INCOMPLETE"; end
    report.detail = "MEMBERS_INCOMPLETE:" + strjoin(unique(reasons,'stable'),"|");
    return;
end

% Both evaluator-owned directions are part of the public operating
% envelope.  A controller that compensates only one direction is not a
% successful ELC response.
report.ok = allPass;
report.score = double(report.ok);
if allPass
    report.detail = "OK";
else
    report.detail = "ONE_OR_MORE_DIRECTIONS_FAILED";
end
end

function [rows,reason] = source_rows(suite,scenarioId,sourceId)
rows = struct([]); reason = "";
if ~isstruct(suite) || ~isfield(suite,'scenario_results')
    reason="MISSING_SOURCE_MEMBER"; return;
end
scenarios = suite.scenario_results;
if iscell(scenarios), cells=scenarios; else, cells=num2cell(scenarios); end
hits = {};
for i=1:numel(cells)
    r=cells{i};
    sid="";
    if isstruct(r) && isfield(r,'scenario'), sid=string(r.scenario); end
    if sid==scenarioId, hits{end+1}=r; end %#ok<AGROW>
end
if numel(hits)~=1
    if numel(hits)>1, reason="SCENARIO_SOURCE_MISMATCH"; else, reason="MISSING_SOURCE_MEMBER"; end
    return;
end
r=hits{1};
if ~isfield(r,'witness_reports') || isempty(r.witness_reports)
    reason="MISSING_SOURCE_MEMBER"; return;
end
w=r.witness_reports;
if iscell(w), wc=w; else, wc=num2cell(w); end
for i=1:numel(wc)
    if isstruct(wc{i}) && isfield(wc{i},'id') && string(wc{i}.id)==sourceId
        if isempty(rows), rows=wc{i}; else, rows(end+1)=wc{i}; end %#ok<AGROW>
    end
end
if isempty(rows), reason="MISSING_SOURCE_MEMBER";
elseif numel(rows)~=1, reason="DUPLICATE_SOURCE_MEMBER";
end
end

function [member,reason] = make_member(row,publicId,direction,scenarioId,sourceId)
member = struct('id',string(publicId),'direction',string(direction), ...
    'evaluated',false,'ok',false,'detail',"SOURCE_UNEVALUATED", ...
    'evidence',struct('source_kind',"witness",'source_scenario',string(scenarioId), ...
    'source_report_id',string(sourceId)));
reason="";
if numel(row)~=1, reason="DUPLICATE_SOURCE_MEMBER"; return; end
if isfield(row,'kind') && string(row.kind)~="witness"
    reason="SOURCE_KIND_MISMATCH"; return;
end
evaluated = isfield(row,'ok') && isscalar(row.ok) && (islogical(row.ok)||isnumeric(row.ok));
if isfield(row,'evaluated'), evaluated=evaluated && isscalar(row.evaluated) && logical(row.evaluated); end
valid = evaluated;
if isfield(row,'valid'), valid=valid && isscalar(row.valid) && logical(row.valid); end
member.evaluated=logical(evaluated);
if ~evaluated, reason="SOURCE_UNEVALUATED"; return; end
if ~valid, reason="SOURCE_INVALID"; return; end
member.ok=logical(row.ok);
if isfield(row,'message'), member.detail=string(row.message);
elseif member.ok, member.detail="OK"; else, member.detail="WITNESS_FAILED"; end
end

function r = base_report()
r=struct('task',"D022",'id',"D022.ballast_load_response_witness_group", ...
    'kind',"task_specific",'semantic_kind',"witness_group",'scenario',"suite", ...
    'layer',"robustness",'evaluated',true,'mandatory',true,'ok',false, ...
    'valid',true,'score',0,'detail',"UNINITIALIZED", ...
    'evidence',struct('members',empty_members(),'members_complete',false, ...
    'members_all_pass',false));
end

function m = empty_members()
m=struct('id',{},'direction',{},'evaluated',{},'ok',{},'detail',{},'evidence',{});
end
