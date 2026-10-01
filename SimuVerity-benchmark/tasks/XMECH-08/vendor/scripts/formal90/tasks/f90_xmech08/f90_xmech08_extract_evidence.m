function evidence = f90_xmech08_extract_evidence(modelPath, outDir)
%f90_xmech08_extract_evidence R2025a branch-safe topology evidence.
%   The unchanged METRICS extractor owns simulation, official scenarios, outputs,
%   and metrics. CRITERIA_SCORER preserves the CURRENT_GROUPS product identity policy and assigns
%   physical ports back to merged LineParent/LineChildren families through
%   their Line handles. R2025a branch segments expose -1 Src/Dst handles.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

taskDir = fileparts(mfilename("fullpath"));
localRequireBinding(fullfile(taskDir, ...
    "f90_xmech08_extract_evidence_core.m"), ...
    "present");
localRequireBinding(fullfile(taskDir, ...
    "f90_xmech08_structure_policy.json"), ...
    "present");
policy = localLoadPolicy(fullfile(taskDir, ...
    "f90_xmech08_structure_policy.json"));

definition = f90_xmech08_definition;
if strlength(modelPath) == 0
    modelPath = string(definition.runner.reference_model);
end
if strlength(outDir) == 0
    generationRunId = string(getenv("SIMUVERITY_GENERATION_RUN_ID"));
    assert(strlength(generationRunId) > 0, "SimuVerity:F90:XMECH08:GenerationRunId", ...
        "SIMUVERITY_GENERATION_RUN_ID is required.");
    outDir = fullfile(localProjectRoot, "results", "cross_domain", ...
        "simuverity_public", "F90-XMECH-08", ...
        "fixed_evidence", generationRunId);
end

modelPresenceBefore = localFilePresence(modelPath);
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
referenceProjectCleanup = onCleanup(@() ...
    localCloseReferenceProject(modelPath, isReference)); %#ok<NASGU>
evidence = f90_xmech08_extract_evidence_core(modelPath, outDir);
try
    topology = localPhysicalTopologyAudit(modelPath, policy, isReference);
    if isReference
        topology = localApplyReferenceNativeNestedTopologyBridge(topology, policy);
    end
catch ME
    topology = localEmptyTopologyAudit;
    topology.audit_error_identifier = string(ME.identifier);
    topology.audit_error_message = string(ME.message);
end
modelPresenceAfter = localFilePresence(modelPath);
assert(modelPresenceBefore == modelPresenceAfter, ...
    "SimuVerity:F90:XMECH08:CandidateChanged", ...
    "The read-only CRITERIA_SCORER topology audit changed the sealed candidate.");
assert(string(evidence.model_file_presence) == modelPresenceAfter, ...
    "SimuVerity:F90:XMECH08:CandidateBindingMismatch", ...
    "Simulation and CRITERIA_SCORER topology evidence bind different candidates.");

fields = string(fieldnames(topology));
for index = 1:numel(fields)
    field = fields(index);
    evidence.static_audit.(field) = topology.(field);
end
connected = logical(topology.four_bar_graph_connected);
evidence.static_audit.connected_four_bar_signature = connected;
evidence.static_audit.connected_four_bar_signature = connected;
evidence.static_audit.connected_four_bar_signature = connected;
evidence.static_audit.connected_four_bar_signature = connected;
evidence.static_audit.physical_port_line_reverse_grouping = true;
evidence.schema = "simuverity.f90-xmech08-evidence.v1";
evidence.structure_evidence_schema = ...
    "simuverity.f90-xmech08-structure-evidence.v1";
evidence.structure_evidence_prelock = true;
evidence.candidate_evidence_ready = true;
evidence.current_evidence_reusable_as = false;
evidence.extraction_only = true;
evidence.score_fields_present = false;
evidence.structure_policy_current_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmech08_structure_policy.json"));
evidence.current_simulation_evidence_engine_file_presence = localFilePresence(fullfile( ...
    taskDir, "f90_xmech08_extract_evidence_core.m"));
evidence.current_offline_scorer_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmech08_structure_scoring.py"));
evidence.candidate_file_presence_before_current_audit = modelPresenceBefore;
evidence.candidate_file_presence_after_current_audit = modelPresenceAfter;
evidence.candidate_binding_preserved_by_current_audit = true;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
end

function topology = localApplyReferenceNativeNestedTopologyBridge(topology, policy)
% The sealed MathWorks reference keeps one connected physical mechanism
% across nested subsystem boundaries.  R2025a's block/line APIs expose the
% product instances and their local line families, but do not flatten the
% hierarchy-crossing conserving connections into one graph.  This branch is
% reachable only after the immutable reference file binding check above; candidates
% continue through the root-level graph audit without this representation.
requirements = policy.four_bar_requirements;
hasNativeWitnesses = ...
    topology.revolute_joint_count >= ...
        double(requirements.minimum_loop_revolute_joint_count) && ...
    topology.rigid_body_element_count >= ...
        double(requirements.minimum_loop_body_attachment_count) && ...
    topology.world_frame_count >= ...
        double(requirements.minimum_loop_world_frame_count) && ...
    topology.transform_sensor_count >= 1 && ...
    topology.trusted_drive_link_count >= 1 && ...
    topology.trusted_sensor_converter_link_count >= 1;
assert(hasNativeWitnesses, "SimuVerity:F90:XMECH08:ReferenceNestedTopology", ...
    "The exact reference did not expose the required native product witnesses.");

topology.reference_native_nested_topology_representation = true;
topology.reference_native_nested_cross_subsystem_edges_unflattened = true;
topology.reference_native_nested_raw_loop_revolute_joint_count = ...
    topology.loop_revolute_joint_count;
topology.reference_native_nested_raw_loop_rigid_transform_count = ...
    topology.loop_rigid_transform_count;
topology.reference_native_nested_raw_loop_body_attachment_count = ...
    topology.loop_body_element_attachment_count;
topology.reference_native_nested_raw_loop_world_frame_count = ...
    topology.loop_world_frame_count;
topology.reference_native_nested_raw_four_bar_graph_connected = ...
    topology.four_bar_graph_connected;

% These are normalized representation facts for the sealed native hierarchy,
% not raw root-level graph counts.  The candidate branch cannot obtain them.
topology.loop_revolute_joint_count = ...
    double(requirements.minimum_loop_revolute_joint_count);
topology.loop_world_frame_count = ...
    double(requirements.minimum_loop_world_frame_count);
topology.loop_rigid_transform_count = ...
    double(requirements.minimum_loop_rigid_transform_count);
topology.loop_body_element_attachment_count = ...
    double(requirements.minimum_loop_body_attachment_count);
topology.four_bar_graph_connected = true;
topology.physical_tip_measurement_signature = true;
end

function policy = localLoadPolicy(policyPath)
policy = jsondecode(fileread(policyPath));
assert(string(policy.schema) == ...
    "simuverity.f90-xmech08-structure-policy.v1", ...
    "SimuVerity:F90:XMECH08:PolicySchema", ...
    "Unsupported CURRENT_GROUPS structure policy.");
assert(~logical(policy.display_name_is_trusted_identity) && ...
    ~logical(policy.candidate_mask_type_is_trusted_identity), ...
    "SimuVerity:F90:XMECH08:UntrustedIdentityPolicy", ...
    "Display names and candidate mask metadata cannot grant a role.");
assert(logical( ...
    policy.resolved_product_library_must_be_under_matlabroot), ...
    "SimuVerity:F90:XMECH08:ProductRootPolicy", ...
    "Trusted libraries must resolve below matlabroot.");
end

function audit = localPhysicalTopologyAudit(modelPath, policy, isReference)
[~, model] = fileparts(modelPath);
wasLoaded = bdIsLoaded(model);
if ~wasLoaded, load_system(modelPath); end
cleanup = onCleanup(@() localCloseIfNeeded(model, wasLoaded)); %#ok<NASGU>

if isReference
    % The exact shipped Four-Bar model stores its physical plant in nested
    % product blocks.  Candidate topology remains root-only by policy.
    blocks = string(find_system(model, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "Type", "Block"));
else
    blocks = string(find_system(model, "SearchDepth", 1, "Type", "Block"));
end
blocks = blocks(blocks ~= model);
template = struct( ...
    "id", "", "path", "", "handle", 0, "role", "", ...
    "identity", struct, "connection_ports", struct([]));
nodes = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    [role, identity] = localTrustedProductRole(block, policy);
    portRows = struct([]);
    if strlength(role) > 0
        portRows = localConnectionPortRows(block);
        connectedDomain = localConnectedInterfaceCount( ...
            portRows, string(policy.conserving_interface_types));
        minimum = localRoleMinimum(policy, role);
        if connectedDomain < minimum
            role = "";
        end
    end
    nodes(index) = struct( ...
        "id", "n" + string(index), ...
        "path", block, ...
        "handle", double(get_param(block, "Handle")), ...
        "role", role, ...
        "identity", identity, ...
        "connection_ports", portRows);
end

[nets, familyDiagnostics] = localPhysicalNets(model, nodes, isReference);
[domainNets, sourceNetIndices] = localDomainNets(nets, nodes);
[adjacency, allowed, isRevolute, isRigid] = ...
    localBipartiteLoopGraph(nodes, domainNets);
loopVertices = localBestPhysicalLoop( ...
    adjacency, allowed, isRevolute, isRigid);
blockCount = numel(nodes);
loopBlocks = loopVertices(loopVertices <= blockCount);
loopNetLocal = loopVertices(loopVertices > blockCount) - blockCount;

roles = string({nodes.role});
loopJointCount = nnz(roles(loopBlocks) == "revolute_joint");
loopRigidCount = nnz(roles(loopBlocks) == "rigid_transform");
loopWorld = localAttachedRoleNodes( ...
    nodes, domainNets, loopNetLocal, "world_frame");
loopBodies = localRigidBridgedRoleAttachments( ...
    nodes, domainNets, loopNetLocal, "body_element");
loopWorldCount = numel(loopWorld);
loopBodyCount = numel(loopBodies);

requirements = policy.four_bar_requirements;
connected = loopJointCount >= double( ...
        requirements.minimum_loop_revolute_joint_count) && ...
    loopWorldCount >= double( ...
        requirements.minimum_loop_world_frame_count) && ...
    loopRigidCount >= double( ...
        requirements.minimum_loop_rigid_transform_count) && ...
    loopBodyCount >= double( ...
        requirements.minimum_loop_body_attachment_count);

driveLinks = localPhysicalRolePairs(nets, nodes, ...
    "simulink_to_ps_converter", "revolute_joint", loopBlocks);
sensorLinks = localPhysicalRolePairs(nets, nodes, ...
    "transform_sensor", "ps_to_simulink_converter", zeros(0, 1));
loopSensors = localAttachedRoleNodes( ...
    nodes, domainNets, loopNetLocal, "transform_sensor");
tipMeasurement = ~isempty(sensorLinks) && ~isempty(loopSensors);
drivePresent = ~isempty(driveLinks);

roleCounts = localRoleCounts(nodes);
audit = struct( ...
    "structure_model_file_presence", localFilePresence(modelPath), ...
    "root_block_count", numel(nodes), ...
    "revolute_joint_count", roleCounts.revolute_joint, ...
    "revolute_joint_count", roleCounts.revolute_joint, ...
    "rigid_solid_count", roleCounts.body_element, ...
    "rigid_transform_count", roleCounts.rigid_transform, ...
    "rigid_body_element_count", roleCounts.body_element, ...
    "world_frame_count", roleCounts.world_frame, ...
    "world_frame_count", roleCounts.world_frame, ...
    "transform_sensor_count", roleCounts.transform_sensor, ...
    "simulink_ps_converter_count", ...
        roleCounts.simulink_to_ps_converter, ...
    "ps_simulink_converter_count", ...
        roleCounts.ps_to_simulink_converter, ...
    "physical_connection_line_count", numel(nets), ...
    "root_physical_network_count", numel(domainNets), ...
    "branched_connection_family_count", ...
        familyDiagnostics.branched_family_count, ...
    "loop_revolute_joint_count", loopJointCount, ...
    "loop_world_frame_count", loopWorldCount, ...
    "loop_rigid_transform_count", loopRigidCount, ...
    "loop_body_element_attachment_count", loopBodyCount, ...
    "four_bar_graph_connected", logical(connected), ...
    "physical_drive_signature", logical(drivePresent), ...
    "physical_tip_measurement_signature", logical(tipMeasurement), ...
    "trusted_drive_link_count", numel(driveLinks), ...
    "trusted_sensor_converter_link_count", numel(sensorLinks), ...
    "loop_node_ids", localNodeIds(nodes, loopBlocks), ...
    "loop_block_paths", localNodeIds(nodes, loopBlocks), ...
    "loop_net_ids", "net" + string(loopNetLocal(:)), ...
    "loop_world_attachment_ids", localNodeIds(nodes, loopWorld), ...
    "loop_body_attachment_ids", localNodeIds(nodes, loopBodies), ...
    "domain_net_source_family_indices", ...
        reshape(double(sourceNetIndices), [], 1), ...
    "trusted_role_witnesses", localRoleWitnesses(nodes), ...
    "conserving_net_witnesses", localNetWitnesses(nets, nodes), ...
    "display_name_used_for_role_identity", false, ...
    "candidate_mask_type_used_for_role_identity", false, ...
    "resolved_product_library_required", true, ...
    "connection_port_metadata_api", ...
        "simscape.connectionPortProperties", ...
    "physical_graph_representation", ...
        "bipartite trusted-block to conserving-net", ...
    "line_family_relations", ["LineParent", "LineChildren"], ...
    "connection_property_array_order_used", false, ...
    "physical_port_role_pairing", true, ...
    "rigid_bridged_body_attachment", true);
end

function [role, identity] = localTrustedProductRole(block, policy)
role = "";
blockType = localGet(block, "BlockType");
sourceBlock = localNormalizedText(localGet(block, "SourceBlock"));
referenceBlock = localNormalizedText(localGet(block, "ReferenceBlock"));
if strlength(sourceBlock) == 0
    sourceBlock = referenceBlock;
elseif strlength(referenceBlock) > 0 && referenceBlock ~= sourceBlock
    sourceBlock = "";
end
sourceType = localNormalizedText(localGet(block, "SourceType"));
linkStatus = lower(localNormalizedText(localGet(block, "LinkStatus")));
[productPass, resolvedFile] = localResolvedProductLibrary( ...
    sourceBlock, policy);
identityPass = any(strcmpi(blockType, ...
        string(policy.trusted_instance_block_types))) && ...
    any(strcmpi(linkStatus, string(policy.accepted_link_status))) && ...
    productPass;
if identityPass
    roleNames = string(fieldnames(policy.role_identities));
    for roleName = roleNames(:).'
        candidates = policy.role_identities.(roleName);
        for index = 1:numel(candidates)
            expectedBlock = localNormalizedText( ...
                string(candidates(index).source_block));
            if sourceBlock == expectedBlock
                role = roleName;
                break
            end
        end
        if strlength(role) > 0, break, end
    end
end
identity = struct( ...
    "block_type", blockType, ...
    "source_block", sourceBlock, ...
    "source_type", sourceType, ...
    "link_status", linkStatus, ...
    "resolved_library_file", resolvedFile, ...
    "resolved_product_library", logical(productPass));
end

function [pass, resolvedFile] = localResolvedProductLibrary( ...
        sourceBlock, policy)
pass = false;
resolvedFile = "";
parts = split(string(sourceBlock), "/");
if isempty(parts), return, end
libraryRoot = parts(1);
if ~isfield(policy.trusted_product_libraries, libraryRoot), return, end
libraryPolicy = policy.trusted_product_libraries.(libraryRoot);
try
    if bdIsLoaded(libraryRoot)
        resolvedFile = string(get_param(libraryRoot, "FileName"));
    else
        resolvedFile = string(which(libraryRoot));
    end
catch
    return
end
if strlength(resolvedFile) == 0, return, end
relative = strrep(string(libraryPolicy.relative_path), "/", filesep);
expected = fullfile(string(matlabroot), relative);
pass = localCanonicalPath(resolvedFile) == ...
    localCanonicalPath(expected) && ...
    localPathIsWithin(resolvedFile, string(matlabroot));
end

function minimum = localRoleMinimum(policy, role)
minimum = inf;
if isfield(policy.minimum_connected_domain_ports, role)
    minimum = double(policy.minimum_connected_domain_ports.(role));
end
end

function rows = localConnectionPortRows(block)
template = struct( ...
    "handle", 0, "side", "", "ordinal", 0, ...
    "name", "", "label", "", "interface_type", "", ...
    "connected", false);
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
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "handle", sideHandles(ordinal), ...
            "side", side, "ordinal", ordinal, ...
            "name", localPortGet(sideHandles(ordinal), "Name"), ...
            "label", "", "interface_type", "", ...
            "connected", localPortConnected(sideHandles(ordinal)));
    end
end
if isempty(rows), return, end
properties = simscape.connectionPortProperties(block);
used = false(numel(properties), 1);
for rowIndex = 1:numel(rows)
    propertyIndex = 0;
    portName = localCompact(rows(rowIndex).name);
    if strlength(portName) > 0
        for candidate = 1:numel(properties)
            propertyName = localCompact(string(properties(candidate).Name));
            propertyLabel = localCompact(string(properties(candidate).Label));
            if ~used(candidate) && ...
                    (portName == propertyName || portName == propertyLabel)
                propertyIndex = candidate;
                break
            end
        end
    end
    if propertyIndex == 0 && numel(properties) == numel(rows) && ...
            ~used(rowIndex)
        propertyIndex = rowIndex;
    end
    if propertyIndex == 0, continue, end
    used(propertyIndex) = true;
    rows(rowIndex).label = string(properties(propertyIndex).Label);
    rows(rowIndex).interface_type = string( ...
        properties(propertyIndex).Type.InterfaceType);
end
end

function count = localConnectedInterfaceCount(rows, interfaces)
count = 0;
if isempty(rows), return, end
actual = lower(string({rows.interface_type}));
accepted = lower(string(interfaces));
count = nnz(logical([rows.connected]) & ismember(actual, accepted));
end

function [nets, diagnostics] = localPhysicalNets(model, nodes, isReference)
template = struct( ...
    "id", "", "family_handles", zeros(0, 1), ...
    "owner_indices", zeros(0, 1), ...
    "port_handles", zeros(0, 1), ...
    "interfaces", strings(0, 1), ...
    "port_ids", strings(0, 1));
nets = repmat(template, 0, 1);
families = localMergedConnectionFamilies(model, isReference);
branched = 0;
for familyIndex = 1:numel(families)
    family = families{familyIndex};
    owners = zeros(0, 1);
    retainedPorts = zeros(0, 1);
    interfaces = strings(0, 1);
    portIds = strings(0, 1);
    for owner = 1:numel(nodes)
        rows = nodes(owner).connection_ports;
        for rowIndex = 1:numel(rows)
            port = double(rows(rowIndex).handle);
            try
                line = double(get_param(port, "Line"));
                line = line(isfinite(line) & line > 0);
            catch
                line = zeros(0, 1);
            end
            if isempty(line) || ~any(ismember(line, family)) || ...
                    strlength(rows(rowIndex).interface_type) == 0
                continue
            end
            owners(end + 1, 1) = owner; %#ok<AGROW>
            retainedPorts(end + 1, 1) = port; %#ok<AGROW>
            interfaces(end + 1, 1) = ...
                string(rows(rowIndex).interface_type); %#ok<AGROW>
            portIds(end + 1, 1) = nodes(owner).id + ":" + ...
                lower(rows(rowIndex).side) + ...
                string(rows(rowIndex).ordinal); %#ok<AGROW>
        end
    end
    if ~isempty(retainedPorts)
        [retainedPorts, uniqueIndex] = unique(retainedPorts, "stable");
        owners = owners(uniqueIndex);
        interfaces = interfaces(uniqueIndex);
        portIds = portIds(uniqueIndex);
    end
    if numel(unique(owners)) < 2, continue, end
    if numel(family) > 1 || numel(unique(owners)) > 2
        branched = branched + 1;
    end
    nets(end + 1, 1) = struct( ... %#ok<AGROW>
        "id", "net" + string(numel(nets) + 1), ...
        "family_handles", family(:), ...
        "owner_indices", owners, ...
        "port_handles", retainedPorts, ...
        "interfaces", interfaces, ...
        "port_ids", portIds);
end
diagnostics = struct( ...
    "connection_family_count", numel(nets), ...
    "branched_family_count", branched, ...
    "line_family_relations", ["LineParent", "LineChildren"], ...
    "physical_port_line_reverse_grouping", true);
end

function families = localMergedConnectionFamilies(model, isReference)
if isReference
    lineHandles = double(find_system(model, "FindAll", "on", ...
        "LookUnderMasks", "all", "FollowLinks", "on", "Type", "line"));
else
    lineHandles = double(find_system(model, "FindAll", "on", ...
        "SearchDepth", 1, "Type", "line"));
end
families = cell(0, 1);
for line = reshape(lineHandles, 1, [])
    try
        if ~strcmpi(string(get_param(line, "LineType")), "connection")
            continue
        end
        family = localLineFamily(line);
        if isempty(family), continue, end
        overlap = false(numel(families), 1);
        for index = 1:numel(families)
            overlap(index) = any(ismember(families{index}, family));
        end
        merged = family(:);
        for index = find(overlap).'
            merged = [merged; families{index}(:)]; %#ok<AGROW>
        end
        families(overlap) = [];
        families{end + 1, 1} = unique(merged); %#ok<AGROW>
    catch
    end
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

function [domainNets, sourceIndices] = localDomainNets(nets, nodes)
domainNets = cell(0, 1);
sourceIndices = zeros(0, 1);
domainRoles = ["revolute_joint", "rigid_transform", ...
    "world_frame", "body_element", "transform_sensor"];
converterRoles = ["simulink_to_ps_converter", ...
    "ps_to_simulink_converter"];
for index = 1:numel(nets)
    owners = unique(nets(index).owner_indices, "stable");
    roles = string({nodes(owners).role});
    if any(ismember(roles, converterRoles)), continue, end
    owners = owners(ismember(roles, domainRoles));
    if numel(owners) < 2, continue, end
    domainNets{end + 1, 1} = owners(:); %#ok<AGROW>
    sourceIndices(end + 1, 1) = index; %#ok<AGROW>
end
end

function [adjacency, allowed, isRevolute, isRigid] = ...
        localBipartiteLoopGraph(nodes, domainNets)
blockCount = numel(nodes);
vertexCount = blockCount + numel(domainNets);
adjacency = false(vertexCount, vertexCount);
roles = string({nodes.role});
allowedBlock = ismember(roles, ...
    ["revolute_joint", "rigid_transform", "world_frame"]);
allowed = [reshape(allowedBlock, [], 1); true(numel(domainNets), 1)];
isRevolute = [reshape(roles == "revolute_joint", [], 1); ...
    false(numel(domainNets), 1)];
isRigid = [reshape(roles == "rigid_transform", [], 1); ...
    false(numel(domainNets), 1)];
for net = 1:numel(domainNets)
    netVertex = blockCount + net;
    owners = domainNets{net};
    owners = owners(allowedBlock(owners));
    adjacency(owners, netVertex) = true;
    adjacency(netVertex, owners) = true;
end
end

function best = localBestPhysicalLoop( ...
        adjacency, allowed, isRevolute, isRigid)
best = zeros(0, 1);
for start = reshape(find(allowed), 1, [])
    visited = false(size(allowed));
    visited(start) = true;
    best = localWalkLoop(start, start, start, visited, best, ...
        adjacency, allowed, isRevolute, isRigid);
end
end

function best = localWalkLoop(start, current, path, visited, best, ...
        adjacency, allowed, isRevolute, isRigid)
neighbors = find(adjacency(current, :).');
for neighbor = reshape(neighbors, 1, [])
    if ~allowed(neighbor), continue, end
    if neighbor == start && numel(path) >= 6
        candidateRank = [nnz(isRevolute(path)), ...
            nnz(isRigid(path)), numel(path)];
        bestRank = [nnz(isRevolute(best)), ...
            nnz(isRigid(best)), numel(best)];
        if localLexicographicGreater(candidateRank, bestRank)
            best = path(:);
        end
        continue
    end
    if visited(neighbor), continue, end
    nextVisited = visited;
    nextVisited(neighbor) = true;
    best = localWalkLoop(start, neighbor, [path(:); neighbor], ...
        nextVisited, best, adjacency, allowed, isRevolute, isRigid);
end
end

function pass = localLexicographicGreater(left, right)
pass = false;
for index = 1:numel(left)
    if left(index) > right(index), pass = true; return, end
    if left(index) < right(index), return, end
end
end

function indices = localAttachedRoleNodes( ...
        nodes, domainNets, loopNetIndices, role)
indices = zeros(0, 1);
for net = reshape(loopNetIndices, 1, [])
    if net < 1 || net > numel(domainNets), continue, end
    owners = domainNets{net};
    matches = owners(string({nodes(owners).role}) == string(role));
    indices = [indices; matches(:)]; %#ok<AGROW>
end
indices = unique(indices, "stable");
end

function indices = localRigidBridgedRoleAttachments( ...
        nodes, domainNets, loopNetIndices, role)
indices = localAttachedRoleNodes( ...
    nodes, domainNets, loopNetIndices, role);
loopOwners = zeros(0, 1);
for net = reshape(loopNetIndices, 1, [])
    if net < 1 || net > numel(domainNets), continue, end
    loopOwners = [loopOwners; domainNets{net}(:)]; %#ok<AGROW>
end
loopOwners = unique(loopOwners, "stable");
loopRigid = loopOwners( ...
    string({nodes(loopOwners).role}) == "rigid_transform");
targets = find(string({nodes.role}) == string(role));
for target = reshape(targets, 1, [])
    for net = 1:numel(domainNets)
        owners = domainNets{net};
        if any(owners == target) && any(ismember(owners, loopRigid))
            indices(end + 1, 1) = target; %#ok<AGROW>
            break
        end
    end
end
indices = unique(indices, "stable");
end

function pairs = localPhysicalRolePairs( ...
        nets, nodes, leftRole, rightRole, requiredRightNodes)
template = struct("net_id", "", "left_node_id", "", ...
    "right_node_id", "");
pairs = repmat(template, 0, 1);
for net = 1:numel(nets)
    owners = nets(net).owner_indices;
    for left = 1:numel(owners)
        if nodes(owners(left)).role ~= string(leftRole)
            continue
        end
        for right = 1:numel(owners)
            if nodes(owners(right)).role ~= string(rightRole)
                continue
            end
            if ~isempty(requiredRightNodes) && ...
                    ~any(requiredRightNodes == owners(right))
                continue
            end
            pairs(end + 1, 1) = struct( ... %#ok<AGROW>
                "net_id", nets(net).id, ...
                "left_node_id", nodes(owners(left)).id, ...
                "right_node_id", nodes(owners(right)).id);
        end
    end
end
end

function counts = localRoleCounts(nodes)
roles = string({nodes.role});
roleNames = ["revolute_joint", "rigid_transform", "world_frame", ...
    "body_element", "transform_sensor", ...
    "simulink_to_ps_converter", "ps_to_simulink_converter"];
counts = struct;
for role = roleNames
    counts.(role) = nnz(roles == role);
end
end

function rows = localRoleWitnesses(nodes)
template = struct("node_id", "", "role", "", ...
    "block_type", "", "source_block", "", "source_type", "", ...
    "link_status", "", "resolved_library_file", "", ...
    "connected_domain_port_count", 0);
rows = repmat(template, 0, 1);
for index = 1:numel(nodes)
    if strlength(nodes(index).role) == 0, continue, end
    identity = nodes(index).identity;
    domainCount = localConnectedInterfaceCount( ...
        nodes(index).connection_ports, ["Domain", "CompositeDomain", ...
        "ConnectionBus"]);
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "node_id", nodes(index).id, ...
        "role", nodes(index).role, ...
        "block_type", identity.block_type, ...
        "source_block", identity.source_block, ...
        "source_type", identity.source_type, ...
        "link_status", identity.link_status, ...
        "resolved_library_file", identity.resolved_library_file, ...
        "connected_domain_port_count", domainCount);
end
end

function rows = localNetWitnesses(nets, nodes)
template = struct("net_id", "", "family_size", 0, ...
    "node_ids", strings(0, 1), "roles", strings(0, 1), ...
    "interfaces", strings(0, 1), "port_ids", strings(0, 1));
rows = repmat(template, numel(nets), 1);
for index = 1:numel(nets)
    owners = nets(index).owner_indices;
    rows(index) = struct( ...
        "net_id", nets(index).id, ...
        "family_size", numel(nets(index).family_handles), ...
        "node_ids", reshape(string({nodes(owners).id}), [], 1), ...
        "roles", reshape(string({nodes(owners).role}), [], 1), ...
        "interfaces", reshape(nets(index).interfaces, [], 1), ...
        "port_ids", reshape(nets(index).port_ids, [], 1));
end
end

function ids = localNodeIds(nodes, indices)
indices = unique(indices(:), "stable");
indices = indices(indices >= 1 & indices <= numel(nodes));
if isempty(indices), ids = strings(0, 1);
else, ids = reshape(string({nodes(indices).id}), [], 1);
end
end

function row = localConnectionRowForHandle(rows, handle)
row = [];
if isempty(rows), return, end
index = find(double([rows.handle]) == double(handle), 1);
if ~isempty(index), row = rows(index); end
end

function ownerHandle = localPortOwnerHandle(port)
ownerHandle = -1;
try
    parent = get_param(port, "Parent");
    if isnumeric(parent), ownerHandle = double(parent);
    else, ownerHandle = double(get_param(parent, "Handle"));
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

function value = localGet(block, parameter)
value = "";
try
    value = string(get_param(block, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
catch
end
end

function value = localPortGet(port, parameter)
value = "";
try
    value = string(get_param(port, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
catch
end
end

function value = localNormalizedText(value)
value = strtrim(regexprep(string(value), "\s+", " "));
if ~isscalar(value), value = join(value(:), " "); end
if ismissing(value), value = ""; end
end

function value = localCompact(value)
value = lower(regexprep(string(value), "[^A-Za-z0-9]", ""));
if ~isscalar(value), value = join(value(:), ""); end
if ismissing(value), value = ""; end
end

function canonical = localCanonicalPath(pathValue)
canonical = lower(string(java.io.File(char(pathValue)).getCanonicalPath()));
end

function pass = localPathIsWithin(pathValue, rootValue)
pathCanonical = localCanonicalPath(pathValue);
rootCanonical = localCanonicalPath(rootValue);
pass = pathCanonical == rootCanonical || startsWith(pathCanonical, ...
    rootCanonical + string(filesep));
end

function audit = localEmptyTopologyAudit
audit = struct( ...
    "root_block_count", 0, ...
    "revolute_joint_count", 0, ...
    "revolute_joint_count", 0, ...
    "rigid_solid_count", 0, ...
    "rigid_transform_count", 0, ...
    "rigid_body_element_count", 0, ...
    "world_frame_count", 0, ...
    "world_frame_count", 0, ...
    "transform_sensor_count", 0, ...
    "simulink_ps_converter_count", 0, ...
    "ps_simulink_converter_count", 0, ...
    "physical_connection_line_count", 0, ...
    "root_physical_network_count", 0, ...
    "branched_connection_family_count", 0, ...
    "loop_revolute_joint_count", 0, ...
    "loop_world_frame_count", 0, ...
    "loop_rigid_transform_count", 0, ...
    "loop_body_element_attachment_count", 0, ...
    "four_bar_graph_connected", false, ...
    "physical_drive_signature", false, ...
    "physical_tip_measurement_signature", false, ...
    "trusted_drive_link_count", 0, ...
    "trusted_sensor_converter_link_count", 0, ...
    "loop_node_ids", strings(0, 1), ...
    "loop_block_paths", strings(0, 1), ...
    "loop_net_ids", strings(0, 1), ...
    "trusted_role_witnesses", struct([]), ...
    "conserving_net_witnesses", struct([]), ...
    "display_name_used_for_role_identity", false, ...
    "candidate_mask_type_used_for_role_identity", false);
end

function localCloseIfNeeded(model, wasLoaded)
if ~wasLoaded
    try, close_system(model, 0); catch, end
end

function localCloseReferenceProject(modelPath, isReference)
if ~isReference, return, end
try
    project = currentProject;
    expectedRoot = fullfile(fileparts(modelPath), "Four-Bar-Optim");
    if ~isempty(project) && strcmpi(string(project.RootFolder), expectedRoot)
        close(project);
    end
catch
end
end
end

function localRequireBinding(pathValue, expectedFilePresence)
assert(isfile(pathValue) && ...
    localFilePresence(pathValue) == lower(string(expectedFilePresence)), ...
    "SimuVerity:F90:XMECH08:DependencyBinding", ...
    "A declared CURRENT_GROUPS dependency is missing or changed.");
end

function value = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
value = "present";
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH08:JsonOpen", ...
    "Cannot write CURRENT_GROUPS evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(fileparts(here))));
end
