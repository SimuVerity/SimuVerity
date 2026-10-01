function report = sat_check_D011_dc_link_rectifier_ownership( ...
    modelName, spec, scenarioId, simOut, signals, baseReports, state) %#ok<INUSD>
%SAT_CHECK_D011_DC_LINK_RECTIFIER_OWNERSHIP D011 AC/DC-link ownership.
% The public chain requires a configured capacitor downstream of a diode
% rectifier.  Generic Series RLC naming is deliberately insufficient: only
% BranchType=C (series or parallel) or an explicit capacitor is a target.

if ~identity_ok(spec, scenarioId)
    report = make_report(false, false, false, ...
        "TASK_OR_SCENARIO_IDENTITY_MISMATCH", struct());
    return;
end
if has_test_facts(state)
    facts = state.evidence.unit_test_dc_link_facts;
    valid = true;
    reason = "OK";
else
    try
        [facts, valid, reason] = extract_facts(modelName);
    catch ex
        report = make_report(false, false, false, ...
            "EXTRACTION_ERROR:" + string(ex.identifier), struct());
        return;
    end
end
if ~valid
    report = make_report(false, false, false, reason, facts);
    return;
end
[schemaOk, ok, detail] = verdict(facts);
report = make_report(true, schemaOk, ok, detail, facts);
end

function [facts, valid, reason] = extract_facts(modelName)
facts = empty_facts();
valid = false;
reason = "";
blocks = string(find_system(char(modelName), "LookUnderMasks", "all", ...
    "FollowLinks", "off", "Type", "Block"));
sources = strings(0, 1);
rectifiers = strings(0, 1);
capacitors = strings(0, 1);
rejectedRlc = strings(0, 1);
for block = blocks(:)'
    if is_ac_source(block), sources(end + 1, 1) = block; end %#ok<AGROW>
    if is_diode_rectifier(block), rectifiers(end + 1, 1) = block; end %#ok<AGROW>
    if is_configured_capacitor(block)
        capacitors(end + 1, 1) = block; %#ok<AGROW>
    elseif is_noncapacitive_rlc(block)
        rejectedRlc(end + 1, 1) = block; %#ok<AGROW>
    end
end
sources = unique(sources, "stable");
rectifiers = unique(rectifiers, "stable");
capacitors = unique(capacitors, "stable");
rejectedRlc = unique(rejectedRlc, "stable");
facts.source_blocks = sources;
facts.rectifier_blocks = rectifiers;
facts.configured_capacitor_blocks = capacitors;
facts.noncapacitive_rlc_excluded = rejectedRlc;
if isempty(sources), reason = "D011_AC_SOURCE_UNRESOLVED"; return; end
if isempty(rectifiers), reason = "D011_DIODE_RECTIFIER_UNRESOLVED"; return; end
if isempty(capacitors), reason = "D011_CONFIGURED_DC_CAPACITOR_UNRESOLVED"; return; end

for source = sources(:)'
for rectifier = rectifiers(:)'
for capacitor = capacitors(:)'
    [pathOk, ~, evidence] = sat_physical_path(char(modelName), ...
        {exact_pattern(modelName, source)}, ...
        {exact_pattern(modelName, rectifier)}, ...
        {exact_pattern(modelName, capacitor)});
    facts.query_count = facts.query_count + 1;
    facts.last_query_evidence = evidence;
    if pathOk && logical(evidence.via_is_cut)
        facts.path_found = true;
        facts.rectifier_required_cut = true;
        facts.winning_source = source;
        facts.winning_rectifier = rectifier;
        facts.winning_capacitor = capacitor;
        facts.path = string(evidence.path(:));
        facts.port_path = string(evidence.port_path(:));
        facts.path_reason = string(evidence.reason);
        valid = true;
        reason = "OK";
        return;
    end
end
end
end
valid = true;
reason = "OK";
end

function tf = is_ac_source(block)
d = own_descriptor(block);
tf = has_connection_ports(block, 2) && ...
    (contains(d, "ac voltage source") || ...
    contains(d, "single-phase voltage source") || ...
    contains(d, "single phase voltage source"));
end

function tf = is_diode_rectifier(block)
d = own_descriptor(block);
device = lower(string(getp(block, "Device")));
arms = str2double(string(getp(block, "Arms")));
activeDevice = any(contains(device, ...
    ["igbt", "mosfet", "gto", "thyristor", "ideal switch"]));
diodeOnly = contains(device, "diode") && ~activeDevice;
namedRectifier = contains(d, "diode bridge") || contains(d, "rectifier");
bridge = contains(d, "universal bridge") || namedRectifier;
armOk = ~isfinite(arms) || arms == 2;
tf = has_connection_ports(block, 4) && bridge && armOk && ...
    (diodeOnly || (namedRectifier && strlength(device) == 0));
end

function tf = is_configured_capacitor(block)
branch = upper(strtrim(string(getp(block, "BranchType"))));
d = own_descriptor(block);
explicit = contains(d, "capacitor") && ...
    ~contains(d, "capacitor voltage") && ...
    ~contains(d, "capacitor current");
tf = has_connection_ports(block, 2) && ...
    (branch == "C" || (strlength(branch) == 0 && explicit));
end

function tf = is_noncapacitive_rlc(block)
branch = upper(strtrim(string(getp(block, "BranchType"))));
d = own_descriptor(block);
tf = has_connection_ports(block, 2) && ...
    contains(d, "rlc branch") && strlength(branch) > 0 && branch ~= "C";
end

function tf = has_connection_ports(block, minimum)
tf = false;
try
    handles = get_param(char(block), "PortHandles");
    count = 0;
    for field = ["LConn", "RConn"]
        if isfield(handles, field), count = count + numel(handles.(field)); end
    end
    tf = count >= minimum;
catch
end
end

function pattern = exact_pattern(modelName, block)
root = string(modelName) + "/";
relative = string(block);
if startsWith(relative, root), relative = extractAfter(relative, strlength(root)); end
pattern = "^" + string(regexptranslate("escape", lower(char(relative)))) + "\|";
pattern = char(pattern);
end

function d = own_descriptor(block)
parts = strings(0, 1);
for parameter = {"Name", "BlockType", "MaskType", "ReferenceBlock", ...
        "SourceBlock", "SourceType"}
    parts(end + 1, 1) = string(getp(block, parameter{1})); %#ok<AGROW>
end
d = lower(strjoin(parts, "|"));
end

function [schemaOk, ok, detail] = verdict(facts)
required = {'source_blocks', 'rectifier_blocks', ...
    'configured_capacitor_blocks', 'path_found', ...
    'rectifier_required_cut'};
schemaOk = isstruct(facts) && isscalar(facts) && all(isfield(facts, required));
if ~schemaOk, ok = false; detail = "FACT_SCHEMA_INVALID"; return; end
if isempty(facts.source_blocks)
    ok = false; detail = "D011_AC_SOURCE_UNRESOLVED";
elseif isempty(facts.rectifier_blocks)
    ok = false; detail = "D011_DIODE_RECTIFIER_UNRESOLVED";
elseif isempty(facts.configured_capacitor_blocks)
    ok = false; detail = "D011_CONFIGURED_DC_CAPACITOR_UNRESOLVED";
elseif ~logical(facts.path_found)
    ok = false; detail = "D011_SOURCE_RECTIFIER_CAPACITOR_PATH_MISSING";
elseif ~logical(facts.rectifier_required_cut)
    ok = false; detail = "D011_RECTIFIER_BYPASS_PRESENT";
else
    ok = true; detail = "OK";
end
end

function tf = identity_ok(spec, scenario)
tf = isstruct(spec) && isscalar(spec) && isfield(spec, "id") && ...
    string(spec.id) == "D011" && string(scenario) == "nominal";
end

function tf = has_test_facts(state)
tf = isstruct(state) && isscalar(state) && isfield(state, "evidence") && ...
    isstruct(state.evidence) && ...
    isfield(state.evidence, "unit_test_dc_link_facts");
end

function value = getp(block, parameter)
value = "";
try, value = string(get_param(char(block), parameter)); catch, end
end

function facts = empty_facts()
facts = struct( ...
    "source_blocks", strings(0, 1), ...
    "rectifier_blocks", strings(0, 1), ...
    "configured_capacitor_blocks", strings(0, 1), ...
    "noncapacitive_rlc_excluded", strings(0, 1), ...
    "path_found", false, ...
    "rectifier_required_cut", false, ...
    "winning_source", "", ...
    "winning_rectifier", "", ...
    "winning_capacitor", "", ...
    "path", strings(0, 1), ...
    "port_path", strings(0, 1), ...
    "path_reason", "", ...
    "query_count", 0, ...
    "last_query_evidence", struct());
end

function report = make_report(evaluated, valid, ok, detail, evidence)
report = struct( ...
    "task", "D011", ...
    "id", "D011.dc_link_rectifier_ownership", ...
    "kind", "task_specific", ...
    "semantic_kind", "structure", ...
    "scenario", "nominal", ...
    "layer", "qualification", ...
    "evaluated", logical(evaluated), ...
    "mandatory", true, ...
    "ok", logical(ok), ...
    "valid", logical(valid), ...
    "score", double(ok), ...
    "detail", string(detail), ...
    "evidence", evidence);
end
