function evidence = f90_xmed07_extract_candidate_evidence_compatibility( ...
        candidatePath, outDir)
%f90_xmed07_extract_candidate_evidence_compatibility Bound-output exact-port audit.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end
assert(isfile(candidatePath), "SimuVerity:F90:XMED07:ModelMissing", ...
    "Candidate model is missing: %s", candidatePath);

taskDir = fileparts(mfilename("fullpath"));
root = localProjectRoot;
localRequireBinding(fullfile(taskDir, ...
    "f90_xmed07_extract_candidate_evidence_core.m"), ...
    "present");
localRequireBinding(fullfile(taskDir, ...
    "f90_xmed07_structure_policy.json"), ...
    "present");
localRequireBinding(fullfile(root, "scripts", "formal90", "tasks", ...
    "_shared", "simuverity_run_candidate_evidence.m"), ...
    "present");
localRequireBinding(fullfile(root, "scripts", "unified", ...
    "public_output", "simuverity_public_output_compatibility.m"), ...
    "present");

candidateBindingBefore = localFilePresence(candidatePath);
evidence = f90_xmed07_extract_candidate_evidence_core(candidatePath, outDir);
foundationAudit = evidence.static_audit;
audit = localCandidateStaticAudit(candidatePath, foundationAudit);
candidateBindingAfter = localFilePresence(candidatePath);
assert(candidateBindingBefore == candidateBindingAfter && ...
    string(evidence.sealed_candidate_file_presence_after) == candidateBindingAfter, ...
    "SimuVerity:F90:XMED07:CandidateChanged", ...
    "Simulation and GROUP_SCORING structural evidence bind different candidates.");

evidence.schema = "simuverity.f90-xmed07-evidence.v1";
evidence.static_audit = audit;
evidence.static_audit_method = ...
    "simuverity.f90-xmed07-bound-output-port-evidence.v1";
evidence.current_candidate_static_audit_superseded = true;
evidence.candidate_evidence_ready = true;
evidence.evidence_contract_valid = false;
evidence.extraction_only = true;
evidence.score_fields_present = false;
evidence.candidate_file_presence_before_current_audit = candidateBindingBefore;
evidence.candidate_file_presence_after_current_audit = candidateBindingAfter;
evidence.candidate_binding_preserved_by_current_audit = true;
evidence.current_evidence_engine_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmed07_extract_candidate_evidence_core.m"));
evidence.public_output_compat_file_presence = localFilePresence(fullfile(root, ...
    "scripts", "unified", "public_output", ...
    "simuverity_public_output_compatibility.m"));
localWriteJsonReplace(fullfile(outDir, "evidence.json"), evidence);
end

function audit = localCandidateStaticAudit(candidatePath, foundationAudit)
[modelDir, model] = fileparts(candidatePath);
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(modelDir, "-begin");
wasLoaded = bdIsLoaded(model);
if ~wasLoaded, load_system(candidatePath); end
modelCleanup = onCleanup( ...
    @() localCloseIfNeeded(model, wasLoaded)); %#ok<NASGU>

nodes = localNodes(model);
edges = localDirectedPortGraph(nodes);
[candidates, collisions] = localPublicOutputCandidates(model, nodes);
[sources, sourcePass] = localOutputSourcePorts(nodes, foundationAudit);
[causal, physical, factPass] = localAuditFacts(foundationAudit);

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
    "schema", "simuverity.f90-xmed07-port-graph.v1", ...
    "nodes", publicNodes, "edges", {edges}, ...
    "public_output_candidates", candidates, ...
    "public_output_source_ports", sources, ...
    "unsupported_direct_name_collisions", collisions, ...
    "current_causal_facts", causal, ...
    "current_physical_facts", physical, ...
    "current_output_source_contract_valid", logical(sourcePass), ...
    "fact_contract_valid", logical(factPass), ...
    "candidate_display_names_emitted", false, ...
    "candidate_mask_types_emitted", false, ...
    "port_identity_complete", true, ...
    "bus_creator_selector_all_to_all", false, ...
    "nested_or_top_level_outport_grants_public_binding", false, ...
    "candidate_logging_aliases_union_with_direct_outputs", false, ...
    "public_output_resolution", ...
        "simuverity_public_output_compatibility direct-before-logsout precedence");
audit = struct( ...
    "structure_port_graph", graph, ...
    "structure_decision_deferred_to_offline_policy", true, ...
    "current_public_output_sinks_superseded", true, ...
    "public_output_container_binding_required", true, ...
    "port_number_preserving_hierarchy_bridges", true);
coreFields = [ ...
    "top_command_to_software", "top_software_to_motor_plant", ...
    "top_plant_feedback_to_software", ...
    "software_reference_to_motor_controller", ...
    "measured_speed_to_motor_controller", ...
    "measured_speed_to_occlusion_detector", ...
    "load_force_to_occlusion_detector", "occlusion_to_supervisory", ...
    "remaining_units_to_supervisory", "physical_motor_present", ...
    "physical_transmission_present", "physical_slide_present", ...
    "physical_reservoir_present", "physical_delivery_line_present", ...
    "physical_patient_boundary_present", ...
    "physical_upstream_flow_sensor_present", ...
    "physical_patient_flow_sensor_present", ...
    "native_occlusion_source_present", ...
    "controller_component_models_present"];
for field = coreFields, audit.(field) = false; end
end

function [sources, pass] = localOutputSourcePorts(nodes, foundationAudit)
names = ["motion_state", "delivery_state", "safety_state"];
sources = struct;
pass = isfield(foundationAudit, "public_output_upstream");
if ~pass
    for name = names, sources.(name) = cell(0, 1); end
    return
end
for name = names
    groups = cell(4, 1);
    if ~isfield(foundationAudit.public_output_upstream, name)
        sources.(name) = groups;
        pass = false;
        continue
    end
    output = foundationAudit.public_output_upstream.(name);
    if ~isfield(output, "role_paths") || numel(output.role_paths) ~= 4
        sources.(name) = groups;
        pass = false;
        continue
    end
    for index = 1:4
        row = output.role_paths(index);
        if ~isfield(row, "source_candidates")
            groups{index} = strings(0, 1);
            pass = false;
            continue
        end
        groups{index} = localPathsOutputPorts( ...
            nodes, row.source_candidates);
        pass = pass && ~isempty(groups{index});
    end
    sources.(name) = groups;
end
end

function ports = localPathsOutputPorts(nodes, pathValues)
ports = strings(0, 1);
values = unique(reshape(string(pathValues), [], 1), "stable");
for value = values.'
    node = localNodePathIndex(nodes, value);
    if node > 0
        ports = [ports; nodes(node).output_ids]; %#ok<AGROW>
    end
end
ports = unique(ports(strlength(ports) > 0), "stable");
end

function [causal, physical, pass] = localAuditFacts(foundationAudit)
causalNames = [ ...
    "command_to_supervisor", "supervisor_to_motor_controller", ...
    "motor_controller_to_actuator", "speed_to_motor_controller", ...
    "speed_to_occlusion_detector", "force_to_occlusion_detector", ...
    "occlusion_detector_to_supervisor", "remaining_to_supervisor", ...
    "controller_components"];
causal = struct;
physical = struct( ...
    "main_chain", false, "upstream_flow_sensor", false, ...
    "patient_flow_sensor", false, "occlusion_source", false);
pass = isfield(foundationAudit, "raw_causal_facts") && ...
    isfield(foundationAudit, "raw_physical_facts");
for name = causalNames
    value = false;
    if pass && isfield(foundationAudit.raw_causal_facts, name)
        value = logical(foundationAudit.raw_causal_facts.(name));
    else
        pass = false;
    end
    causal.(name) = value;
end
if isfield(foundationAudit, "raw_physical_facts") && ...
        isfield(foundationAudit.raw_physical_facts, ...
            "motor_transmission_slide_reservoir_line_patient")
    rawPhysical = foundationAudit.raw_physical_facts;
    physical.main_chain = logical( ...
        rawPhysical.motor_transmission_slide_reservoir_line_patient);
else
    pass = false;
end
if isfield(foundationAudit, "physical_upstream_flow_witness")
    physical.upstream_flow_sensor = ...
        ~isempty(foundationAudit.physical_upstream_flow_witness);
else
    pass = false;
end
if isfield(foundationAudit, "physical_patient_flow_witness")
    physical.patient_flow_sensor = ...
        ~isempty(foundationAudit.physical_patient_flow_witness);
else
    pass = false;
end
if isfield(foundationAudit, "physical_occlusion_witness")
    physical.occlusion_source = ...
        ~isempty(foundationAudit.physical_occlusion_witness);
else
    pass = false;
end
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
names = ["motion_state", "delivery_state", "safety_state"];
template = struct("container_kind", "", ...
    "container_node_id", "", "anchor_port_id", "");
candidates = struct;
collisions = struct;
for name = names
    rows = repmat(template, 0, 1);
    for node = 1:numel(nodes)
        if lower(nodes(node).block_type) ~= "toworkspace" || ...
                localGet(nodes(node).path, "VariableName") ~= name || ...
                numel(nodes(node).input_handles) ~= 1 || ...
                ~localPortConnected(nodes(node).input_handles(1))
            continue
        end
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "container_kind", "simulation_output_toworkspace", ...
            "container_node_id", nodes(node).id, ...
            "anchor_port_id", nodes(node).input_ids(1));
    end
    for node = 1:numel(nodes)
        for ordinal = 1:numel(nodes(node).output_handles)
            port = nodes(node).output_handles(ordinal);
            if ~localOn(localPortGet(port, "DataLogging")) || ...
                    localEffectiveLoggingName(port) ~= name
                continue
            end
            rows(end + 1, 1) = struct( ... %#ok<AGROW>
                "container_kind", "logsout_exact_element", ...
                "container_node_id", nodes(node).id, ...
                "anchor_port_id", nodes(node).output_ids(ordinal));
        end
    end
    candidates.(name) = rows;
    collisions.(name) = localUnsupportedDirectCollisionCount( ...
        model, nodes, name);
end
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
    "SimuVerity:F90:XMED07:DependencyBinding", ...
    "A declared GROUP_SCORING dependency is missing or changed.");
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function localWriteJsonReplace(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMED07:WriteJson", ...
    "Cannot write GROUP_SCORING evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
