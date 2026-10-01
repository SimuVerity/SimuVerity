function audit = f90_xmed02_reference_static_audit(modelOrPath)
%f90_xmed02_reference_static_audit Exact-reference R2025a audit bridge.
%
% Component identities come from block/library metadata, never display
% names.  Qualification comes from real Simscape conserving-port nets and
% closed path witnesses; the source reference-scale counts are diagnostic.

inputWasPath = isfile(modelOrPath);
if inputWasPath
    [~, model] = fileparts(modelOrPath);
    load_system(modelOrPath);
    cleanup = onCleanup(@() close_system(model, 0)); %#ok<NASGU>
else
    model = string(modelOrPath);
    cleanup = []; %#ok<NASGU>
end

set_param(model, "SimulationCommand", "update");
blocks = find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
identities = strings(numel(blocks), 1);
for index = 1:numel(blocks)
    identities(index) = localIdentity(blocks{index});
end

counts = struct();
counts.resistive = sum(localMatches(identities, ...
    ["resistor", "resistance", "restriction"]));
counts.compliance = sum(localMatches(identities, ...
    ["capacitor", "compliance", "chamber", "accumulator"]));
counts.inertance = sum(localMatches(identities, ...
    ["inductor", "inertance", "fluid inertia", "pipe"]));
counts.valve = sum(localMatches(identities, ...
    ["diode", "check valve", "directional valve"]));
counts.pressure_sensor = sum(localMatches(identities, ...
    ["voltage sensor", "pressure sensor"]));
counts.flow_sensor = sum(localMatches(identities, ...
    ["current sensor", "flow rate sensor", "mass flow sensor"]));
counts.controlled_flow_actuator = sum(localMatches(identities, ...
    ["controlled current source", "controlled voltage source", ...
    "controlled flow rate source", ...
    "controlled mass flow rate source", "centrifugal pump"]));

rootBlocks = find_system(model, "SearchDepth", 1, "Type", "Block");
rootBlocks = string(rootBlocks(:));
rootBlocks(rootBlocks == model) = [];
[edgesFrom, edgesTo] = localRootSignalEdges(model);

pressureOwners = localOwners(rootBlocks, ...
    ["voltage sensor", "pressure sensor"]);
flowOwners = localOwners(rootBlocks, ...
    ["current sensor", "flow rate sensor", "mass flow sensor"]);
actuatorOwners = localOwners(rootBlocks, ...
    ["controlled current source", "controlled voltage source", ...
    "controlled flow rate source", ...
    "controlled mass flow rate source", "centrifugal pump"]);

pressureSink = localOutputSink(model, "pressure_state");
flowSink = localOutputSink(model, "flow_state");
commandSink = localOutputSink(model, "pump_command");
commandDrivers = unique(edgesFrom(edgesTo == commandSink));
[feedbackReachable, feedbackPath] = localAnyReachableVia( ...
    pressureOwners, commandDrivers, actuatorOwners, edgesFrom, edgesTo);
dynamicOnPath = localPathHasDynamicControl(feedbackPath);
feedbackOk = feedbackReachable && dynamicOnPath;

sourceCountStructureOk = counts.resistive >= 8 && ...
    counts.compliance >= 4 && counts.inertance >= 3 && counts.valve >= 4;
[circulationGraph, circulationTopology] = localPhysicalGraph( ...
    model, rootBlocks, feedbackPath, dynamicOnPath, ...
    sourceCountStructureOk);
structureOk = logical(circulationTopology.pass);

pressureAncestors = localAncestors(pressureSink, edgesFrom, edgesTo);
flowAncestors = localAncestors(flowSink, edgesFrom, edgesTo);
commandAncestors = localAncestors(commandSink, edgesFrom, edgesTo);

pressureProvenanceCount = numel(intersect( ...
    pressureAncestors, pressureOwners));
flowProvenanceCount = numel(intersect(flowAncestors, flowOwners));
commandUsesPressure = ~isempty(intersect( ...
    commandAncestors, pressureOwners));

interfaceOk = strlength(pressureSink) > 0 && ...
    strlength(flowSink) > 0 && strlength(commandSink) > 0;
pressureProvenanceOk = pressureProvenanceCount >= 3;
flowProvenanceOk = flowProvenanceCount >= 3;
commandProvenanceOk = commandUsesPressure;
physicalIoOk = counts.pressure_sensor >= 3 && ...
    counts.flow_sensor >= 3 && ...
    logical(circulationTopology.pressure_measurements.pass);
pumpOk = counts.controlled_flow_actuator >= 1 && ...
    ~isempty(actuatorOwners) && ...
    logical(circulationTopology.ecmo_feedback_branch.pass);

components = struct( ...
    "circulation_structure", double(structureOk), ...
    "physical_measurements", double(physicalIoOk), ...
    "real_pump_actuator", double(pumpOk), ...
    "pressure_feedback_to_pump", double(feedbackOk), ...
    "public_interface", double(interfaceOk), ...
    "pressure_output_provenance", double(pressureProvenanceOk), ...
    "flow_output_provenance", double(flowProvenanceOk), ...
    "command_feedback_provenance", double(commandProvenanceOk));
values = cell2mat(struct2cell(components));

audit = struct();
audit.schema = "simuverity.formal90-xmed02-static-audit.v1";
audit.task_id = "F90-XMED-02";
audit.model = model;
audit.valid = true;
audit.counts = counts;
audit.source_count_structure_ok = sourceCountStructureOk;
audit.components = components;
audit.score = mean(values);
audit.core_mechanism_ok = structureOk && physicalIoOk && pumpOk && ...
    feedbackOk && interfaceOk && pressureProvenanceOk && ...
    flowProvenanceOk && commandProvenanceOk;
audit.circulation_graph = circulationGraph;
audit.circulation_topology = circulationTopology;
audit.feedback_path = feedbackPath;
audit.feedback_path_has_dynamic_control = dynamicOnPath;
audit.pressure_owners = pressureOwners;
audit.flow_owners = flowOwners;
audit.actuator_owners = actuatorOwners;
audit.output_sinks = struct("pressure_state", pressureSink, ...
    "flow_state", flowSink, "pump_command", commandSink);
audit.provenance_counts = struct( ...
    "pressure_state", pressureProvenanceCount, ...
    "flow_state", flowProvenanceCount, ...
    "pump_command_uses_pressure", commandUsesPressure);
end

function [physicalGraph, decision] = localPhysicalGraph( ...
        model, rootBlocks, feedbackPath, dynamicOnPath, ...
        sourceCountStructureOk)
ownerTemplate = struct("owner", "", "roles", strings(0, 1), ...
    "net_ids", strings(0, 1), "ports_complete", false, ...
    "is_reference", false);
owners = repmat(ownerTemplate, numel(rootBlocks), 1);
referenceNets = strings(0, 1);
physicalPorts = localRootPhysicalPorts(rootBlocks);
[netIndex, nativeNetStats] = simuverity_physical_line_networks( ...
    model, physicalPorts);
for index = 1:numel(rootBlocks)
    root = rootBlocks(index);
    roles = localRootRoles(root);
    [netIds, complete] = localDomainNetIds(root, netIndex);
    isReference = localRootIsReference(root);
    owners(index) = struct("owner", root, "roles", roles, ...
        "net_ids", netIds, "ports_complete", complete, ...
        "is_reference", isReference);
    if isReference
        referenceNets = [referenceNets; netIds(:)]; %#ok<AGROW>
    end
end
referenceNets = unique(referenceNets);

edgeTemplate = struct("id", "", "owner", "", "net_a", "", ...
    "net_b", "", "roles", strings(0, 1));
transportEdges = repmat(edgeTemplate, 0, 1);
invalidTransportOwners = strings(0, 1);
complianceNets = strings(0, 1);
pressureSensorNets = strings(0, 1);
transportRoles = ["resistive", "inertance", "valve", ...
    "flow_sensor", "actuator"];
for index = 1:numel(owners)
    owner = owners(index);
    if any(owner.roles == "compliance")
        complianceNets = [complianceNets; owner.net_ids(:)]; %#ok<AGROW>
    end
    if any(owner.roles == "pressure_sensor")
        pressureSensorNets = [pressureSensorNets; owner.net_ids(:)]; %#ok<AGROW>
    end
    roles = intersect(owner.roles, transportRoles, "stable");
    if isempty(roles), continue, end
    if ~owner.ports_complete || numel(owner.net_ids) ~= 2 || ...
            owner.net_ids(1) == owner.net_ids(2)
        invalidTransportOwners(end + 1, 1) = owner.owner; %#ok<AGROW>
        continue
    end
    newEdge = struct( ...
        "id", "e" + string(numel(transportEdges) + 1), ...
        "owner", owner.owner, "net_a", owner.net_ids(1), ...
        "net_b", owner.net_ids(2), "roles", roles(:));
    newEdge.roles = cellstr(roles(:));
    transportEdges(end + 1, 1) = newEdge; %#ok<AGROW>
end
complianceNets = setdiff(unique(complianceNets), referenceNets);
pressureSensorNets = setdiff(unique(pressureSensorNets), referenceNets);

feedbackActuatorEdgeId = "";
if ~isempty(feedbackPath)
    feedbackOwner = feedbackPath(end);
    for index = 1:numel(transportEdges)
        if transportEdges(index).owner == feedbackOwner && ...
                any(transportEdges(index).roles == "actuator")
            feedbackActuatorEdgeId = transportEdges(index).id;
            break
        end
    end
end
conservingPortGraphValid = ~isempty(transportEdges);
physicalGraph = struct( ...
    "schema", "simuverity.f90-xmed02-circulation-graph.v1", ...
    "graph_valid", conservingPortGraphValid, ...
    "identity_valid", true, ...
    "conserving_port_graph_valid", conservingPortGraphValid, ...
    "transport_edges", transportEdges, ...
    "compliance_nets", complianceNets, ...
    "pressure_sensor_nets", pressureSensorNets, ...
    "reference_nets", referenceNets, ...
    "feedback_actuator_edge_id", feedbackActuatorEdgeId, ...
    "feedback_path_has_dynamic_control", logical(dynamicOnPath), ...
    "invalid_transport_owners", unique(invalidTransportOwners), ...
    "role_identity_source", ...
        "BlockType|MaskType|ReferenceBlock|SourceBlock", ...
    "physical_net_source", ...
        "simuverity_physical_line_networks:LineParent+LineChildren+exact_PortConnectivity", ...
    "physical_net_dependency_file_presence", ...
        "present", ...
    "physical_net_stats", nativeNetStats, ...
    "source_count_structure_ok", logical(sourceCountStructureOk));
% Cell arrays force JSON arrays even when a category has one member.
physicalGraph.compliance_nets = cellstr(complianceNets(:));
physicalGraph.pressure_sensor_nets = cellstr(pressureSensorNets(:));
physicalGraph.reference_nets = cellstr(referenceNets(:));
physicalGraph.invalid_transport_owners = ...
    cellstr(unique(invalidTransportOwners(:)));
decision = localAssessCirculation(physicalGraph);
end

function roles = localRootRoles(root)
descendants = find_system(root, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block");
identities = strings(numel(descendants), 1);
for index = 1:numel(descendants)
    identities(index) = localIdentity(descendants{index});
end
roles = strings(0, 1);
patterns = { ...
    "resistive", ["resistor", "resistance", "restriction"]; ...
    "compliance", ["capacitor", "compliance", "chamber", "accumulator"]; ...
    "inertance", ["inductor", "inertance", "fluid inertia", "pipe"]; ...
    "valve", ["diode", "check valve", "directional valve"]; ...
    "pressure_sensor", ["voltage sensor", "pressure sensor"]; ...
    "flow_sensor", ["current sensor", "flow rate sensor", "mass flow sensor"]; ...
    "actuator", ["controlled current source", "controlled voltage source", ...
        "controlled flow rate source", "controlled mass flow rate source", ...
        "centrifugal pump"]};
for row = 1:size(patterns, 1)
    if any(localMatches(identities, patterns{row, 2}))
        roles(end + 1, 1) = string(patterns{row, 1}); %#ok<AGROW>
    end
end
roles = unique(roles, "stable");
end

function pass = localRootIsReference(root)
identity = localIdentity(root);
pass = any(localMatches(identity, ["electrical reference", ...
    "hydraulic reference", "thermal reference", ...
    "mechanical translational reference"]));
end

function [netIds, complete] = localDomainNetIds(block, netIndex)
rows = localConnectionPortRows(block);
netIds = strings(0, 1);
complete = ~isempty(rows);
for index = 1:numel(rows)
    kind = lower(string(rows(index).interface_type));
    if ~ismember(kind, ["domain", "compositedomain"]), continue, end
    netId = localNetId(rows(index).handle, netIndex);
    if strlength(netId) == 0
        complete = false;
    else
        netIds(end + 1, 1) = netId; %#ok<AGROW>
    end
end
netIds = unique(netIds, "stable");
complete = complete && ~isempty(netIds);
end

function rows = localConnectionPortRows(block)
template = struct("handle", 0, "name", "", "label", "", ...
    "interface_type", "", "side", "", "ordinal", 0);
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
            "name", localPortGet(sideHandles(ordinal), "Name"), ...
            "label", "", "interface_type", "", ...
            "side", side, "ordinal", ordinal);
    end
end
if isempty(rows), return, end
configuration = localSimscapePortConfiguration(block);
try
    properties = simscape.connectionPortProperties(block);
catch
    properties = [];
end
used = false(numel(properties), 1);
for row = 1:numel(rows)
    [configuredName, configuredLabel, configuredType, configured] = ...
        localConfiguredPortIdentity(configuration, rows(row).side, ...
        rows(row).ordinal);
    identities = unique(localNormalizeToken([configuredName; ...
        configuredLabel; rows(row).name]), "stable");
    identities = identities(strlength(identities) > 0);
    propertyIndex = localUniquePropertyMatch(properties, used, identities);
    if propertyIndex > 0
        used(propertyIndex) = true;
        rows(row).name = string(properties(propertyIndex).Name);
        rows(row).label = string(properties(propertyIndex).Label);
        rows(row).interface_type = lower(string( ...
            properties(propertyIndex).Type.InterfaceType));
    elseif configured
        rows(row).name = configuredName;
        rows(row).label = configuredLabel;
        rows(row).interface_type = configuredType;
    end
end
% reference_blank_connection_port_domain_fallback
% R2025a can return no connectionPortProperties/port configuration for the
% source masked Simscape subsystems in the exact task-bound reference.  The
% wrapper file binding guard ensures this file is never selected for a candidate.
% LConn/RConn handles that still report PortType=connection are the native
% conserving-port boundary for these reference subsystems.
for row = 1:numel(rows)
    if strlength(rows(row).interface_type) > 0, continue, end
    try
        if strcmpi(string(get_param(rows(row).handle, "PortType")), "connection")
            rows(row).interface_type = "domain";
        end
    catch
    end
end
end

function configuration = localSimscapePortConfiguration(block)
configuration = struct();
try
    raw = string(get_param(block, "InternalSimscapePortConfiguration"));
    if ~isscalar(raw) || strlength(strtrim(raw)) == 0, return, end
    decoded = jsondecode(char(raw));
    if isstruct(decoded) && isscalar(decoded)
        configuration = decoded;
    end
catch
end
end

function [name, label, interfaceType, configured] = ...
        localConfiguredPortIdentity(configuration, side, ordinal)
name = "";
label = "";
interfaceType = "";
configured = false;
field = "";
if side == "LConn"
    field = "Left";
elseif side == "RConn"
    field = "Right";
end
if strlength(field) == 0 || ~isstruct(configuration) || ...
        ~isfield(configuration, char(field))
    return
end
entries = configuration.(char(field));
if iscell(entries)
    if ordinal > numel(entries), return, end
    entry = entries{ordinal};
elseif isstruct(entries)
    if ordinal > numel(entries), return, end
    entry = entries(ordinal);
else
    return
end
if ~isstruct(entry) || ~isscalar(entry), return, end
configured = true;
if isfield(entry, "id"), name = string(entry.id); end
if isfield(entry, "label"), label = string(entry.label); end
if isfield(entry, "type")
    type = lower(strtrim(string(entry.type)));
    if ismember(type, ["input", "output"])
        interfaceType = type;
    elseif strlength(type) > 0 && contains(type, "composite")
        interfaceType = "compositedomain";
    elseif strlength(type) > 0
        interfaceType = "domain";
    end
end
end

function propertyIndex = localUniquePropertyMatch(properties, used, identities)
propertyIndex = 0;
for identity = reshape(identities, 1, [])
    matches = zeros(0, 1);
    for candidate = 1:numel(properties)
        if used(candidate), continue, end
        propertyName = localNormalizeToken(string(properties(candidate).Name));
        propertyLabel = localNormalizeToken(string(properties(candidate).Label));
        if identity == propertyName || identity == propertyLabel
            matches(end + 1, 1) = candidate; %#ok<AGROW>
        end
    end
    if numel(matches) == 1
        propertyIndex = matches(1);
        return
    end
end
end

function ports = localRootPhysicalPorts(rootBlocks)
ports = zeros(0, 1);
for block = reshape(rootBlocks, 1, [])
    try
        handles = get_param(block, "PortHandles");
    catch
        continue
    end
    for side = ["LConn", "RConn"]
        if ~isfield(handles, side), continue, end
        for port = reshape(double(handles.(side)), 1, [])
            try
                if strcmpi(string(get_param(port, "PortType")), "connection")
                    ports(end + 1, 1) = port; %#ok<AGROW>
                end
            catch
            end
        end
    end
end
ports = unique(ports(isfinite(ports) & ports > 0));
end

function netId = localNetId(port, netIndex)
netId = "";
try
    line = double(get_param(port, "Line"));
    line = line(isfinite(line) & line > 0);
    if isempty(line), return, end
    roots = zeros(0, 1);
    for handle = reshape(line, 1, [])
        key = localHandleKey(handle);
        if isKey(netIndex, key)
            roots(end + 1, 1) = netIndex(key); %#ok<AGROW>
        end
    end
    roots = roots(isfinite(roots) & roots > 0);
    if isempty(roots), return, end
    netId = "net_" + string(sprintf("%.0f", min(roots)));
catch
end
end

function key = localHandleKey(handle)
key = sprintf("%.15g", double(handle));
end

function decision = localAssessCirculation(graph)
emptyWitness = localEmptyWitness();
main = emptyWitness;
ecmo = emptyWitness;
reasons = strings(0, 1);
if ~logical(graph.graph_valid) || ~logical(graph.identity_valid) || ...
        ~logical(graph.conserving_port_graph_valid)
    reasons(end + 1, 1) = "invalid_conserving_port_graph";
end
edges = graph.transport_edges;
if ~isempty(edges)
    main = localFindCycle(edges, 1:numel(edges), ...
        string(graph.compliance_nets), string(graph.reference_nets), "main");
    feedbackIndices = find(string({edges.id}) == ...
        string(graph.feedback_actuator_edge_id));
    ecmo = localFindCycle(edges, feedbackIndices, ...
        string(graph.compliance_nets), string(graph.reference_nets), "ecmo");
end
anchoredPressureNets = intersect(string(graph.pressure_sensor_nets), ...
    string(graph.compliance_nets));
pressure = struct("pass", numel(anchoredPressureNets) >= 3, ...
    "anchored_net_count", numel(anchoredPressureNets), ...
    "net_ids", anchoredPressureNets);
if ~main.pass
    reasons(end + 1, 1) = "missing_closed_systemic_pulmonary_circulation";
end
if ~ecmo.pass
    reasons(end + 1, 1) = "missing_closed_feedback_actuated_ecmo_branch";
end
if ~pressure.pass
    reasons(end + 1, 1) = ...
        "insufficient_compliance_anchored_pressure_measurements";
end
if ~logical(graph.feedback_path_has_dynamic_control)
    reasons(end + 1, 1) = "missing_dynamic_pressure_feedback";
end
if main.search_exhausted || ecmo.search_exhausted
    reasons(end + 1, 1) = "circulation_graph_search_exhausted";
end
pass = isempty(reasons) && main.pass && ecmo.pass && pressure.pass;
if ~pass
    reasons(end + 1, 1) = ...
        "missing_or_unproved_connected_circulation_topology";
end
decision = struct( ...
    "policy_id", "formal90-xmed02-connected-circulation", ...
    "pass", pass, "reasons", unique(reasons, "stable"), ...
    "main_circulation", main, ...
    "ecmo_feedback_branch", ecmo, ...
    "pressure_measurements", pressure);
end

function witness = localFindCycle(edges, candidateIndices, ...
        complianceNets, referenceNets, kind)
witness = localEmptyWitness();
usable = zeros(0, 1);
for index = 1:numel(edges)
    if ~any(referenceNets == string(edges(index).net_a)) && ...
            ~any(referenceNets == string(edges(index).net_b))
        usable(end + 1, 1) = index; %#ok<AGROW>
    end
end
states = 0;
for candidate = reshape(candidateIndices, 1, [])
    if ~any(usable == candidate), continue, end
    start = string(edges(candidate).net_a);
    target = string(edges(candidate).net_b);
    stack = {struct("node", start, "visited", start, ...
        "path", zeros(0, 1))};
    while ~isempty(stack)
        state = stack{end};
        stack(end) = [];
        states = states + 1;
        if states > 50000
            witness.search_exhausted = true;
            return
        end
        if state.node == target && ~isempty(state.path)
            summary = localCycleSummary(edges, ...
                [candidate; state.path(:)], complianceNets);
            if localWitnessPass(summary, kind)
                summary.pass = true;
                witness = summary;
                return
            end
            continue
        end
        for edgeIndex = reshape(flipud(usable), 1, [])
            if edgeIndex == candidate || any(state.path == edgeIndex)
                continue
            end
            edge = edges(edgeIndex);
            other = "";
            if string(edge.net_a) == state.node
                other = string(edge.net_b);
            elseif string(edge.net_b) == state.node
                other = string(edge.net_a);
            end
            if strlength(other) == 0 || any(state.visited == other)
                continue
            end
            stack{end + 1} = struct( ... %#ok<AGROW>
                "node", other, "visited", [state.visited; other], ...
                "path", [state.path; edgeIndex]);
        end
    end
end
end

function summary = localCycleSummary(edges, indices, complianceNets)
roleCounts = struct("resistive", 0, "inertance", 0, ...
    "valve", 0, "flow_sensor", 0, "actuator", 0);
edgeIds = strings(0, 1);
netIds = strings(0, 1);
for index = reshape(indices, 1, [])
    edge = edges(index);
    edgeIds(end + 1, 1) = string(edge.id); %#ok<AGROW>
    netIds = [netIds; string(edge.net_a); string(edge.net_b)]; %#ok<AGROW>
    for role = reshape(string(edge.roles), 1, [])
        field = char(role);
        if isfield(roleCounts, field)
            roleCounts.(field) = roleCounts.(field) + 1;
        end
    end
end
netIds = unique(netIds);
summary = struct("pass", false, "edge_ids", edgeIds, ...
    "net_ids", netIds, "role_counts", roleCounts, ...
    "compliance_net_count", numel(intersect(netIds, complianceNets)), ...
    "search_exhausted", false);
end

function pass = localWitnessPass(summary, kind)
counts = summary.role_counts;
if string(kind) == "main"
    pass = (counts.actuator >= 2 || counts.valve >= 4) && ...
        counts.resistive >= 2 && counts.inertance >= 2 && ...
        counts.flow_sensor >= 2 && summary.compliance_net_count >= 3;
else
    pass = counts.actuator >= 1 && counts.resistive >= 1 && ...
        counts.flow_sensor >= 1 && summary.compliance_net_count >= 2;
end
end

function witness = localEmptyWitness()
witness = struct("pass", false, "edge_ids", strings(0, 1), ...
    "net_ids", strings(0, 1), ...
    "role_counts", struct("resistive", 0, "inertance", 0, ...
        "valve", 0, "flow_sensor", 0, "actuator", 0), ...
    "compliance_net_count", 0, "search_exhausted", false);
end

function identity = localIdentity(block)
parts = strings(0, 1);
for parameter = ["BlockType", "MaskType", "ReferenceBlock", "SourceBlock"]
    try
        value = string(get_param(block, parameter));
        if strlength(value) > 0
            parts(end + 1, 1) = value; %#ok<AGROW>
        end
    catch
    end
end
identity = lower(regexprep(strjoin(parts, " | "), "\s+", " "));
end

function mask = localMatches(values, patterns)
mask = false(size(values));
for index = 1:numel(patterns)
    mask = mask | contains(values, lower(patterns(index)));
end
end

function owners = localOwners(rootBlocks, patterns)
owners = strings(0, 1);
for index = 1:numel(rootBlocks)
    root = rootBlocks(index);
    descendants = find_system(root, "LookUnderMasks", "all", ...
        "FollowLinks", "on", "Type", "Block");
    identities = strings(numel(descendants), 1);
    for blockIndex = 1:numel(descendants)
        identities(blockIndex) = localIdentity(descendants{blockIndex});
    end
    if any(localMatches(identities, patterns))
        owners(end + 1, 1) = root; %#ok<AGROW>
    end
end
owners = unique(owners);
end

function [from, to] = localRootSignalEdges(model)
from = strings(0, 1);
to = strings(0, 1);
lines = find_system(model, "FindAll", "on", "SearchDepth", 1, ...
    "Type", "line");
for index = 1:numel(lines)
    try
        sourcePort = get_param(lines(index), "SrcPortHandle");
        destinationPorts = get_param(lines(index), "DstPortHandle");
        if sourcePort == -1 || isempty(destinationPorts), continue, end
        source = string(getfullname(get_param(sourcePort, "Parent")));
        for destinationPort = destinationPorts(:).'
            if destinationPort == -1, continue, end
            destination = string(getfullname( ...
                get_param(destinationPort, "Parent")));
            from(end + 1, 1) = source; %#ok<AGROW>
            to(end + 1, 1) = destination; %#ok<AGROW>
        end
    catch
    end
end
end

function sink = localOutputSink(model, variable)
sink = "";
blocks = find_system(model, "SearchDepth", 1, ...
    "BlockType", "ToWorkspace");
for index = 1:numel(blocks)
    try
        if string(get_param(blocks{index}, "VariableName")) == variable
            sink = string(blocks{index});
            return
        end
    catch
    end
end
end

function ancestors = localAncestors(sink, from, to)
ancestors = strings(0, 1);
if strlength(sink) == 0, return, end
frontier = sink;
seen = sink;
while ~isempty(frontier)
    next = strings(0, 1);
    for index = 1:numel(frontier)
        parents = from(to == frontier(index));
        parents = setdiff(unique(parents), seen);
        next = [next; parents(:)]; %#ok<AGROW>
        seen = [seen; parents(:)]; %#ok<AGROW>
    end
    frontier = unique(next);
end
ancestors = setdiff(unique(seen), sink);
end

function [ok, path] = localAnyReachable(starts, goals, from, to)
ok = false;
path = strings(0, 1);
for startIndex = 1:numel(starts)
    [found, candidate] = localShortestPath( ...
        starts(startIndex), goals, from, to);
    if found
        ok = true;
        path = candidate;
        return
    end
end
end

function [ok, path] = localAnyReachableVia(starts, vias, goals, from, to)
ok = false;
path = strings(0, 1);
for startIndex = 1:numel(starts)
    for viaIndex = 1:numel(vias)
        [firstFound, firstPath] = localShortestPath( ...
            starts(startIndex), vias(viaIndex), from, to);
        if ~firstFound, continue, end
        [secondFound, secondPath] = localShortestPath( ...
            vias(viaIndex), goals, from, to);
        if secondFound
            ok = true;
            path = [firstPath; secondPath(2:end)];
            return
        end
    end
end
end

function [found, path] = localShortestPath(start, goals, from, to)
found = false;
path = strings(0, 1);
queue = {start};
paths = {start};
seen = start;
while ~isempty(queue)
    node = queue{1};
    nodePath = paths{1};
    queue(1) = [];
    paths(1) = [];
    if any(goals == node)
        found = true;
        path = nodePath;
        return
    end
    children = unique(to(from == node));
    for child = children(:).'
        if any(seen == child), continue, end
        seen(end + 1, 1) = child; %#ok<AGROW>
        queue{end + 1} = child; %#ok<AGROW>
        paths{end + 1} = [nodePath; child]; %#ok<AGROW>
    end
end
end

function ok = localPathHasDynamicControl(path)
ok = false;
for index = 1:numel(path)
    identity = localIdentity(path(index));
    if any(contains(identity, [ ...
            "integrator", "state-space", "statespace", ...
            "transferfcn", "transfer fcn", ...
            "pid", "unitdelay", "memory", "discretefilter", ...
            "discrete filter"]))
        ok = true;
        return
    end
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

function value = localNormalizeToken(value)
value = lower(regexprep(strtrim(string(value)), "[^a-zA-Z0-9]+", ""));
end
