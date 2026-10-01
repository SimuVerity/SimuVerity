function report = sat_check_D011_mechanical_causality( ...
    modelName, spec, scenarioId, simOut, signals, baseReports, state) %#ok<INUSD>
%SAT_CHECK_D011_MECHANICAL_CAUSALITY Reject prescribed rotor motion.
% Wm may be measured from a PMSM, but it is not a motor-drive response when
% F_cmd (or another command) directly prescribes an ideal speed input.

if ~identity_ok(spec, scenarioId)
    report = make_report(false, false, false, ...
        "TASK_OR_SCENARIO_IDENTITY_MISMATCH", struct());
    return;
end
if has_test_facts(state)
    facts = state.evidence.unit_test_mechanical_facts;
    valid = true;
    reason = "OK";
else
    try
        [facts, valid, reason] = extract_facts(modelName, baseReports, state);
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

function [facts, valid, reason] = extract_facts(modelName, baseReports, state)
facts = empty_facts();
valid = false;
reason = "";
machines = active_machines(baseReports);
if isempty(machines), machines = discover_machines(modelName); end
machines = unique(machines, "stable");
facts.active_machine_blocks = machines;
if isempty(machines), reason = "D011_ACTIVE_PMSM_UNRESOLVED"; return; end

rows = repmat(struct("block", "", "mode", "", ...
    "classification", ""), 0, 1);
imposed = strings(0, 1);
allowed = strings(0, 1);
unresolved = strings(0, 1);
for machine = machines(:)'
    mode = lower(strtrim(string(getp(machine, "MechanicalLoad"))));
    if contains(mode, "speed") || contains(mode, "angular velocity")
        classification = "IMPOSED_SPEED";
        imposed(end + 1, 1) = machine; %#ok<AGROW>
    elseif contains(mode, "torque")
        classification = "TORQUE_DRIVEN";
        allowed(end + 1, 1) = machine; %#ok<AGROW>
    elseif contains(mode, "mechanical") && ...
            (contains(mode, "port") || contains(mode, "rotational"))
        classification = "MECHANICAL_CONSERVING_PORT";
        allowed(end + 1, 1) = machine; %#ok<AGROW>
    elseif strlength(mode) == 0 && has_extra_mechanical_port(machine)
        classification = "MECHANICAL_CONSERVING_PORT";
        allowed(end + 1, 1) = machine; %#ok<AGROW>
    else
        classification = "UNRESOLVED";
        unresolved(end + 1, 1) = machine; %#ok<AGROW>
    end
    rows(end + 1, 1) = struct("block", machine, "mode", mode, ... %#ok<AGROW>
        "classification", classification);
end
facts.machine_modes = rows;
facts.imposed_speed_machine_blocks = imposed;
facts.allowed_dynamic_machine_blocks = allowed;
facts.unresolved_machine_blocks = unresolved;

commands = input_bindings(baseReports, "F_cmd");
facts.command_blocks = commands;
idealSources = discover_ideal_speed_sources(modelName);
facts.ideal_speed_source_blocks = idealSources;
drivenSources = strings(0, 1);
paths = cell(0, 1);
if ~isempty(commands) && ~isempty(idealSources)
    graph = task_graph(modelName, state);
    for command = commands(:)'
    for target = idealSources(:)'
        [reaches, path] = signal_reaches(graph, command, target);
        if reaches
            drivenSources(end + 1, 1) = target; %#ok<AGROW>
            paths{end + 1, 1} = path; %#ok<AGROW>
        end
    end
    end
end
facts.command_driven_ideal_speed_sources = unique(drivenSources, "stable");
facts.command_to_ideal_speed_paths = paths;
valid = true;
reason = "OK";
end

function machines = active_machines(base)
machines = strings(0, 1);
reports = field_items(base, "struct_reports");
for i = 1:numel(reports)
    row = reports{i};
    if ~isstruct(row) || ~isfield(row, "id") || ...
            string(row.id) ~= "inverter_to_pmsm" || ...
            ~logical_field(row, "ok") || ~isfield(row, "evidence") || ...
            ~isfield(row.evidence, "path")
        continue;
    end
    for block = string(row.evidence.path(:))'
        if is_pmsm(block), machines(end + 1, 1) = block; end %#ok<AGROW>
    end
end
end

function machines = discover_machines(modelName)
machines = strings(0, 1);
blocks = string(find_system(char(modelName), "LookUnderMasks", "all", ...
    "FollowLinks", "off", "Type", "Block"));
for block = blocks(:)'
    if is_pmsm(block), machines(end + 1, 1) = block; end %#ok<AGROW>
end
end

function tf = is_pmsm(block)
d = own_descriptor(block);
tf = contains(d, "permanent magnet synchronous machine") || ...
    (contains(d, "pmsm") && contains(d, "machine"));
end

function tf = has_extra_mechanical_port(block)
tf = false;
try
    handles = get_param(char(block), "PortHandles");
    count = 0;
    for field = ["LConn", "RConn"]
        if isfield(handles, field), count = count + numel(handles.(field)); end
    end
    % A three-phase machine needs three electrical terminals.  A fourth
    % conserving terminal is evidence of an exposed mechanical port.
    tf = count >= 4;
catch
end
end

function sources = discover_ideal_speed_sources(modelName)
sources = strings(0, 1);
blocks = string(find_system(char(modelName), "LookUnderMasks", "all", ...
    "FollowLinks", "off", "Type", "Block"));
for block = blocks(:)'
    d = own_descriptor(block);
    if contains(d, "ideal rotational motion source") || ...
            contains(d, "controlled rotational motion source") || ...
            contains(d, "ideal angular velocity source") || ...
            contains(d, "ideal speed source")
        sources(end + 1, 1) = block; %#ok<AGROW>
    end
end
sources = unique(sources, "stable");
end

function blocks = input_bindings(base, name)
blocks = strings(0, 1);
reports = field_items(base, "input_reports");
for i = 1:numel(reports)
    row = reports{i};
    if ~isstruct(row) || ~isfield(row, "name") || ...
            string(row.name) ~= string(name) || ...
            ~logical_field(row, "ok") || ~isfield(row, "bindings")
        continue;
    end
    bindings = string(row.bindings(:));
    for binding = bindings(:)'
        parts = split(binding, "::");
        if ~isempty(parts) && strlength(parts(1)) > 0
            blocks(end + 1, 1) = parts(1); %#ok<AGROW>
        end
    end
end
blocks = unique(blocks, "stable");
end

function graph = task_graph(modelName, state)
if isstruct(state) && isfield(state, "model_graph") && ...
        isstruct(state.model_graph) && isfield(state.model_graph, "schema") && ...
        string(state.model_graph.schema) == "simuverity.sat-model-graph.v1"
    graph = state.model_graph;
else
    graph = sat_model_graph(char(modelName));
end
end

function [ok, path] = signal_reaches(graph, source, target)
query = struct("network", "signal", "direction", "forward", ...
    "source", struct("block", source), ...
    "target", struct("block", target));
[ok, evidence] = sat_graph_query(graph, query);
path = {};
if ok && isstruct(evidence) && isfield(evidence, "block_path")
    path = cellstr(string(evidence.block_path));
end
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
required = {'active_machine_blocks', 'machine_modes', ...
    'imposed_speed_machine_blocks', 'allowed_dynamic_machine_blocks', ...
    'unresolved_machine_blocks', 'command_driven_ideal_speed_sources'};
schemaOk = isstruct(facts) && isscalar(facts) && all(isfield(facts, required));
if ~schemaOk, ok = false; detail = "FACT_SCHEMA_INVALID"; return; end
if isempty(facts.active_machine_blocks)
    ok = false; detail = "D011_ACTIVE_PMSM_UNRESOLVED";
elseif ~isempty(facts.imposed_speed_machine_blocks)
    ok = false; detail = "D011_PMSM_SPEED_IS_EXTERNALLY_IMPOSED";
elseif ~isempty(facts.command_driven_ideal_speed_sources)
    ok = false; detail = "D011_COMMAND_DRIVES_IDEAL_SPEED_SOURCE";
elseif ~isempty(facts.unresolved_machine_blocks)
    ok = false; detail = "D011_MACHINE_MECHANICAL_MODE_UNRESOLVED";
elseif isempty(facts.allowed_dynamic_machine_blocks)
    ok = false; detail = "D011_MECHANICAL_DYNAMICS_NOT_PROVED";
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
    isfield(state.evidence, "unit_test_mechanical_facts");
end

function value = getp(block, parameter)
value = "";
try, value = string(get_param(char(block), parameter)); catch, end
end

function value = logical_field(row, name)
value = isstruct(row) && isfield(row, name) && isscalar(row.(name)) && ...
    logical(row.(name));
end

function items = field_items(value, name)
if ~isstruct(value) || ~isscalar(value) || ~isfield(value, name) || ...
        isempty(value.(name))
    items = {};
elseif iscell(value.(name))
    items = value.(name)(:).';
else
    items = arrayfun(@(row) row, value.(name), "UniformOutput", false);
end
end

function facts = empty_facts()
facts = struct( ...
    "active_machine_blocks", strings(0, 1), ...
    "machine_modes", struct("block", {}, "mode", {}, ...
        "classification", {}), ...
    "imposed_speed_machine_blocks", strings(0, 1), ...
    "allowed_dynamic_machine_blocks", strings(0, 1), ...
    "unresolved_machine_blocks", strings(0, 1), ...
    "command_blocks", strings(0, 1), ...
    "ideal_speed_source_blocks", strings(0, 1), ...
    "command_driven_ideal_speed_sources", strings(0, 1), ...
    "command_to_ideal_speed_paths", {cell(0, 1)});
end

function report = make_report(evaluated, valid, ok, detail, evidence)
report = struct( ...
    "task", "D011", ...
    "id", "D011.mechanical_causality", ...
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
