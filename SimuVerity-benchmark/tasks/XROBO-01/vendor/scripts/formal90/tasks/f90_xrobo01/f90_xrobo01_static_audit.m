function audit = f90_xrobo01_static_audit(modelPath, outputPath)
%f90_xrobo01_static_audit Extract trusted product and exact-port evidence.
% The offline SCORING_CORE policy owns qualification.  This MATLAB stage only resolves
% product library links and records actual Simulink/Simscape port edges.
arguments
    modelPath (1,1) string
    outputPath (1,1) string = ""
end

taskDir = fileparts(mfilename("fullpath"));
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(taskDir, "-begin");
def = f90_xrobo01_definition;
source = f90_xrobo01_source_setup;
audit = localEmptyAudit(modelPath);
try
    assert(isfile(modelPath), "SimuVerity:F90:XROBO01:CandidateMissing", ...
        "Candidate model is missing.");
    localAssignNominalInputs(def);
    [modelDir, model] = fileparts(modelPath);
    wasLoaded = bdIsLoaded(model);
    if ~wasLoaded
        environmentCleanup = localPrepareAuditEnvironment( ...
            modelDir); %#ok<NASGU>
        load_system(modelPath);
    end
    modelCleanup = onCleanup( ...
        @() localCloseIfNeeded(model, wasLoaded)); %#ok<NASGU>
    set_param(model, "SimulationCommand", "update");

    blocks = string(find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", ...
        "MatchFilter", @Simulink.match.activeVariants, ...
        "Type", "Block"));
    blocks = blocks(blocks ~= model);
    nodes = localNodes(blocks);
    signalEdges = localSignalEdges(nodes);
    physicalEdges = localPhysicalEdges(nodes);
    [signalEdges, physicalEdges, hierarchyComplete] = ...
        localHierarchyEdges(nodes, signalEdges, physicalEdges);
    signalEdges = localBlockTransferEdges(nodes, signalEdges);
    physicalEdges = localProductTransferEdges(nodes, physicalEdges);
    publicOutputs = localPublicOutputs(nodes);
    graphNodes = localGraphNodes(nodes);

    graph = struct( ...
        "schema", "simuverity.f90-xrobo01-port-network.v1", ...
        "nodes", graphNodes, ...
        "signal_edges", {signalEdges}, ...
        "physical_edges", {physicalEdges}, ...
        "public_outputs", publicOutputs, ...
        "source_binding_registered", logical(isfile(source.model) && ...
            localFilePresence(source.model) == lower(string( ...
            def.source.exact_file_presence))), ...
        "self_contained_callback", localSelfContainedCallback(model), ...
        "port_identity_complete", logical(all( ...
            [nodes.port_interface_complete])), ...
        "hierarchy_bridges_preserve_port_ordinals", ...
            logical(hierarchyComplete), ...
        "candidate_display_names_emitted", false, ...
        "candidate_mask_or_component_identity_emitted", false, ...
        "candidate_source_type_used_for_identity", false, ...
        "unresolved_reference_metadata_used_for_identity", false, ...
        "identity_fields", ["BlockType", ...
            "resolved product SourceBlock path", "LinkStatus", ...
            "resolved product library file"], ...
        "connection_port_metadata_api", ...
            "simscape.connectionPortProperties", ...
        "same_parent_subtree_is_not_a_network_edge", true);

    audit = struct( ...
        "schema", "simuverity.f90-xrobo01-static-audit.v1", ...
        "task_id", def.id, ...
        "formal_id", def.formal_id, ...
        "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
        "model_path", localCanonicalPath(modelPath), ...
        "model_file_presence", localFilePresence(modelPath), ...
        "matlab_release", string(version("-release")), ...
        "pass", false, ...
        "mechanism_fraction", 0, ...
        "checks", struct([]), ...
        "port_network", graph, ...
        "offline_structure_decision_required", true, ...
        "current_static_identity_and_subtree_semantics_superseded", true, ...
        "error_identifier", "", ...
        "error_message", "");
catch ME
    audit.error_identifier = string(ME.identifier);
    audit.error_message = string(ME.message);
end
audit.generated_at = string(datetime("now", "TimeZone", ...
    "Asia/Shanghai", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));
if strlength(outputPath) > 0
    folder = fileparts(outputPath);
    if ~isfolder(folder), mkdir(folder); end
    localWriteJson(outputPath, audit);
end
end

function nodes = localNodes(blocks)
template = struct( ...
    "id", "", "path", "", "handle", 0, "parent", "", ...
    "block_type", "", "semantic_type", "", ...
    "source_block", "", "source_type", "", ...
    "link_status", "", "library_root", "", ...
    "resolved_library_file", "", ...
    "resolved_library_under_matlabroot", false, ...
    "source_block_exists", false, "trusted_product", false, ...
    "port_interface_complete", true, ...
    "signal_input_handles", zeros(0, 1), ...
    "signal_output_handles", zeros(0, 1), ...
    "domain_handles", zeros(0, 1), ...
    "signal_input_ports", strings(0, 1), ...
    "signal_output_ports", strings(0, 1), ...
    "domain_ports", strings(0, 1), ...
    "port_labels", struct, "domain_families", struct, ...
    "connection_rows", struct([]), ...
    "joint_configuration", struct);
nodes = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    id = "n" + string(index);
    blockType = localGet(block, "BlockType");
    sourceBlockRaw = localGet(block, "SourceBlock");
    referenceBlock = localGet(block, "ReferenceBlock");
    if strlength(sourceBlockRaw) == 0
        sourceBlockRaw = referenceBlock;
    elseif strlength(referenceBlock) > 0 && ...
            localNormalizeSpace(referenceBlock) ~= ...
            localNormalizeSpace(sourceBlockRaw)
        sourceBlockRaw = "";
    end
    sourceBlock = localNormalizeSpace(sourceBlockRaw);
    sourceType = localNormalizeSpace(localGet(block, "SourceType"));
    linkStatus = lower(localGet(block, "LinkStatus"));
    [resolved, libraryFile, sourceExists, libraryRoot] = ...
        localResolvedProductLibrary(sourceBlockRaw);

    ordinaryInputs = localPortHandles(block, "Inport");
    ordinaryOutputs = localPortHandles(block, "Outport");
    connectionRows = localConnectionPortRows(block);
    connectionKinds = lower(string({connectionRows.interface_type}));
    physicalInputs = localRowHandles(connectionRows, ...
        connectionKinds == "input");
    physicalOutputs = localRowHandles(connectionRows, ...
        connectionKinds == "output");
    domains = localRowHandles(connectionRows, ...
        ismember(connectionKinds, ["domain", "compositedomain"]));
    unknownConnected = false;
    for row = 1:numel(connectionRows)
        if connectionRows(row).connected && ...
                strlength(connectionRows(row).interface_type) == 0
            unknownConnected = true;
        end
    end
    inputs = [ordinaryInputs; physicalInputs];
    outputs = [ordinaryOutputs; physicalOutputs];
    inputIds = id + "_si" + string((1:numel(inputs)).');
    outputIds = id + "_so" + string((1:numel(outputs)).');
    domainIds = id + "_d" + string((1:numel(domains)).');
    labels = struct;
    families = struct;
    for ordinal = 1:numel(inputs)
        labels.(inputIds(ordinal)) = localPortLabel( ...
            inputs(ordinal), connectionRows);
    end
    for ordinal = 1:numel(outputs)
        labels.(outputIds(ordinal)) = localPortLabel( ...
            outputs(ordinal), connectionRows);
    end
    for ordinal = 1:numel(domains)
        label = localPortLabel(domains(ordinal), connectionRows);
        labels.(domainIds(ordinal)) = label;
        families.(domainIds(ordinal)) = localDomainFamily( ...
            sourceBlock, label);
    end
    nodes(index) = struct( ...
        "id", id, "path", block, ...
        "handle", double(get_param(block, "Handle")), ...
        "parent", localGet(block, "Parent"), ...
        "block_type", blockType, ...
        "semantic_type", localGet(block, "SFBlockType"), ...
        "source_block", sourceBlock, ...
        "source_type", sourceType, "link_status", linkStatus, ...
        "library_root", libraryRoot, ...
        "resolved_library_file", libraryFile, ...
        "resolved_library_under_matlabroot", logical(resolved), ...
        "source_block_exists", logical(sourceExists), ...
        "trusted_product", logical(resolved && sourceExists && ...
            any(strcmpi(blockType, ...
            ["Reference", "SimscapeMultibodyBlock"])) && ...
            any(strcmpi(linkStatus, ["resolved", "implicit"]))), ...
        "port_interface_complete", ~unknownConnected, ...
        "signal_input_handles", inputs, ...
        "signal_output_handles", outputs, ...
        "domain_handles", domains, ...
        "signal_input_ports", inputIds, ...
        "signal_output_ports", outputIds, ...
        "domain_ports", domainIds, ...
        "port_labels", labels, "domain_families", families, ...
        "connection_rows", connectionRows, ...
        "joint_configuration", localJointConfiguration(block, ...
            sourceBlock, resolved && sourceExists));
end
end

function rows = localConnectionPortRows(block)
template = struct("handle", 0, "side", "", "ordinal", 0, ...
    "port_number", NaN, "name", "", "label", "", ...
    "interface_type", "", "connected", false);
rows = repmat(template, 0, 1);
try
    handles = get_param(block, "PortHandles");
catch
    return
end
for side = ["LConn", "RConn"]
    if ~isfield(handles, side), continue, end
    sideHandles = reshape(double(handles.(side)), 1, []);
    for ordinal = 1:numel(sideHandles)
        portNumber = str2double(localPortGet( ...
            sideHandles(ordinal), "PortNumber"));
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "handle", sideHandles(ordinal), "side", side, ...
            "ordinal", ordinal, "port_number", portNumber, ...
            "name", localPortGet(sideHandles(ordinal), "Name"), ...
            "label", "", "interface_type", "", ...
            "connected", localPortConnected(sideHandles(ordinal)));
    end
end
if isempty(rows), return, end
try
    properties = simscape.connectionPortProperties(block);
catch
    return
end
used = false(numel(properties), 1);
for row = 1:numel(rows)
    propertyIndex = 0;
    name = localNormalizeToken(rows(row).name);
    if strlength(name) > 0
        for candidate = 1:numel(properties)
            propertyName = localNormalizeToken( ...
                string(properties(candidate).Name));
            propertyLabel = localNormalizeToken( ...
                string(properties(candidate).Label));
            if ~used(candidate) && ...
                    (name == propertyName || name == propertyLabel)
                propertyIndex = candidate;
                break
            end
        end
    end
    if propertyIndex == 0 && numel(properties) == numel(rows) && ...
            ~used(row)
        propertyIndex = row;
    end
    if propertyIndex == 0, continue, end
    used(propertyIndex) = true;
    rows(row).label = string(properties(propertyIndex).Label);
    rows(row).interface_type = lower(string( ...
        properties(propertyIndex).Type.InterfaceType));
end
end

function edges = localSignalEdges(nodes)
edges = cell(0, 3);
for sourceNode = 1:numel(nodes)
    for sourceOrdinal = 1:numel( ...
            nodes(sourceNode).signal_output_handles)
        sourceHandle = nodes(sourceNode).signal_output_handles( ...
            sourceOrdinal);
        for targetNode = 1:numel(nodes)
            for targetOrdinal = 1:numel( ...
                    nodes(targetNode).signal_input_handles)
                targetHandle = nodes(targetNode).signal_input_handles( ...
                    targetOrdinal);
                if ~localPortsShareLine(sourceHandle, targetHandle)
                    continue
                end
                edges = localAddEdge(edges, ...
                    nodes(sourceNode).signal_output_ports(sourceOrdinal), ...
                    nodes(targetNode).signal_input_ports(targetOrdinal), ...
                    "connection_line");
            end
        end
    end
end
end

function edges = localPhysicalEdges(nodes)
edges = cell(0, 3);
for leftNode = 1:numel(nodes)
    for leftOrdinal = 1:numel(nodes(leftNode).domain_handles)
        for rightNode = leftNode:numel(nodes)
            first = 1;
            if rightNode == leftNode, first = leftOrdinal + 1; end
            for rightOrdinal = first:numel(nodes(rightNode).domain_handles)
                if ~localPortsShareLine( ...
                        nodes(leftNode).domain_handles(leftOrdinal), ...
                        nodes(rightNode).domain_handles(rightOrdinal))
                    continue
                end
                edges = localAddEdge(edges, ...
                    nodes(leftNode).domain_ports(leftOrdinal), ...
                    nodes(rightNode).domain_ports(rightOrdinal), ...
                    "connection_line");
            end
        end
    end
end
end

function [signalEdges, physicalEdges, complete] = ...
        localHierarchyEdges(nodes, signalEdges, physicalEdges)
complete = true;
for child = 1:numel(nodes)
    blockType = lower(nodes(child).block_type);
    parent = localNodePathIndex(nodes, nodes(child).parent);
    if parent <= 0, continue, end
    ordinal = localNumericParameter(nodes(child).path, "Port", 1);
    if blockType == "inport"
        if ordinal <= numel(nodes(parent).signal_input_ports) && ...
                ~isempty(nodes(child).signal_output_ports)
            signalEdges = localAddEdge(signalEdges, ...
                nodes(parent).signal_input_ports(ordinal), ...
                nodes(child).signal_output_ports(1), "hierarchy_in");
        else
            complete = false;
        end
    elseif blockType == "outport"
        if ordinal <= numel(nodes(parent).signal_output_ports) && ...
                ~isempty(nodes(child).signal_input_ports)
            signalEdges = localAddEdge(signalEdges, ...
                nodes(child).signal_input_ports(1), ...
                nodes(parent).signal_output_ports(ordinal), ...
                "hierarchy_out");
        else
            complete = false;
        end
    elseif blockType == "pmioport"
        [childKind, childId] = localOnlyConnectionPort(nodes(child));
        [parentKind, parentId] = localParentConnectionPort( ...
            nodes(parent), ordinal);
        if strlength(childId) == 0 || strlength(parentId) == 0 || ...
                childKind ~= parentKind
            complete = false;
            continue
        end
        if childKind == "domain"
            physicalEdges = localAddEdge(physicalEdges, ...
                childId, parentId, "hierarchy_port_ordinal");
        elseif childKind == "input"
            signalEdges = localAddEdge(signalEdges, ...
                parentId, childId, "hierarchy_input_ordinal");
        elseif childKind == "output"
            signalEdges = localAddEdge(signalEdges, ...
                childId, parentId, "hierarchy_output_ordinal");
        else
            complete = false;
        end
    end
end
end

function edges = localBlockTransferEdges(nodes, edges)
barriers = ["inport", "outport", "pmioport", ...
    "toworkspace", "terminator", "scope", "goto", "from"];
for node = 1:numel(nodes)
    ordinarySubsystem = lower(nodes(node).block_type) == "subsystem" && ...
        strlength(nodes(node).semantic_type) == 0;
    if ordinarySubsystem || ...
            any(lower(nodes(node).block_type) == barriers) || ...
            localProductSignalBarrier(nodes(node))
        continue
    end
    for input = reshape(nodes(node).signal_input_ports, 1, [])
        for output = reshape(nodes(node).signal_output_ports, 1, [])
            edges = localAddEdge(edges, input, output, ...
                "trusted_block_transfer");
        end
    end
end
end

function edges = localProductTransferEdges(nodes, edges)
for node = 1:numel(nodes)
    if ~nodes(node).trusted_product || ...
            ~localAllowsDomainTransfer(nodes(node))
        continue
    end
    ids = nodes(node).domain_ports;
    for left = 1:numel(ids)
        familyLeft = string(nodes(node).domain_families.(ids(left)));
        if strlength(familyLeft) == 0, continue, end
        for right = left + 1:numel(ids)
            familyRight = string(nodes(node).domain_families.(ids(right)));
            if familyLeft ~= familyRight, continue, end
            edges = localAddEdge(edges, ids(left), ids(right), ...
                "trusted_component_transfer");
        end
    end
end
end

function pass = localAllowsDomainTransfer(node)
source = lower(localNormalizeSpace(node.source_block));
pass = startsWith(source, "sm_lib/joints/") || ...
    startsWith(source, "sm_lib/body elements/") || ...
    endsWith(source, "/rigid transform") || ...
    startsWith(source, "fl_lib/electrical/") || ...
    startsWith(source, "fl_lib/mechanical/") || ...
    startsWith(source, "batteryecm_lib/") || ...
    startsWith(source, "ee_lib/electromechanical/");
end

function outputs = localPublicOutputs(nodes)
names = ["body_state", "contact_state", ...
    "gait_state", "electrical_state"];
channels = [6, 4, 3, 3];
outputs = struct;
for index = 1:numel(names)
    matches = zeros(0, 1);
    for node = 1:numel(nodes)
        if lower(nodes(node).block_type) == "toworkspace" && ...
                localGet(nodes(node).path, "VariableName") == names(index)
            matches(end + 1, 1) = node; %#ok<AGROW>
        end
    end
    row = struct("node_id", "", "anchor_port_id", "", ...
        "candidate_count", numel(matches), "timeseries", false, ...
        "max_data_points_inf", false, ...
        "expected_channels", channels(index));
    if numel(matches) == 1
        node = matches(1);
        row.node_id = nodes(node).id;
        if numel(nodes(node).signal_input_ports) == 1
            row.anchor_port_id = nodes(node).signal_input_ports(1);
        end
        row.timeseries = strcmpi( ...
            localGet(nodes(node).path, "SaveFormat"), "Timeseries");
        row.max_data_points_inf = strcmpi( ...
            localGet(nodes(node).path, "MaxDataPoints"), "inf");
    end
    outputs.(names(index)) = row;
end
end

function result = localGraphNodes(nodes)
template = struct("id", "", "block_type", "", "semantic_type", "", ...
    "source_block", "", "source_type", "", "link_status", "", ...
    "library_root", "", "resolved_library_file", "", ...
    "resolved_library_under_matlabroot", false, ...
    "source_block_exists", false, "port_interface_complete", false, ...
    "signal_input_ports", strings(0, 1), ...
    "signal_output_ports", strings(0, 1), ...
    "domain_ports", strings(0, 1), "port_labels", struct, ...
    "domain_families", struct, "joint_configuration", struct);
result = repmat(template, numel(nodes), 1);
for index = 1:numel(nodes)
    result(index) = struct( ...
        "id", nodes(index).id, ...
        "block_type", nodes(index).block_type, ...
        "semantic_type", nodes(index).semantic_type, ...
        "source_block", nodes(index).source_block, ...
        "source_type", nodes(index).source_type, ...
        "link_status", nodes(index).link_status, ...
        "library_root", nodes(index).library_root, ...
        "resolved_library_file", nodes(index).resolved_library_file, ...
        "resolved_library_under_matlabroot", ...
            nodes(index).resolved_library_under_matlabroot, ...
        "source_block_exists", nodes(index).source_block_exists, ...
        "port_interface_complete", ...
            nodes(index).port_interface_complete, ...
        "signal_input_ports", nodes(index).signal_input_ports, ...
        "signal_output_ports", nodes(index).signal_output_ports, ...
        "domain_ports", nodes(index).domain_ports, ...
        "port_labels", nodes(index).port_labels, ...
        "domain_families", nodes(index).domain_families, ...
        "joint_configuration", nodes(index).joint_configuration);
end
end

function [resolved, file, exists, root] = ...
        localResolvedProductLibrary(sourceBlock)
resolved = false;
file = "";
exists = false;
root = "";
parts = split(localNormalizeSpace(sourceBlock), "/");
if isempty(parts) || strlength(parts(1)) == 0, return, end
root = parts(1);
try
    if bdIsLoaded(root)
        file = string(get_param(root, "FileName"));
    else
        file = string(which(root));
    end
    if strlength(file) == 0, return, end
    resolved = localPathIsWithin(file, string(matlabroot));
    if ~resolved, return, end
    load_system(root);
    exists = double(getSimulinkBlockHandle(sourceBlock, true)) > 0;
catch
    resolved = false;
    exists = false;
end
end

function configuration = localJointConfiguration( ...
        block, sourceBlock, resolved)
configuration = struct;
if ~resolved || sourceBlock ~= "sm_lib/Joints/Revolute Joint"
    return
end
configuration = struct( ...
    "torque_actuation_mode", localGet(block, "TorqueActuationMode"), ...
    "motion_actuation_mode", localGet(block, "MotionActuationMode"), ...
    "sense_position", localGet(block, "SensePosition"), ...
    "sense_velocity", localGet(block, "SenseVelocity"));
end

function pass = localProductSignalBarrier(node)
if ~node.trusted_product
    pass = false;
    return
end
source = lower(localNormalizeSpace(node.source_block));
pass = source == "sm_lib/joints/revolute joint" || ...
    endsWith(source, "/transform sensor") || ...
    endsWith(source, "/current sensor") || ...
    endsWith(source, "/voltage sensor") || ...
    source == "sm_lib/forces and torques/external force and torque" || ...
    contains(source, "ee_lib/electromechanical/");
end

function family = localDomainFamily(sourceBlock, label)
source = lower(localNormalizeSpace(sourceBlock));
label = lower(localNormalizeSpace(label));
family = "";
if startsWith(source, "sm_lib/")
    family = "multibody_frame";
elseif startsWith(source, "batteryecm_lib/") || ...
        startsWith(source, "fl_lib/electrical/")
    family = "electrical";
elseif startsWith(source, "fl_lib/mechanical/")
    family = "mechanical";
elseif startsWith(source, "ee_lib/electromechanical/")
    if any(label == ["+", "-", "vp", "vm"])
        family = "electrical";
    elseif any(label == ["r", "c", "s", "o"])
        family = "mechanical";
    end
end
end

function [kind, id] = localOnlyConnectionPort(node)
kind = "";
id = "";
count = numel(node.signal_input_ports) + ...
    numel(node.signal_output_ports) + numel(node.domain_ports);
if count ~= 1, return, end
if ~isempty(node.signal_input_ports)
    kind = "input"; id = node.signal_input_ports(1);
elseif ~isempty(node.signal_output_ports)
    kind = "output"; id = node.signal_output_ports(1);
else
    kind = "domain"; id = node.domain_ports(1);
end
end

function [kind, id] = localParentConnectionPort(node, ordinal)
kind = "";
id = "";
rows = node.connection_rows;
if isempty(rows), return, end
numbers = double([rows.port_number]);
match = find(isfinite(numbers) & numbers == ordinal, 1);
if isempty(match) && ordinal <= numel(rows), match = ordinal; end
if isempty(match), return, end
handle = rows(match).handle;
input = find(node.signal_input_handles == handle, 1);
output = find(node.signal_output_handles == handle, 1);
domain = find(node.domain_handles == handle, 1);
if ~isempty(input)
    kind = "input"; id = node.signal_input_ports(input);
elseif ~isempty(output)
    kind = "output"; id = node.signal_output_ports(output);
elseif ~isempty(domain)
    kind = "domain"; id = node.domain_ports(domain);
end
end

function handles = localRowHandles(rows, selected)
handles = zeros(0, 1);
if isempty(rows), return, end
handles = reshape(double([rows(selected).handle]), [], 1);
end

function label = localPortLabel(handle, rows)
label = localPortGet(handle, "Name");
if isempty(rows), return, end
match = find(double([rows.handle]) == double(handle), 1);
if ~isempty(match) && strlength(rows(match).label) > 0
    label = rows(match).label;
end
label = localNormalizeSpace(label);
end

function pass = localPortsShareLine(left, right)
pass = false;
try
    leftLine = double(get_param(left, "Line"));
    rightLine = double(get_param(right, "Line"));
    if isempty(leftLine) || isempty(rightLine) || ...
            leftLine(1) < 0 || rightLine(1) < 0
        return
    end
    pass = ~isempty(intersect(localLineFamily(leftLine(1)), ...
        localLineFamily(rightLine(1))));
catch
end
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

function index = localNodePathIndex(nodes, pathValue)
index = 0;
match = find(string({nodes.path}) == string(pathValue), 1);
if ~isempty(match), index = match; end
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

function value = localNumericParameter(block, parameter, fallback)
value = fallback;
try
    raw = get_param(block, parameter);
    parsed = str2double(string(raw));
    if isfinite(parsed) && parsed >= 1, value = floor(parsed); end
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
value = localGet(port, parameter);
end

function value = localNormalizeSpace(value)
value = strip(regexprep(string(value), "\s+", " "));
if ~isscalar(value), value = join(value(:), " "); end
if ismissing(value), value = ""; end
end

function value = localNormalizeToken(value)
value = lower(regexprep(localNormalizeSpace(value), "[^A-Za-z0-9]", ""));
end

function pass = localSelfContainedCallback(model)
callbacks = ["PreLoadFcn", "PostLoadFcn", "InitFcn", "StartFcn"];
text = "";
for callback = callbacks
    text = text + newline + localGet(model, callback);
end
text = lower(text);
pass = ~contains(text, "sm_robot_run_4legs_param_def_load");
end

function localAssignNominalInputs(def)
for index = 1:numel(def.public_inputs)
    assignin("base", def.public_inputs(index).name, ...
        def.public_inputs(index).nominal);
end
end

function cleanup = localPrepareAuditEnvironment(modelDir)
oldPath = path;
oldDir = pwd;
cleanup = onCleanup(@() localRestoreEnvironment(oldPath, oldDir));
restoredefaultpath;
localKeepOnlyProductPaths(string(matlabroot));
addpath(genpath(modelDir), "-begin");
cd(modelDir);
end

function localKeepOnlyProductPaths(productRoot)
entries = string(strsplit(path, pathsep));
entries = entries(strlength(entries) > 0);
keep = false(size(entries));
for index = 1:numel(entries)
    keep(index) = localPathIsWithin(entries(index), productRoot);
end
assert(any(keep), "SimuVerity:F90:XROBO01:ProductPathMissing", ...
    "No standard MATLAB product paths remain for the SCORING_CORE audit.");
path(char(strjoin(entries(keep), pathsep)));
end

function localRestoreEnvironment(oldPath, oldDir)
try, cd(oldDir); catch, end
try, path(oldPath); catch, end
end

function localCloseIfNeeded(model, wasLoaded)
if ~wasLoaded
    try, close_system(model, 0); catch, end
end
end

function canonical = localCanonicalPath(pathValue)
canonical = string(java.io.File(char(pathValue)).getCanonicalPath());
end

function pass = localPathIsWithin(pathValue, rootValue)
pathCanonical = lower(localCanonicalPath(pathValue));
rootCanonical = lower(localCanonicalPath(rootValue));
pass = pathCanonical == rootCanonical || startsWith(pathCanonical, ...
    rootCanonical + string(filesep));
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function audit = localEmptyAudit(modelPath)
audit = struct( ...
    "schema", "simuverity.f90-xrobo01-static-audit.v1", ...
    "task_id", "XROBO01", "formal_id", "F90-XROBO-01", ...
    "generation_run_id", string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "model_path", modelPath, "model_file_presence", "", ...
    "matlab_release", string(version("-release")), ...
    "pass", false, "mechanism_fraction", 0, ...
    "checks", struct([]), "port_network", struct, ...
    "offline_structure_decision_required", true, ...
    "current_static_identity_and_subtree_semantics_superseded", true, ...
    "error_identifier", "", "error_message", "");
end

function localWriteJson(pathValue, payload)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XROBO01:JsonOpen", ...
    "Cannot write SCORING_CORE static evidence.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
end
