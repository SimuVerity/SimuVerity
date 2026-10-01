function evidence = f90_xmed05_extract_evidence(modelPath, outDir)
%f90_xmed05_extract_evidence Bound public outputs on an exact port graph.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
assert(isfile(modelPath), "SimuVerity:F90:XMED05:ModelMissing", ...
    "Candidate model is missing: %s", modelPath);

taskDir = fileparts(mfilename("fullpath"));
root = localProjectRoot;
localRequireBinding(fullfile(taskDir, ...
    "f90_xmed05_extract_evidence_core.m"), ...
    "present");
localRequireBinding(fullfile(root, "scripts", "unified", ...
    "public_output", "simuverity_public_output_compatibility.m"), ...
    "present");

candidateBindingBefore = localFilePresence(modelPath);
evidence = f90_xmed05_extract_evidence_core(modelPath, outDir);
foundationAudit = evidence.static_audit;
audit = localCandidateStaticAudit(modelPath, foundationAudit);
candidateBindingAfter = localFilePresence(modelPath);
assert(candidateBindingBefore == candidateBindingAfter && ...
    string(evidence.model_file_presence) == candidateBindingAfter, ...
    "SimuVerity:F90:XMED05:CandidateChanged", ...
    "Simulation and GROUP_SCORING structural evidence bind different candidates.");

evidence.schema = "simuverity.f90-xmed05-evidence.v1";
evidence.static_audit = audit;
evidence.static_audit_method = ...
    "simuverity.f90-xmed05-bound-output-port-evidence.v1";
evidence.current_candidate_static_audit_superseded = true;
evidence.candidate_evidence_ready = true;
evidence.evidence_contract_valid = false;
evidence.extraction_only = true;
evidence.score_fields_present = false;
evidence.candidate_file_presence_before_current_audit = candidateBindingBefore;
evidence.candidate_file_presence_after_current_audit = candidateBindingAfter;
evidence.candidate_binding_preserved_by_current_audit = true;
evidence.current_evidence_engine_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmed05_extract_evidence_core.m"));
evidence.public_output_compat_file_presence = localFilePresence(fullfile(root, ...
    "scripts", "unified", "public_output", ...
    "simuverity_public_output_compatibility.m"));
localWriteJsonReplace(fullfile(outDir, "evidence.json"), evidence);
end

function audit = localCandidateStaticAudit(modelPath, foundationAudit)
[modelDir, model] = fileparts(modelPath);
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(modelDir, "-begin");
wasLoaded = bdIsLoaded(model);
if ~wasLoaded, load_system(modelPath); end
modelCleanup = onCleanup( ...
    @() localCloseIfNeeded(model, wasLoaded)); %#ok<NASGU>

nodes = localNodes(model);
edges = localDirectedPortGraph(nodes);
[candidates, collisions] = localPublicOutputCandidates(model, nodes);
[selectedRoles, rolePorts, roleSelectionPass, boundedPass] = ...
    localSelectedRoleContract(nodes, foundationAudit);

publicNodes = repmat(struct( ...
    "id", "", "block_type", "", ...
    "input_ports", strings(0, 1), ...
    "output_ports", strings(0, 1)), numel(nodes), 1);
for index = 1:numel(nodes)
    publicNodes(index) = struct( ...
        "id", nodes(index).id, ...
        "block_type", nodes(index).block_type, ...
        "input_ports", nodes(index).input_ids, ...
        "output_ports", nodes(index).output_ids);
end
graph = struct( ...
    "schema", "simuverity.f90-xmed05-port-graph.v1", ...
    "nodes", publicNodes, "edges", {edges}, ...
    "selected_roles", selectedRoles, ...
    "role_ports", rolePorts, ...
    "public_output_candidates", candidates, ...
    "unsupported_direct_name_collisions", collisions, ...
    "name_neutral_role_selection", logical(roleSelectionPass), ...
    "bounded_pacing_delivery_verified", logical(boundedPass), ...
    "candidate_display_names_emitted", false, ...
    "candidate_mask_types_emitted", false, ...
    "port_identity_complete", true, ...
    "bus_creator_selector_all_to_all", false, ...
    "candidate_logging_aliases_union_with_direct_outputs", false, ...
    "public_output_resolution", ...
        "simuverity_public_output_compatibility direct-before-logsout precedence");
audit = struct( ...
    "structure_port_graph", graph, ...
    "structure_decision_deferred_to_offline_policy", true, ...
    "behavioral_pacing_support", foundationAudit.behavioral_pacing_support, ...
    "minimum_hybrid_closed_loop_signature", false, ...
    "display_name_used_for_role_discovery", false, ...
    "display_name_is_sufficient", false, ...
    "mask_type_is_trusted_identity", false, ...
    "public_output_container_binding_required", true, ...
    "port_number_preserving_hierarchy_bridges", true);
end

function [roles, ports, rolePass, boundedPass] = ...
        localSelectedRoleContract(nodes, foundationAudit)
roles = struct( ...
    "cardiac_response", "", "sensing", "", ...
    "ddd_logic", "", "bounded_pacing_delivery", "");
ports = struct( ...
    "cardiac_response_outputs", strings(0, 1), ...
    "sensing_inputs", strings(0, 1), ...
    "sensing_outputs", strings(0, 1), ...
    "ddd_logic_inputs", strings(0, 1), ...
    "ddd_command_outputs", strings(0, 1), ...
    "ddd_accepted_outputs", strings(0, 1), ...
    "pacing_delivery_inputs", strings(0, 1), ...
    "pacing_delivery_outputs", strings(0, 1), ...
    "cardiac_response_inputs", strings(0, 1));
rolePass = false;
boundedPass = false;
if ~isfield(foundationAudit, "role_path_witnesses"), return, end
chain = foundationAudit.role_path_witnesses;
roleFields = [ ...
    "cardiac_response_block", "sensing_block", ...
    "ddd_logic_block", "bounded_pacing_delivery_block"];
roleNames = [ ...
    "cardiac_response", "sensing", ...
    "ddd_logic", "bounded_pacing_delivery"];
indices = zeros(1, numel(roleFields));
for index = 1:numel(roleFields)
    if ~isfield(chain, roleFields(index)), return, end
    indices(index) = localNodePathIndex(nodes, ...
        string(chain.(roleFields(index))));
    if indices(index) <= 0, return, end
    roles.(roleNames(index)) = nodes(indices(index)).id;
end
if numel(unique(indices)) ~= numel(indices), return, end

mappings = { ...
    "cardiac_response_outputs", 1, "output"; ...
    "sensing_inputs", 2, "input"; ...
    "sensing_outputs", 2, "output"; ...
    "ddd_logic_inputs", 3, "input"; ...
    "ddd_command_outputs", 3, "output"; ...
    "ddd_accepted_outputs", 3, "output"; ...
    "pacing_delivery_inputs", 4, "input"; ...
    "pacing_delivery_outputs", 4, "output"; ...
    "cardiac_response_inputs", 1, "input"};
for row = 1:size(mappings, 1)
    field = string(mappings{row, 1});
    nodeIndex = indices(mappings{row, 2});
    if ~isfield(chain, field), return, end
    ordinals = reshape(double(chain.(field)), [], 1);
    values = localOrdinalPortIds(nodes(nodeIndex), ...
        ordinals, string(mappings{row, 3}));
    if numel(values) ~= 2, return, end
    ports.(field) = values;
end
rolePass = logical(foundationAudit.display_name_used_for_role_discovery == false) && ...
    logical(foundationAudit.display_name_is_sufficient == false) && ...
    logical(foundationAudit.mask_type_is_trusted_identity == false) && ...
    logical(chain.role_blocks_are_distinct) && ...
    logical(chain.chamber_ports_are_distinct);
boundedPass = logical(chain.bounded_pacing_delivery_verified);
end

function ids = localOrdinalPortIds(node, ordinals, direction)
ids = strings(0, 1);
if numel(ordinals) ~= 2 || numel(unique(ordinals)) ~= 2 || ...
        any(~isfinite(ordinals)) || any(ordinals < 1) || ...
        any(mod(ordinals, 1) ~= 0)
    return
end
if direction == "input", available = node.input_ids;
else, available = node.output_ids;
end
if any(ordinals > numel(available)), return, end
ids = reshape(available(ordinals), [], 1);
end

function nodes = localNodes(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
blocks = blocks(blocks ~= model);
template = struct( ...
    "id", "", "path", "", "handle", 0, "parent", "", ...
    "block_type", "", ...
    "input_handles", zeros(0, 1), ...
    "output_handles", zeros(0, 1), ...
    "input_ids", strings(0, 1), ...
    "output_ids", strings(0, 1));
nodes = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    inputs = localPortHandles(block, "Inport");
    outputs = localPortHandles(block, "Outport");
    id = "n" + string(index);
    nodes(index) = struct( ...
        "id", id, "path", block, ...
        "handle", double(get_param(block, "Handle")), ...
        "parent", localGet(block, "Parent"), ...
        "block_type", localGet(block, "BlockType"), ...
        "input_handles", inputs, "output_handles", outputs, ...
        "input_ids", id + ":i" + string((1:numel(inputs)).'), ...
        "output_ids", id + ":o" + string((1:numel(outputs)).'));
end
end

function edges = localDirectedPortGraph(nodes)
edges = cell(0, 3);
for sourceNode = 1:numel(nodes)
    for sourceOrdinal = 1:numel(nodes(sourceNode).output_handles)
        sourcePort = nodes(sourceNode).output_handles(sourceOrdinal);
        for destinationPort = reshape( ...
                localDestinationPorts(sourcePort), 1, [])
            destinationNode = localNodeForPort(nodes, destinationPort);
            if destinationNode <= 0, continue, end
            destinationOrdinal = find( ...
                nodes(destinationNode).input_handles == destinationPort, 1);
            if isempty(destinationOrdinal), continue, end
            edges = localAddEdge(edges, ...
                nodes(sourceNode).output_ids(sourceOrdinal), ...
                nodes(destinationNode).input_ids(destinationOrdinal), ...
                "signal_line");
        end
    end
end
edges = localHierarchyEdges(nodes, edges);
safeBarriers = ["subsystem", "inport", "outport", ...
    "toworkspace", "terminator", "scope", "goto", "from", ...
    "buscreator", "busselector"];
for node = 1:numel(nodes)
    if any(lower(nodes(node).block_type) == safeBarriers), continue, end
    for input = reshape(nodes(node).input_ids, 1, [])
        for output = reshape(nodes(node).output_ids, 1, [])
            edges = localAddEdge(edges, input, output, "block_transfer");
        end
    end
end
end

function edges = localHierarchyEdges(nodes, edges)
for child = 1:numel(nodes)
    blockType = lower(nodes(child).block_type);
    if blockType ~= "inport" && blockType ~= "outport", continue, end
    parent = localNodePathIndex(nodes, nodes(child).parent);
    if parent <= 0, continue, end
    ordinal = localNumericBlockParameter(nodes(child).path, "Port");
    if ~isfinite(ordinal) || ordinal < 1, continue, end
    ordinal = floor(ordinal);
    if blockType == "inport" && ...
            ordinal <= numel(nodes(parent).input_ids) && ...
            ~isempty(nodes(child).output_ids)
        edges = localAddEdge(edges, nodes(parent).input_ids(ordinal), ...
            nodes(child).output_ids(1), "hierarchy_in");
    elseif blockType == "outport" && ...
            ordinal <= numel(nodes(parent).output_ids) && ...
            ~isempty(nodes(child).input_ids)
        edges = localAddEdge(edges, nodes(child).input_ids(1), ...
            nodes(parent).output_ids(ordinal), "hierarchy_out");
    end
end
end

function [candidates, collisions] = localPublicOutputCandidates(model, nodes)
names = ["CardiacEGM", "PacingEvents"];
widths = [2, 8];
template = struct( ...
    "container_kind", "", "container_node_id", "", ...
    "channel_target_port_ids", strings(0, 1));
candidates = struct;
collisions = struct;
for outputIndex = 1:numel(names)
    name = names(outputIndex);
    width = widths(outputIndex);
    rows = repmat(template, 0, 1);
    for node = 1:numel(nodes)
        if lower(nodes(node).block_type) ~= "toworkspace" || ...
                localGet(nodes(node).path, "VariableName") ~= name || ...
                numel(nodes(node).input_handles) ~= 1
            continue
        end
        sources = localSourcePorts(nodes(node).input_handles(1));
        if numel(sources) ~= 1, continue, end
        aggregator = localNodeForPort(nodes, sources(1));
        targets = localAggregatorTargets(nodes, aggregator, width);
        if numel(targets) ~= width, continue, end
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "container_kind", "simulation_output_toworkspace", ...
            "container_node_id", nodes(node).id, ...
            "channel_target_port_ids", targets);
    end
    for node = 1:numel(nodes)
        logged = false;
        for port = reshape(nodes(node).output_handles, 1, [])
            if localOn(localPortGet(port, "DataLogging")) && ...
                    localEffectiveLoggingName(port) == name
                logged = true;
                break
            end
        end
        if ~logged, continue, end
        targets = localAggregatorTargets(nodes, node, width);
        if numel(targets) ~= width, continue, end
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "container_kind", "logsout_exact_element", ...
            "container_node_id", nodes(node).id, ...
            "channel_target_port_ids", targets);
    end
    candidates.(name) = rows;
    collisions.(name) = localUnsupportedDirectCollisionCount( ...
        model, nodes, name);
end
end

function targets = localAggregatorTargets(nodes, node, width)
targets = strings(0, 1);
if node <= 0 || ~any(lower(nodes(node).block_type) == ...
        ["mux", "vectorconcatenate", "matrixconcatenate"]) || ...
        numel(nodes(node).input_handles) ~= width
    return
end
connected = arrayfun(@localPortConnected, nodes(node).input_handles);
if ~all(connected), return, end
targets = nodes(node).input_ids;
end

function count = localUnsupportedDirectCollisionCount(model, nodes, name)
count = 0;
for node = 1:numel(nodes)
    if lower(nodes(node).block_type) == "scope" && ...
            localOn(localGet(nodes(node).path, "SaveToWorkspace")) && ...
            localGet(nodes(node).path, "SaveName") == name
        count = count + 1;
    end
end
pairs = [ ...
    "SaveOutput", "OutputSaveName"; ...
    "SaveState", "StateSaveName"; ...
    "SaveTime", "TimeSaveName"; ...
    "SaveFinalState", "FinalStateName"; ...
    "DSMLogging", "DSMLoggingName"];
for index = 1:size(pairs, 1)
    if localOn(localGet(model, pairs(index, 1))) && ...
            localGet(model, pairs(index, 2)) == name
        count = count + 1;
    end
end
end

function destinations = localDestinationPorts(sourcePort)
destinations = zeros(0, 1);
try
    line = double(get_param(sourcePort, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        value = double(get_param(item, "DstPortHandle"));
        destinations = [destinations; value(:)]; %#ok<AGROW>
    end
catch
end
destinations = unique(destinations( ...
    isfinite(destinations) & destinations > 0), "stable");
end

function sources = localSourcePorts(destinationPort)
sources = zeros(0, 1);
try
    line = double(get_param(destinationPort, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        value = double(get_param(item, "SrcPortHandle"));
        sources = [sources; value(:)]; %#ok<AGROW>
    end
catch
end
sources = unique(sources(isfinite(sources) & sources > 0), "stable");
end

function family = localLineFamily(seed)
family = zeros(0, 1);
pending = unique(double(seed(seed > 0)));
while ~isempty(pending)
    current = pending(1);
    pending(1) = [];
    if any(family == current), continue, end
    family(end + 1, 1) = current; %#ok<AGROW>
    relatives = zeros(0, 1);
    for property = ["LineParent", "LineChildren"]
        try
            value = double(get_param(current, property));
            relatives = [relatives; value(:)]; %#ok<AGROW>
        catch
        end
    end
    relatives = relatives(isfinite(relatives) & relatives > 0);
    pending = unique([pending(:); relatives(:)]);
end
end

function value = localEffectiveLoggingName(port)
value = strtrim(localPortGet(port, "DataLoggingName"));
if strlength(value) > 0, return, end
try
    line = double(get_param(port, "Line"));
    if isempty(line) || line(1) < 0, return, end
    family = localLineFamily(line(1));
    for item = reshape(family, 1, [])
        candidate = strtrim(localGet(item, "Name"));
        if strlength(candidate) > 0, value = candidate; return, end
    end
catch
end
end

function edges = localAddEdge(edges, source, target, kind)
source = string(source);
target = string(target);
kind = string(kind);
if strlength(source) == 0 || strlength(target) == 0 || source == target
    return
end
if ~isempty(edges)
    duplicate = string(edges(:, 1)) == source & ...
        string(edges(:, 2)) == target & string(edges(:, 3)) == kind;
    if any(duplicate), return, end
end
edges(end + 1, :) = {char(source), char(target), char(kind)};
end

function handles = localPortHandles(block, field)
handles = zeros(0, 1);
try
    ports = get_param(block, "PortHandles");
    if isfield(ports, field)
        handles = reshape(double(ports.(field)), [], 1);
    end
catch
end
end

function index = localNodeForPort(nodes, port)
index = 0;
try
    parent = get_param(port, "Parent");
    if isnumeric(parent), owner = double(parent);
    else, owner = double(get_param(parent, "Handle"));
    end
    match = find(double([nodes.handle]) == owner, 1);
    if ~isempty(match), index = match; end
catch
end
end

function index = localNodePathIndex(nodes, pathValue)
index = 0;
match = find(string({nodes.path}) == string(pathValue), 1);
if ~isempty(match), index = match; end
end

function value = localNumericBlockParameter(block, parameter)
value = nan;
try
    raw = get_param(block, parameter);
    if isnumeric(raw) && isscalar(raw), value = double(raw);
    else, value = str2double(string(raw));
    end
catch
end
end

function pass = localPortConnected(port)
pass = false;
try
    line = double(get_param(port, "Line"));
    pass = any(isfinite(line) & line >= 0);
catch
end
end

function value = localGet(object, parameter)
value = "";
try
    value = string(get_param(object, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
    if ismissing(value), value = ""; end
catch
end
end

function value = localPortGet(port, parameter)
value = "";
try
    value = string(get_param(port, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
    if ismissing(value), value = ""; end
catch
end
end

function pass = localOn(value)
pass = any(lower(strtrim(string(value))) == ["on", "true", "1", "yes"]);
end

function localCloseIfNeeded(model, wasLoaded)
if ~wasLoaded
    try, close_system(model, 0); catch, end
end
end

function localRequireBinding(pathValue, expected)
assert(isfile(pathValue) && localFilePresence(pathValue) == lower(string(expected)), ...
    "SimuVerity:F90:XMED05:DependencyBinding", ...
    "A declared GROUP_SCORING dependency is missing or changed.");
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function localWriteJsonReplace(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMED05:WriteJson", ...
    "Cannot write GROUP_SCORING evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
