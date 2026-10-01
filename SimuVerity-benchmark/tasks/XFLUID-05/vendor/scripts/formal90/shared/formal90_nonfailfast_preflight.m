function report = formal90_nonfailfast_preflight(checks, reportPath)
%FORMAL90_NONFAILFAST_PREFLIGHT Run all adapter checks and retain every issue.
%
% Each element of checks must provide id, category and run.  run is a
% function handle returning a scalar struct with fields:
%   passed  - logical scalar
%   observed, detail - optional, JSON-encodable diagnostics
%
% The helper deliberately never throws for an individual check.  A caller
% must inspect report.pass and may only proceed to update/compile/smoke when
% it is true.  This keeps adapter repair concentrated in one persistent
% MATLAB session instead of failing on the first bad locator or port.

arguments
    checks (1,:) struct
    reportPath (1,1) string = ""
end

records = repmat(struct( ...
    "id", "", "category", "", "passed", false, ...
    "observed", "", "detail", ""), 1, numel(checks));

for index = 1:numel(checks)
    entry = checks(index);
    required = ["id", "category", "run"];
    missing = required(~isfield(entry, required));
    records(index).id = string(localField(entry, "id", "unnamed_check_" + index));
    records(index).category = string(localField(entry, "category", "adapter"));
    if ~isempty(missing) || ~isa(entry.run, "function_handle")
        records(index).detail = "invalid preflight definition: missing " + strjoin(missing, ", ");
        continue;
    end
    try
        result = feval(entry.run);
        if ~isstruct(result) || ~isfield(result, "passed") || ~isscalar(result.passed)
            records(index).detail = "check must return scalar struct containing logical passed";
            continue;
        end
        records(index).passed = logical(result.passed);
        records(index).observed = string(localField(result, "observed", ""));
        records(index).detail = string(localField(result, "detail", ""));
    catch exception
        records(index).detail = string(exception.identifier) + ": " + string(exception.message);
    end
end

allPassed = ~isempty(records) && all([records.passed]);
if isempty(records)
    records = struct( ...
        "id", "preflight_contract", "category", "adapter", "passed", false, ...
        "observed", "", "detail", "empty check list is invalid");
end
report = struct( ...
    "schema", "simuverity.formal90.nonfailfast-preflight.v1", ...
    "pass", allPassed, ...
    "issues", records(~[records.passed]), ...
    "checks", records, ...
    "checked_at", string(datetime("now", "TimeZone", "Asia/Shanghai", ...
        "Format", "yyyy-MM-dd'T'HH:mm:ssXXX")));

if strlength(reportPath) > 0
    parent = fileparts(reportPath);
    if ~isfolder(parent), mkdir(parent); end
    temporary = reportPath + ".tmp." + string(feature("getpid"));
    fid = fopen(temporary, "w", "n", "UTF-8");
    assert(fid >= 0, "SimuVerity:F90:Preflight:WriteFailed", "Cannot write %s", temporary);
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, "%s\n", jsonencode(report, PrettyPrint=true));
    clear cleanup
    movefile(temporary, reportPath, "f");
end
end

function value = localField(entry, name, fallback)
if isfield(entry, name)
    value = entry.(name);
else
    value = fallback;
end
end
