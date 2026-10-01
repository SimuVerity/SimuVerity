function report = sat_check_D019_physical_vout_level_count( ...
        spec,scenarioId,simOut,stageOk,stageEvidence)
%SAT_CHECK_D019_PHYSICAL_VOUT_LEVEL_COUNT Count trusted physical Vout levels.
% This compatibility route uses Vout only after the exact semiconductor stage
% proof establishes that the trusted sensor measures a bridge phase directly
% against the stage midpoint.

if string(scenarioId) ~= "nominal", report = struct([]); return; end
report = base_report(scenarioId);
check = check_spec(spec);
if isempty(check), report.detail = "TASK_CHECK_SPEC_MISSING"; return; end
if nargin < 4 || ~logical(stageOk)
    report.detail = "EXACT_PHYSICAL_STAGE_PROOF_FAILED"; return;
end
if nargin < 5 || ~isstruct(stageEvidence) || ...
        ~getbool(stageEvidence,"vout_phase_to_midpoint",false)
    report.detail = "TRUSTED_VOUT_STAGE_BINDING_MISSING"; return;
end
[t,y,got,why] = vout_series(simOut);
if ~got, report.detail = "VOUT_SIGNAL_MISSING:" + why; return; end
report.evaluated = true;
frequency = getnum(check,"fundamental_hz",50);
cycles = getnum(check,"analysis_cycles",3);
duration = cycles / frequency;
if numel(t) < 3 || t(end)-t(1)+time_eps(t) < duration
    report.detail = "INSUFFICIENT_COMPLETE_CYCLES"; return;
end
targetStart = t(end)-duration;
first = find(t <= targetStart+time_eps(t),1,"last");
if isempty(first)
    report.detail = "INSUFFICIENT_COMPLETE_CYCLES"; return;
end
t = t(first:end); y = y(first:end);
if numel(t) < 3 || t(end)-t(1)+time_eps(t) < duration
    report.detail = "INSUFFICIENT_COMPLETE_CYCLES"; return;
end
[levels,occupancies,coverage,valid,detail] = detect_levels(y,check);
minimum = getnum(check,"min_effective_levels",3);
report.valid = logical(valid);
report.ok = logical(valid && numel(levels) >= minimum);
report.score = double(report.ok);
report.evidence = struct( ...
    "signal","Vout", ...
    "measurement_block",getstr(stageEvidence,"vout_measurement_block",""), ...
    "physical_phase_to_midpoint",true, ...
    "analysis_cycles",cycles,"fundamental_hz",frequency, ...
    "sample_count",numel(y),"effective_level_count",numel(levels), ...
    "level_centers",levels,"level_occupancies",occupancies, ...
    "plateau_coverage",coverage,"min_effective_levels",minimum, ...
    "min_plateau_coverage",getnum(check,"min_plateau_coverage",0.45), ...
    "min_level_separation_frac",getnum(check,"min_level_separation_frac",0.08), ...
    "level_tolerance_frac",getnum(check,"level_tolerance_frac",0.035), ...
    "min_level_occupancy_frac",getnum(check,"min_level_occupancy_frac",0.01));
if ~valid, report.detail = string(detail);
elseif report.ok, report.detail = "OK";
else, report.detail = "EFFECTIVE_LEVEL_COUNT_BELOW_MINIMUM";
end
end

function [levels,occupancies,coverage,valid,detail] = detect_levels(y,cfg)
levels = []; occupancies = []; coverage = 0; valid = false;
detail = "INVALID_VOUT_SIGNAL"; y = double(y(:));
if numel(y) < 16 || any(~isfinite(y)), return; end
sorted = sort(y); count = numel(sorted);
low = sorted(max(1,ceil(0.002*count)));
high = sorted(min(count,floor(0.998*count)));
span = high-low;
if ~isfinite(span) || span <= max(1,max(abs([low high])))*1e-12
    detail = "DEGENERATE_LEVEL_RANGE"; return;
end
tolerance = getnum(cfg,"level_tolerance_frac",0.035)*span;
stable = abs(diff(y)) <= tolerance;
plateau = false(count,1);
plateau(1:end-1) = plateau(1:end-1) | stable;
plateau(2:end) = plateau(2:end) | stable;
coverage = mean(plateau);
minimumCoverage = getnum(cfg,"min_plateau_coverage",0.45);
if coverage+64*eps(max(1,coverage)) < minimumCoverage
    detail = "INSUFFICIENT_PLATEAU_COVERAGE"; return;
end
values = sort(y(plateau));
if isempty(values), detail = "NO_PLATEAU_SAMPLES"; return; end
minimumSeparation = getnum(cfg,"min_level_separation_frac",0.08)*span;
starts = [1;find(diff(values)+64*eps(max(1,span)) >= minimumSeparation)+1];
stops = [starts(2:end)-1;numel(values)];
centers = zeros(1,numel(starts)); counts = zeros(1,numel(starts));
for i = 1:numel(starts)
    one = values(starts(i):stops(i));
    centers(i) = median(one); counts(i) = numel(one);
end
occupancy = counts/count;
minimumOccupancy = getnum(cfg,"min_level_occupancy_frac",0.01);
keep = occupancy+64*eps(max(1,minimumOccupancy)) >= minimumOccupancy;
levels = centers(keep); occupancies = occupancy(keep);
valid = true; detail = "OK";
end

function [t,y,ok,why] = vout_series(simOut)
t = []; y = []; ok = false; why = "EMPTY"; value = [];
try
    if isa(simOut,"Simulink.SimulationOutput"), value = simOut.get("Vout");
    elseif isstruct(simOut) && isfield(simOut,"Vout"), value = simOut.Vout;
    end
catch, value = []; end
if isa(value,"timeseries")
    t = double(value.Time(:)); y = double(value.Data);
elseif isstruct(value) && isfield(value,"t") && isfield(value,"Y")
    t = double(value.t(:)); y = double(value.Y);
elseif isstruct(value) && isfield(value,"time") && ...
        isfield(value,"signals") && isfield(value.signals,"values")
    t = double(value.time(:)); y = double(value.signals.values);
end
if isempty(t) || isempty(y), why = "UNSUPPORTED_SIGNAL_FORMAT"; return; end
if size(y,1) ~= numel(t) && size(y,2) == numel(t), y = y.'; end
if size(y,1) ~= numel(t) || size(y,2) ~= 1
    why = "VOUT_MUST_BE_SCALAR"; return;
end
ok = all(isfinite(t)) && all(isfinite(y));
if ~ok, why = "NONFINITE_VOUT"; end
end

function check = check_spec(spec)
check = [];
if ~isstruct(spec) || ~isfield(spec,"task_specific_checks"), return; end
rows = spec.task_specific_checks;
if ~iscell(rows), rows = num2cell(rows); end
for i = 1:numel(rows)
    if isfield(rows{i},"id") && ...
            string(rows{i}.id) == "D019.internal_multilevel_stage_level_count"
        check = rows{i}; return;
    end
end
end

function report = base_report(scenario)
report = struct( ...
    "task","D019","id","D019.internal_multilevel_stage_level_count", ...
    "kind","task_specific","semantic_kind","band", ...
    "scenario",string(scenario),"layer","nominal", ...
    "evaluated",false,"mandatory",true,"ok",false,"valid",false, ...
    "score",0,"detail","UNINITIALIZED","evidence",struct());
end
function value = getnum(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && isnumeric(s.(name)) && ...
        isscalar(s.(name)) && isfinite(s.(name)), value = double(s.(name)); end
end
function value = getbool(s,name,defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s,name) && isscalar(s.(name)), value = logical(s.(name)); end
end
function value = getstr(s,name,defaultValue)
value = string(defaultValue);
if isstruct(s) && isfield(s,name) && ~isempty(s.(name)), value = string(s.(name)); end
end
function value = time_eps(t), value = max(1,abs(t(end)))*256*eps; end
