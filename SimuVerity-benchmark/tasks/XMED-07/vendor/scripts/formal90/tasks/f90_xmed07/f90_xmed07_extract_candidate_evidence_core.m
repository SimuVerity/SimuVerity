function evidence = f90_xmed07_extract_candidate_evidence_core( ...
        candidatePath, outDir)
%f90_xmed07_extract_candidate_evidence_core Candidate graph audit.
%   SCORING_CORE keeps the METRICS simulation, scenario, output, and metric contracts, but
%   replaces the provisional global-SCC/name-count audit with independent
%   directed-signal and Simscape conserving-port path witnesses.
arguments
    candidatePath (1,1) string
    outDir (1,1) string
end

[taskRoot, sharedRoot] = localRoots("F90-XMED-07");
addpath(sharedRoot, "-begin");
cleanup = onCleanup(@() rmpath(sharedRoot)); %#ok<NASGU>
official = jsondecode(fileread(simuverity_official_scenarios_path()));
policy = localLoadPolicy;
spec = struct( ...
    "schema", "simuverity.f90-xmed07-evidence.v1", ...
    "task_id", "F90-XMED-07", ...
    "scenarios", official.scenarios, ...
    "output_contract", localOutputs, ...
    "input_builder", @localInputs, ...
    "requested_input_builder", @localRequested, ...
    "stop_time", @(scenario, unused) double(scenario.stop_time_s), ... %#ok<NASGU>
    "postprocess", @localPostprocess, ...
    "static_audit", @(model, taskSpec) localAudit(model, taskSpec, policy), ...
    "finalize_evidence", @(item, taskSpec) localFinalize(item, taskSpec), ...
    "evidence_sample_s", 0.02);
evidence = simuverity_run_candidate_evidence(candidatePath, outDir, spec);
end

function policy = localLoadPolicy
policyPath = fullfile(fileparts(mfilename("fullpath")), ...
    "f90_xmed07_structure_policy.json");
policy = jsondecode(fileread(policyPath));
assert(string(policy.schema) == ...
    "simuverity.f90-xmed07-structure-policy.v1", ...
    "SimuVerity:F90:XMED07:PolicySchema", ...
    "Unsupported structure policy.");
identityFields = string(policy.qualification_identity_fields);
assert(~any(strcmpi(identityFields, "Name")) && ...
    ~any(strcmpi(identityFields, "MaskType")), ...
    "SimuVerity:F90:XMED07:IdentityPolicy", ...
    "Display Name and candidate MaskType cannot grant a physical role.");
assert(~logical(policy.name_match_is_sufficient) && ...
    ~logical(policy.global_signal_scc_is_qualification), ...
    "SimuVerity:F90:XMED07:QualificationPolicy", ...
    "Names and global signal SCCs cannot grant SCORING_CORE qualification.");
end

function evidence = localFinalize(evidence, ~)
taskDir = fileparts(mfilename("fullpath"));
evidence.candidate_evidence_ready = true;
evidence.structure_evidence_schema = ...
    "simuverity.f90-xmed07-structure-evidence.v1";
evidence.structure_policy_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmed07_structure_policy.json"));
evidence.current_simulation_kernel_file_presence = localFilePresence(fullfile( ...
    fileparts(taskDir), "_shared", ...
    "simuverity_run_candidate_evidence.m"));
evidence.current_offline_scorer_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmed07_scoring_core.py"));
evidence.score_fields_present = false;
end

function audit = localAudit(model, spec, policy)
nodes = localNodes(model, policy);
[signalEdges, signalDiagnostics] = localSignalEdges(nodes, policy);
[physicalEdges, physicalDiagnostics] = localPhysicalEdges(nodes);

roles = struct;
physicalRoleNames = ["motor", "transmission", "slide", "reservoir", ...
    "line", "patient", "flow_sensor", "speed_sensor", ...
    "force_sensor", "pressure_sensor", "displacement_sensor", ...
    "occlusion_source", "actuator"];
for roleName = physicalRoleNames
    roles.(roleName) = localRoleCandidates(nodes, roleName, policy);
end

mainChain = localPhysicalChainWitness(physicalEdges, { ...
    roles.motor, roles.transmission, roles.slide, roles.reservoir, ...
    roles.line, roles.patient});
[upstreamFlow, patientFlow] = localFlowWitnesses( ...
    mainChain, roles.flow_sensor);
occlusionPhysical = localRouteRoleWitness( ...
    mainChain, roles.occlusion_source, 4, 6);
speedSensors = localPhysicallyCoupled(physicalEdges, ...
    roles.speed_sensor, roles.motor);
forceSensors = localPhysicallyCoupled(physicalEdges, ...
    roles.force_sensor, unique([roles.slide; roles.reservoir; roles.line]));
pressureSensors = localPhysicallyCoupled(physicalEdges, ...
    roles.pressure_sensor, unique([roles.reservoir; roles.line; roles.patient]));
displacementSensors = localPhysicallyCoupled(physicalEdges, ...
    roles.displacement_sensor, unique([roles.slide; roles.reservoir]));
actuators = localPhysicallyCoupled(physicalEdges, ...
    roles.actuator, roles.motor);

commandSources = localBlocksReferencingVariables(nodes, ...
    string(policy.drive_command_fields));
lowRemainingSources = localBlocksReferencingVariables(nodes, ...
    string(policy.low_remaining_command_field));
controlNodes = localControlNodes(nodes, policy);
motorCandidates = localControlRoleCandidates(nodes, controlNodes, ...
    "motor_controller", string(policy.motor_controller_specialist_types), policy);
detectorCandidates = localControlRoleCandidates(nodes, controlNodes, ...
    "occlusion_detector", string(policy.detector_specialist_types), policy);
supervisorCandidates = localControlRoleCandidates(nodes, controlNodes, ...
    "supervisor", string(policy.supervisor_specialist_types), policy);
remainingCandidates = localControlRoleCandidates(nodes, controlNodes, ...
    "remaining", string(policy.remaining_specialist_types), policy);
motorControllers = localMotorControllers(signalEdges, motorCandidates, ...
    commandSources, speedSensors, actuators);
remainingSources = localRemainingSources(signalEdges, remainingCandidates, ...
    displacementSensors, upstreamFlow);
[supervisors, supervisorControllerPairs] = localSupervisors( ...
    signalEdges, supervisorCandidates, commandSources, ...
    lowRemainingSources, remainingSources, motorControllers);
detectors = localOcclusionDetectors(signalEdges, detectorCandidates, ...
    speedSensors, forceSensors, motorControllers, supervisors);

outputSinks = localPublicOutputSinks(nodes, ...
    string({spec.output_contract.name}));
deliveryIntegrators = localDeliveryIntegrators(signalEdges, ...
    remainingCandidates, patientFlow, outputSinks.delivery_state);
motionOutput = localPublicOutputUpstream(signalEdges, nodes, ...
    "motion_state", outputSinks.motion_state, ...
    ["command", "motor_controller", "speed_sensor", "displacement_sensor"], ...
    {commandSources, motorControllers, speedSensors, displacementSensors});
deliveryOutput = localPublicOutputUpstream(signalEdges, nodes, ...
    "delivery_state", outputSinks.delivery_state, ...
    ["upstream_flow_sensor", "patient_flow_sensor", ...
    "pressure_sensor", "delivery_integrator"], ...
    {upstreamFlow, patientFlow, pressureSensors, deliveryIntegrators});
safetyOutput = localPublicOutputUpstream(signalEdges, nodes, ...
    "safety_state", outputSinks.safety_state, ...
    ["force_or_pressure_sensor", "occlusion_detector", ...
    "supervisor", "remaining_source"], ...
    {unique([forceSensors; pressureSensors]), detectors, ...
    supervisors, remainingSources});

raw = struct;
raw.command_to_supervisor = localSignalReachable( ...
    signalEdges, commandSources, supervisors);
raw.supervisor_to_motor_controller = ...
    localPairReachable(supervisorControllerPairs);
raw.motor_controller_to_actuator = localSignalReachable( ...
    signalEdges, motorControllers, actuators);
raw.speed_to_motor_controller = localSignalReachable( ...
    signalEdges, speedSensors, motorControllers);
raw.speed_to_occlusion_detector = localSignalReachable( ...
    signalEdges, speedSensors, detectors);
raw.force_to_occlusion_detector = localSignalReachable( ...
    signalEdges, forceSensors, detectors);
raw.occlusion_detector_to_supervisor = localSignalReachable( ...
    signalEdges, detectors, supervisors);
raw.remaining_to_supervisor = localSignalReachable( ...
    signalEdges, remainingSources, supervisors) && ...
    localSignalReachable(signalEdges, lowRemainingSources, supervisors);
raw.controller_components = ~isempty(motorControllers) && ...
    ~isempty(detectors) && ~isempty(supervisors) && ...
    localThreeDistinctWitnesses(motorControllers, detectors, supervisors);
rawPhysical = struct( ...
    "motor_transmission_slide_reservoir_line_patient", mainChain.pass, ...
    "two_distinct_in_route_flow_sensors", ...
        ~isempty(upstreamFlow) && ~isempty(patientFlow), ...
    "in_route_occlusion_source", ~isempty(occlusionPhysical));

audit = struct( ...
    "top_command_to_software", raw.command_to_supervisor && motionOutput.pass, ...
    "top_software_to_motor_plant", ...
        raw.motor_controller_to_actuator && motionOutput.pass, ...
    "top_plant_feedback_to_software", ...
        raw.speed_to_motor_controller && motionOutput.pass, ...
    "software_reference_to_motor_controller", ...
        raw.supervisor_to_motor_controller && motionOutput.pass, ...
    "measured_speed_to_motor_controller", ...
        raw.speed_to_motor_controller && motionOutput.pass, ...
    "measured_speed_to_occlusion_detector", ...
        raw.speed_to_occlusion_detector && safetyOutput.pass, ...
    "load_force_to_occlusion_detector", ...
        raw.force_to_occlusion_detector && safetyOutput.pass, ...
    "occlusion_to_supervisory", ...
        raw.occlusion_detector_to_supervisor && safetyOutput.pass, ...
    "remaining_units_to_supervisory", ...
        raw.remaining_to_supervisor && safetyOutput.pass, ...
    "physical_motor_present", mainChain.pass, ...
    "physical_transmission_present", mainChain.pass, ...
    "physical_slide_present", mainChain.pass, ...
    "physical_reservoir_present", mainChain.pass, ...
    "physical_delivery_line_present", mainChain.pass && deliveryOutput.pass, ...
    "physical_patient_boundary_present", mainChain.pass, ...
    "physical_upstream_flow_sensor_present", ...
        ~isempty(upstreamFlow) && deliveryOutput.pass, ...
    "physical_patient_flow_sensor_present", ...
        ~isempty(patientFlow) && deliveryOutput.pass, ...
    "native_occlusion_source_present", ...
        ~isempty(occlusionPhysical) && deliveryOutput.pass && safetyOutput.pass, ...
    "controller_component_models_present", raw.controller_components, ...
    "candidate_delivery_path_qualified", mainChain.pass && ...
        ~isempty(upstreamFlow) && ~isempty(patientFlow), ...
    "motion_state_upstream_qualified", motionOutput.pass, ...
    "delivery_state_upstream_qualified", deliveryOutput.pass, ...
    "safety_state_upstream_qualified", safetyOutput.pass, ...
    "public_outputs_all_upstream_qualified", ...
        motionOutput.pass && deliveryOutput.pass && safetyOutput.pass, ...
    "connected_public_output_count", localConnectedOutputCount(outputSinks), ...
    "raw_causal_facts", raw, ...
    "raw_physical_facts", rawPhysical, ...
    "role_candidates", localRoleSummary(nodes, roles, ...
        commandSources, lowRemainingSources, controlNodes), ...
    "fact_witnesses", localFactWitnesses(signalEdges, nodes, ...
        commandSources, supervisors, motorControllers, actuators, ...
        speedSensors, detectors, forceSensors, remainingSources), ...
    "physical_chain_witness", localPhysicalWitnessRows(nodes, mainChain), ...
    "physical_upstream_flow_witness", localNodePaths(nodes, upstreamFlow), ...
    "physical_patient_flow_witness", localNodePaths(nodes, patientFlow), ...
    "physical_occlusion_witness", localNodePaths(nodes, occlusionPhysical), ...
    "public_output_upstream", struct( ...
        "motion_state", motionOutput, "delivery_state", deliveryOutput, ...
        "safety_state", safetyOutput), ...
    "signal_graph", signalDiagnostics, ...
    "physical_graph", physicalDiagnostics, ...
    "identity_qualification_fields", ...
        string(policy.qualification_identity_fields), ...
    "display_name_is_sufficient", false, ...
    "candidate_mask_type_is_trusted", false, ...
    "global_signal_scc_used", false);
end

function nodes = localNodes(model, policy)
blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
template = struct( ...
    "path", "", "handle", 0, "parent", "", "name", "", ...
    "block_type", "", "trusted_identity", "", ...
    "connected_signal_in", 0, "connected_signal_out", 0, ...
    "connection_ports", struct([]), ...
    "connected_domain_port_count", 0, ...
    "connected_physical_signal_port_count", 0);
nodes = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    rows = localConnectionPortRows(block);
    nodes(index).path = block;
    nodes(index).handle = double(get_param(block, "Handle"));
    nodes(index).parent = localGet(block, "Parent");
    nodes(index).name = localGet(block, "Name");
    nodes(index).block_type = localGet(block, "BlockType");
    nodes(index).trusted_identity = localTrustedIdentity(block, policy);
    nodes(index).connected_signal_in = ...
        localConnectedPortCount(block, "Inport");
    nodes(index).connected_signal_out = ...
        localConnectedPortCount(block, "Outport");
    nodes(index).connection_ports = rows;
    if ~isempty(rows)
        connected = logical([rows.connected]);
        domain = logical([rows.is_domain]);
        nodes(index).connected_domain_port_count = nnz(connected & domain);
        nodes(index).connected_physical_signal_port_count = ...
            nnz(connected & ~domain);
    end
end
end

function identity=localTrustedIdentity(block, policy)
parts = strings(0, 1);
for parameter = string(policy.qualification_identity_fields(:)).'
    value = localGet(block, parameter);
    if strlength(value) > 0
        parts(end + 1, 1) = value; %#ok<AGROW>
    end
end
identity = join(parts, " | ");
end

function rows = localConnectionPortRows(block)
template = struct( ...
    "handle", 0, "side", "", "ordinal", 0, "type", "", ...
    "name", "", "label", "", "is_domain", false, ...
    "is_input", false, "is_output", false, "connected", false);
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
            "side", side, ...
            "ordinal", ordinal, ...
            "type", "", ...
            "name", localPortText(sideHandles(ordinal), "Name"), ...
            "label", "", ...
            "is_domain", false, ...
            "is_input", false, ...
            "is_output", false, ...
            "connected", localPortConnected(sideHandles(ordinal)));
    end
end
if isempty(rows), return, end

% R2025a exposes one record per physical modeling port.  We bind records
% to LConn/RConn handles by unique Name/Label when possible and otherwise
% by the documented returned port order.  An unresolved record is not
% treated as a conserving port.
try
    properties = simscape.connectionPortProperties(block);
catch
    return
end
if isempty(properties), return, end
used = false(numel(properties), 1);
for rowIndex = 1:numel(rows)
    propertyIndex = 0;
    portName = localNormalize(rows(rowIndex).name);
    if strlength(portName) > 0
        for candidate = 1:numel(properties)
            propertyName = localNormalize(localObjectText( ...
                properties(candidate), "Name"));
            propertyLabel = localNormalize(localObjectText( ...
                properties(candidate), "Label"));
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
    typeValue = localObjectText(properties(propertyIndex), "Type");
    propertyName = localObjectText(properties(propertyIndex), "Name");
    rows(rowIndex).type = typeValue;
    if strlength(rows(rowIndex).name) == 0
        rows(rowIndex).name = propertyName;
    end
    rows(rowIndex).label = localObjectText( ...
        properties(propertyIndex), "Label");
    normalized = lower(strtrim(typeValue));
    rows(rowIndex).is_domain = startsWith(normalized, "domain") || ...
        contains(normalized, "conserving");
    rows(rowIndex).is_input = contains(normalized, "input");
    rows(rowIndex).is_output = contains(normalized, "output");
end
end

function value = localObjectText(object, property)
value = "";
try
    value = string(object.(property));
    if ~isscalar(value), value = join(value(:), " "); end
catch
end
end

function value = localPortText(port, parameter)
value = "";
try
    value = string(get_param(port, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
catch
end
end

function [edges, diagnostics] = localSignalEdges(nodes, policy)
edges = zeros(0, 2);
for sourceIndex = 1:numel(nodes)
    block = nodes(sourceIndex).path;
    try
        ports = get_param(block, "PortHandles");
    catch
        continue
    end
    if ~isfield(ports, "Outport"), continue, end
    for port = reshape(double(ports.Outport), 1, [])
        resolvedSources = localSignalEndpointNodes( ...
            nodes, port, "source");
        connectedPorts = localConnectedLinePorts(port);
        for destinationPort = connectedPorts(:).'
            resolvedDestinations = localSignalEndpointNodes( ...
                nodes, destinationPort, "destination");
            for resolvedSource = reshape(resolvedSources, 1, [])
                for resolvedDestination = reshape(resolvedDestinations, 1, [])
                    if resolvedSource ~= resolvedDestination
                        edges(end + 1, :) = ... %#ok<AGROW>
                            [resolvedSource, resolvedDestination];
                    end
                end
            end
        end
    end
end

physicalSignalEdges = localPhysicalSignalCausalEdges(nodes, policy);
edges = unique([edges; physicalSignalEdges], "rows");
edges = edges(edges(:, 1) ~= edges(:, 2), :);
diagnostics = struct( ...
    "node_count", numel(nodes), ...
    "directed_edge_count", size(edges, 1), ...
    "physical_signal_causal_edge_count", size(physicalSignalEdges, 1), ...
    "qualification_uses_global_scc", false, ...
    "hierarchy_bridges_present", true, ...
    "hierarchy_bridge_kind", "port-number-preserving");
end

function indices = localSignalEndpointNodes(nodes, port, direction)
indices = zeros(0, 1);
parentIndex = localNodeIndex(nodes, localParentHandle(port));
if parentIndex <= 0, return, end
parentType = lower(nodes(parentIndex).block_type);
if ~any(parentType == ["subsystem", "modelreference"])
    indices = parentIndex;
    return
end
if parentType == "modelreference"
    % A referenced model is not granted opaque input-to-output causality.
    return
end
portNumber = localNumericPortParameter(port, "PortNumber");
if ~isfinite(portNumber)
    if direction == "source", portField = "Outport";
    else, portField = "Inport";
    end
    portNumber = localStandardPortOrdinal( ...
        nodes(parentIndex).path, port, portField);
end
if ~isfinite(portNumber), return, end
if direction == "source"
    boundaryType = "outport";
else
    boundaryType = "inport";
end
for index = 1:numel(nodes)
    if nodes(index).parent ~= nodes(parentIndex).path || ...
            lower(nodes(index).block_type) ~= boundaryType
        continue
    end
    boundaryPort = localNumericBlockParameter(nodes(index).path, "Port");
    if isfinite(boundaryPort) && boundaryPort == portNumber
        indices(end + 1, 1) = index; %#ok<AGROW>
    end
end
end

function edges = localPhysicalSignalCausalEdges(nodes, policy)
edges = zeros(0, 2);
for sourceIndex = 1:numel(nodes)
    rows = nodes(sourceIndex).connection_ports;
    for rowIndex = 1:numel(rows)
        row = rows(rowIndex);
        if row.is_domain || ~row.connected, continue, end
        resolvedSources = localPhysicalEndpointNodes( ...
            nodes, row.handle);
        connectedPorts = localConnectedLinePorts(row.handle);
        for otherPort = connectedPorts(:).'
            otherBlock = localParentHandle(otherPort);
            otherIndex = localNodeIndex(nodes, otherBlock);
            if otherIndex <= 0, continue, end
            otherRow = localConnectionRowForHandle( ...
                nodes(otherIndex).connection_ports, otherPort);
            if isempty(otherRow) || otherRow.is_domain, continue, end
            resolvedOthers = localPhysicalEndpointNodes(nodes, otherPort);
            for resolvedSource = reshape(resolvedSources, 1, [])
                for resolvedOther = reshape(resolvedOthers, 1, [])
                    if resolvedSource == resolvedOther, continue, end
                    if row.is_output && otherRow.is_input
                        edges(end + 1, :) = ... %#ok<AGROW>
                            [resolvedSource, resolvedOther];
                    elseif row.is_input && otherRow.is_output
                        edges(end + 1, :) = ... %#ok<AGROW>
                            [resolvedOther, resolvedSource];
                    elseif localMatchesTokens( ...
                            nodes(resolvedSource).trusted_identity, ...
                            string(policy.role_identity_tokens.simulink_to_ps)) || ...
                            localMatchesTokens( ...
                            nodes(resolvedOther).trusted_identity, ...
                            string(policy.role_identity_tokens.ps_to_simulink))
                        edges(end + 1, :) = ... %#ok<AGROW>
                            [resolvedSource, resolvedOther];
                    elseif localMatchesTokens( ...
                            nodes(resolvedSource).trusted_identity, ...
                            string(policy.role_identity_tokens.ps_to_simulink)) || ...
                            localMatchesTokens( ...
                            nodes(resolvedOther).trusted_identity, ...
                            string(policy.role_identity_tokens.simulink_to_ps))
                        edges(end + 1, :) = ... %#ok<AGROW>
                            [resolvedOther, resolvedSource];
                    end
                end
            end
        end
    end
end
edges = unique(edges, "rows");
end

function [edges, diagnostics] = localPhysicalEdges(nodes)
lineEdges = zeros(0, 2);
hierarchyBridgeCount = 0;
for sourceIndex = 1:numel(nodes)
    rows = nodes(sourceIndex).connection_ports;
    for rowIndex = 1:numel(rows)
        row = rows(rowIndex);
        if ~row.is_domain || ~row.connected, continue, end
        resolvedSources = localPhysicalEndpointNodes(nodes, row.handle);
        connectedPorts = localConnectedLinePorts(row.handle);
        for otherPort = connectedPorts(:).'
            otherBlock = localParentHandle(otherPort);
            otherIndex = localNodeIndex(nodes, otherBlock);
            if otherIndex <= 0, continue, end
            otherRow = localConnectionRowForHandle( ...
                nodes(otherIndex).connection_ports, otherPort);
            if ~isempty(otherRow) && otherRow.is_domain && otherRow.connected
                resolvedOthers = localPhysicalEndpointNodes(nodes, otherPort);
                for resolvedSource = reshape(resolvedSources, 1, [])
                    for resolvedOther = reshape(resolvedOthers, 1, [])
                        if resolvedSource ~= resolvedOther
                            lineEdges(end + 1, :) = ... %#ok<AGROW>
                                sort([resolvedSource, resolvedOther]);
                            hierarchyBridgeCount = hierarchyBridgeCount + ...
                                double(resolvedSource ~= sourceIndex || ...
                                resolvedOther ~= otherIndex);
                        end
                    end
                end
            end
        end
    end
end
lineEdges = unique(lineEdges, "rows");

% PortConnectivity is a second, independent observation that each retained
% edge is an actual LConn/RConn block connection.  It is diagnostic rather
% than a name- or component-count shortcut.
connectivityPairs = localPortConnectivityPairs(nodes);
confirmed = ismember(lineEdges, connectivityPairs, "rows");
edges = lineEdges;
diagnostics = struct( ...
    "node_count", numel(nodes), ...
    "conserving_edge_count", size(edges, 1), ...
    "line_derived_edge_count", size(lineEdges, 1), ...
    "port_connectivity_confirmed_edge_count", nnz(confirmed), ...
    "hierarchy_bridge_count", hierarchyBridgeCount, ...
    "hierarchy_bridge_kind", "connection-port-preserving", ...
    "physical_signal_edges_excluded", true, ...
    "conserving_port_metadata_api", "simscape.connectionPortProperties", ...
    "connection_sides", ["LConn", "RConn"]);
end

function pairs = localPortConnectivityPairs(nodes)
pairs = zeros(0, 2);
for index = 1:numel(nodes)
    if nodes(index).connected_domain_port_count < 1, continue, end
    try
        connectivity = get_param(nodes(index).path, "PortConnectivity");
    catch
        connectivity = struct([]);
    end
    for row = 1:numel(connectivity)
        typeValue = string(connectivity(row).Type);
        if ~any(contains(typeValue, ["LConn", "RConn"])), continue, end
        neighbors = [double(connectivity(row).SrcBlock(:)); ...
            double(connectivity(row).DstBlock(:))];
        neighbors = neighbors(isfinite(neighbors) & neighbors > 0);
        for handle = neighbors(:).'
            neighborIndex = localNodeIndex(nodes, handle);
            if neighborIndex > 0 && neighborIndex ~= index && ...
                    nodes(neighborIndex).connected_domain_port_count >= 1
                pairs(end + 1, :) = sort([index, neighborIndex]); %#ok<AGROW>
            end
        end
    end
end
pairs = unique(pairs, "rows");
end

function candidates = localRoleCandidates(nodes, roleName, policy)
tokens = string(policy.role_identity_tokens.(roleName));
minimum = double(policy.minimum_conserving_ports.(roleName));
candidates = zeros(0, 1);
for index = 1:numel(nodes)
    % Name is deliberately read only to form a broad discovery pool.  A
    % role is granted below solely by trusted identity and connected Domain
    % conserving ports, so a renamed Gain/Subsystem cannot satisfy it.
    discoveredByName = localMatchesTokens(nodes(index).name, tokens); %#ok<NASGU>
    identityQualified = localMatchesTokens( ...
        nodes(index).trusted_identity, tokens);
    portQualified = nodes(index).connected_domain_port_count >= minimum;
    if identityQualified && portQualified
        candidates(end + 1, 1) = index; %#ok<AGROW>
    end
end
candidates = candidates(1:min(numel(candidates), ...
    double(policy.maximum_role_candidates)));
end

function candidates = localBlocksReferencingVariables(nodes, variableNames)
candidates = zeros(0, 1);
for index = 1:numel(nodes)
    textValue = localDialogText(nodes(index).path);
    if strlength(textValue) == 0, continue, end
    for variableName = reshape(string(variableNames), 1, [])
        expression = "(?<![A-Za-z0-9_])" + ...
            regexptranslate("escape", variableName) + ...
            "(?![A-Za-z0-9_])";
        if ~isempty(regexp(textValue, expression, "once"))
            candidates(end + 1, 1) = index; %#ok<AGROW>
            break
        end
    end
end
candidates = unique(candidates, "stable");
end

function value = localDialogText(block)
parts = strings(0, 1);
try
    parameters = get_param(block, "DialogParameters");
    fields = string(fieldnames(parameters));
catch
    fields = strings(0, 1);
end
for field = fields(:).'
    try
        item = get_param(block, field);
        item = localValueText(item);
        if strlength(item) > 0
            parts(end + 1, 1) = item; %#ok<AGROW>
        end
    catch
    end
end
for field = ["Value", "Expression", "VariableName", "Script"]
    try
        item = localValueText(get_param(block, field));
        if strlength(item) > 0
            parts(end + 1, 1) = item; %#ok<AGROW>
        end
    catch
    end
end
value = join(unique(parts, "stable"), " ");
end

function value = localValueText(item)
value = "";
try
    if ischar(item) || isstring(item) || isnumeric(item) || islogical(item)
        text = string(item);
        value = join(text(:), " ");
    end
catch
end
end

function controls = localControlNodes(nodes, policy)
controls = zeros(0, 1);
trustedTypes = lower(string(policy.control_block_types));
stateflowTypes = lower(string(policy.stateflow_control_types));
for index = 1:numel(nodes)
    if nodes(index).connected_signal_in < 1 || ...
            nodes(index).connected_signal_out < 1
        continue
    end
    blockType = lower(nodes(index).block_type);
    stateflowType = lower(localGet(nodes(index).path, "SFBlockType"));
    direct = any(blockType == trustedTypes) || ...
        any(stateflowType == stateflowTypes);
    subsystem = blockType == "subsystem" && ...
        localSubsystemHasControlCapability(nodes(index).path, ...
        trustedTypes, stateflowTypes);
    modelReference = blockType == "modelreference" && ...
        strlength(localGet(nodes(index).path, "ModelName")) > 0;
    if direct || subsystem || modelReference
        controls(end + 1, 1) = index; %#ok<AGROW>
    end
end
end

function pass = localSubsystemHasControlCapability( ...
        subsystem, trustedTypes, stateflowTypes)
pass = false;
try
    descendants = string(find_system(subsystem, ...
        "LookUnderMasks", "all", "FollowLinks", "on", ...
        "Type", "Block"));
catch
    return
end
descendants = descendants(descendants ~= string(subsystem));
for block = descendants(:).'
    blockType = lower(localGet(block, "BlockType"));
    stateflowType = lower(localGet(block, "SFBlockType"));
    if any(blockType == trustedTypes) || any(stateflowType == stateflowTypes)
        pass = true;
        return
    end
end
end

function candidates = localControlRoleCandidates( ...
        nodes, controls, roleName, specialistTypes, policy)
preferred = zeros(0, 1);
tokens = string(policy.role_discovery_tokens.(roleName));
specialistTypes = lower(string(specialistTypes));
for index = reshape(controls, 1, [])
    displayDiscovered = localMatchesTokens(nodes(index).name, tokens);
    capabilityDiscovered = any(lower(nodes(index).block_type) == ...
        specialistTypes) || strlength(localGet(nodes(index).path, ...
        "SFBlockType")) > 0;
    if displayDiscovered || capabilityDiscovered
        preferred(end + 1, 1) = index; %#ok<AGROW>
    end
end
% Display text only orders discovery; every returned block already passed
% the actual signal-port and executable-control capability checks.
candidates = unique([preferred; controls], "stable");
candidates = candidates(1:min(numel(candidates), ...
    double(policy.maximum_role_candidates)));
end

function controllers = localMotorControllers( ...
        edges, candidates, commands, speedSensors, actuators)
controllers = zeros(0, 1);
for candidate = reshape(candidates, 1, [])
    if localSignalReachable(edges, commands, candidate) && ...
            localSignalReachable(edges, speedSensors, candidate) && ...
            localSignalReachable(edges, candidate, actuators)
        controllers(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
controllers = unique(controllers, "stable");
end

function sources = localRemainingSources( ...
        edges, candidates, displacementSensors, upstreamFlow)
sources = zeros(0, 1);
physicalOrigins = unique([displacementSensors; upstreamFlow]);
for candidate = reshape(candidates, 1, [])
    if localSignalReachable(edges, physicalOrigins, candidate)
        sources(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
sources = unique(sources, "stable");
end

function [supervisors, pairs] = localSupervisors( ...
        edges, candidates, commands, lowRemainingCommands, ...
        remainingSources, controllers)
supervisors = zeros(0, 1);
pairs = zeros(0, 2);
for supervisor = reshape(candidates, 1, [])
    if ~localSignalReachable(edges, commands, supervisor) || ...
            ~localSignalReachable(edges, lowRemainingCommands, supervisor) || ...
            ~localSignalReachable(edges, remainingSources, supervisor)
        continue
    end
    for controller = reshape(controllers, 1, [])
        if supervisor ~= controller && ...
                localSignalReachable(edges, supervisor, controller)
            supervisors(end + 1, 1) = supervisor; %#ok<AGROW>
            pairs(end + 1, :) = [supervisor, controller]; %#ok<AGROW>
        end
    end
end
supervisors = unique(supervisors, "stable");
pairs = unique(pairs, "rows", "stable");
end

function detectors = localOcclusionDetectors( ...
        edges, candidates, speedSensors, forceSensors, controllers, supervisors)
detectors = zeros(0, 1);
for candidate = reshape(candidates, 1, [])
    if any(candidate == controllers) || any(candidate == supervisors)
        continue
    end
    if localSignalReachable(edges, speedSensors, candidate) && ...
            localSignalReachable(edges, forceSensors, candidate)
        detectors(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
detectors = unique(detectors, "stable");
end

function integrators = localDeliveryIntegrators( ...
        edges, candidates, patientFlow, deliverySinks)
integrators = zeros(0, 1);
for candidate = reshape(candidates, 1, [])
    if localSignalReachable(edges, patientFlow, candidate) && ...
            localSignalReachable(edges, candidate, deliverySinks)
        integrators(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
integrators = unique(integrators, "stable");
end

function [supervisorPass] = localPairReachable(pairs)
supervisorPass = ~isempty(pairs);
end

function pass = localThreeDistinctWitnesses(controllers, detectors, supervisors)
pass = false;
for controller = reshape(controllers, 1, [])
    for detector = reshape(detectors, 1, [])
        for supervisor = reshape(supervisors, 1, [])
            if numel(unique([controller, detector, supervisor])) == 3
                pass = true;
                return
            end
        end
    end
end
end

function coupled = localPhysicallyCoupled(edges, candidates, targets)
coupled = zeros(0, 1);
for candidate = reshape(candidates, 1, [])
    if localPhysicalReachable(edges, candidate, targets)
        coupled(end + 1, 1) = candidate; %#ok<AGROW>
    end
end
coupled = unique(coupled, "stable");
end

function witness = localPhysicalChainWitness(edges, roleSets)
witness = struct( ...
    "pass", false, ...
    "role_nodes", zeros(0, 1), ...
    "path_nodes", zeros(0, 1));
if isempty(roleSets) || any(cellfun(@isempty, roleSets)), return, end
for start = reshape(roleSets{1}, 1, [])
    [pass, roleNodes, pathNodes] = localExtendPhysicalChain( ...
        edges, roleSets, 2, start, start, start);
    if pass
        witness.pass = true;
        witness.role_nodes = roleNodes;
        witness.path_nodes = pathNodes;
        return
    end
end
end

function [pass, roleNodesOut, pathNodesOut] = localExtendPhysicalChain( ...
        edges, roleSets, stage, current, used, roleNodes, pathNodes)
if stage > numel(roleSets)
    pass = true;
    roleNodesOut = roleNodes;
    pathNodesOut = pathNodes;
    return
end
pass = false;
roleNodesOut = zeros(0, 1);
pathNodesOut = zeros(0, 1);
for target = reshape(roleSets{stage}, 1, [])
    if any(target == used), continue, end
    [segmentPass, segment] = localShortestPhysicalPath( ...
        edges, current, target, setdiff(used, current));
    if ~segmentPass, continue, end
    newNodes = segment(2:end);
    if any(ismember(newNodes, used)), continue, end
    [childPass, childRoles, childPath] = localExtendPhysicalChain( ...
        edges, roleSets, stage + 1, target, ...
        [used(:); newNodes(:)], [roleNodes(:); target], ...
        [pathNodes(:); newNodes(:)]);
    if childPass
        pass = true;
        roleNodesOut = childRoles;
        pathNodesOut = childPath;
        return
    end
end
end

function [pass, pathNodes] = localShortestPhysicalPath( ...
        edges, source, target, blocked)
pass = false;
pathNodes = zeros(0, 1);
if isempty(source) || isempty(target), return, end
if source == target
    pass = true;
    pathNodes = source;
    return
end
nodeCount = max([edges(:); source; target; 0]);
adjacency = cell(nodeCount, 1);
for row = 1:size(edges, 1)
    left = edges(row, 1);
    right = edges(row, 2);
    adjacency{left}(end + 1) = right; %#ok<AGROW>
    adjacency{right}(end + 1) = left; %#ok<AGROW>
end
seen = false(nodeCount, 1);
previous = zeros(nodeCount, 1);
blocked = blocked(blocked >= 1 & blocked <= nodeCount);
seen(blocked) = true;
seen(source) = true;
queue = source;
while ~isempty(queue)
    current = queue(1);
    queue(1) = [];
    for successor = adjacency{current}
        if seen(successor), continue, end
        seen(successor) = true;
        previous(successor) = current;
        if successor == target
            pathNodes = target;
            while pathNodes(1) ~= source
                parent = previous(pathNodes(1));
                if parent <= 0
                    pathNodes = zeros(0, 1);
                    return
                end
                pathNodes = [parent; pathNodes]; %#ok<AGROW>
            end
            pass = true;
            return
        end
        queue(end + 1) = successor; %#ok<AGROW>
    end
end
end

function pass = localPhysicalReachable(edges, sources, targets)
pass = false;
if isempty(sources) || isempty(targets), return, end
if any(ismember(sources, targets)), pass = true; return, end
nodeCount = max([edges(:); sources(:); targets(:); 0]);
adjacency = cell(nodeCount, 1);
for row = 1:size(edges, 1)
    left = edges(row, 1);
    right = edges(row, 2);
    adjacency{left}(end + 1) = right; %#ok<AGROW>
    adjacency{right}(end + 1) = left; %#ok<AGROW>
end
seen = false(nodeCount, 1);
queue = unique(sources(:)).';
seen(queue) = true;
targetMask = false(nodeCount, 1);
targetMask(targets) = true;
while ~isempty(queue)
    current = queue(1);
    queue(1) = [];
    if targetMask(current), pass = true; return, end
    for successor = adjacency{current}
        if ~seen(successor)
            seen(successor) = true;
            queue(end + 1) = successor; %#ok<AGROW>
        end
    end
end
end

function [upstream, patient] = localFlowWitnesses(chain, flowSensors)
upstream = zeros(0, 1);
patient = zeros(0, 1);
if ~chain.pass || numel(chain.role_nodes) < 6, return, end
positions = find(ismember(chain.path_nodes, flowSensors));
if numel(positions) < 2, return, end
reservoirPosition = find(chain.path_nodes == chain.role_nodes(4), 1, "first");
patientPosition = find(chain.path_nodes == chain.role_nodes(6), 1, "last");
positions = positions(positions > reservoirPosition & positions < patientPosition);
if numel(positions) < 2, return, end
upstream = chain.path_nodes(positions(1));
patient = chain.path_nodes(positions(end));
if upstream == patient
    upstream = zeros(0, 1);
    patient = zeros(0, 1);
end
end

function witness = localRouteRoleWitness(chain, candidates, firstRole, lastRole)
witness = zeros(0, 1);
if ~chain.pass || numel(chain.role_nodes) < lastRole, return, end
firstPosition = find(chain.path_nodes == ...
    chain.role_nodes(firstRole), 1, "first");
lastPosition = find(chain.path_nodes == ...
    chain.role_nodes(lastRole), 1, "last");
positions = find(ismember(chain.path_nodes, candidates));
positions = positions(positions > firstPosition & positions < lastPosition);
if ~isempty(positions), witness = chain.path_nodes(positions(1)); end
end

function pass = localSignalReachable(edges, sources, targets)
[pass, ~] = localSignalPath(edges, sources, targets);
end

function [pass, pathNodes] = localSignalPath(edges, sources, targets)
pass = false;
pathNodes = zeros(0, 1);
if isempty(sources) || isempty(targets), return, end
nodeCount = max([edges(:); sources(:); targets(:); 0]);
if nodeCount < 1, return, end
adjacency = cell(nodeCount, 1);
for row = 1:size(edges, 1)
    adjacency{edges(row, 1)}(end + 1) = edges(row, 2); %#ok<AGROW>
end
seen = false(nodeCount, 1);
previous = zeros(nodeCount, 1);
origin = zeros(nodeCount, 1);
queue = unique(sources(:)).';
queue = queue(queue >= 1 & queue <= nodeCount);
seen(queue) = true;
origin(queue) = queue;
targetMask = false(nodeCount, 1);
targets = targets(targets >= 1 & targets <= nodeCount);
targetMask(targets) = true;
for source = queue
    if targetMask(source)
        pass = true;
        pathNodes = source;
        return
    end
end
while ~isempty(queue)
    current = queue(1);
    queue(1) = [];
    for successor = adjacency{current}
        if seen(successor), continue, end
        seen(successor) = true;
        previous(successor) = current;
        origin(successor) = origin(current);
        if targetMask(successor)
            pathNodes = successor;
            while pathNodes(1) ~= origin(successor)
                pathNodes = [previous(pathNodes(1)); pathNodes]; %#ok<AGROW>
            end
            pass = true;
            return
        end
        queue(end + 1) = successor; %#ok<AGROW>
    end
end
end

function output = localPublicOutputUpstream( ...
        edges, nodes, outputName, sinks, roleNames, sourceSets)
rows = repmat(struct( ...
    "role", "", "pass", false, "source_candidates", strings(0, 1), ...
    "path_nodes", strings(0, 1)), numel(roleNames), 1);
for index = 1:numel(roleNames)
    [pass, pathNodes] = localSignalPath(edges, sourceSets{index}, sinks);
    rows(index).role = roleNames(index);
    rows(index).pass = logical(pass);
    rows(index).source_candidates = localNodePaths(nodes, sourceSets{index});
    rows(index).path_nodes = localNodePaths(nodes, pathNodes);
end
output = struct( ...
    "output", outputName, ...
    "sink_blocks", localNodePaths(nodes, sinks), ...
    "role_paths", rows, ...
    "pass", ~isempty(sinks) && all([rows.pass]));
end

function sinks = localPublicOutputSinks(nodes, outputNames)
sinks = struct;
for outputName = reshape(string(outputNames), 1, [])
    sinks.(outputName) = zeros(0, 1);
end
for index = 1:numel(nodes)
    blockType = lower(nodes(index).block_type);
    variable = "";
    if blockType == "toworkspace"
        variable = localGet(nodes(index).path, "VariableName");
    elseif blockType == "outport"
        variable = nodes(index).name;
    end
    for outputName = reshape(string(outputNames), 1, [])
        if variable == outputName
            sinks.(outputName)(end + 1, 1) = index;
        end
    end
end
end

function count = localConnectedOutputCount(sinks)
count = 0;
for field = string(fieldnames(sinks)).'
    count = count + double(~isempty(sinks.(field)));
end
end

function summary = localRoleSummary(nodes, roles, commands, lowCommands, controls)
summary = struct;
for field = string(fieldnames(roles)).'
    summary.(field) = localNodePaths(nodes, roles.(field));
end
summary.public_drive_command_sources = localNodePaths(nodes, commands);
summary.low_remaining_command_sources = localNodePaths(nodes, lowCommands);
summary.control_capability_nodes = localNodePaths(nodes, controls);
end

function witnesses = localFactWitnesses( ...
        edges, nodes, commands, supervisors, controllers, actuators, ...
        speedSensors, detectors, forceSensors, remainingSources)
witnesses = struct( ...
    "command_to_supervisor", localSignalWitness( ...
        edges, nodes, commands, supervisors), ...
    "supervisor_to_motor_controller", localSignalWitness( ...
        edges, nodes, supervisors, controllers), ...
    "motor_controller_to_actuator", localSignalWitness( ...
        edges, nodes, controllers, actuators), ...
    "speed_to_motor_controller", localSignalWitness( ...
        edges, nodes, speedSensors, controllers), ...
    "speed_to_occlusion_detector", localSignalWitness( ...
        edges, nodes, speedSensors, detectors), ...
    "force_to_occlusion_detector", localSignalWitness( ...
        edges, nodes, forceSensors, detectors), ...
    "occlusion_detector_to_supervisor", localSignalWitness( ...
        edges, nodes, detectors, supervisors), ...
    "remaining_to_supervisor", localSignalWitness( ...
        edges, nodes, remainingSources, supervisors));
end

function witness = localSignalWitness(edges, nodes, sources, targets)
[pass, pathNodes] = localSignalPath(edges, sources, targets);
witness = struct( ...
    "pass", logical(pass), ...
    "source_candidates", localNodePaths(nodes, sources), ...
    "target_candidates", localNodePaths(nodes, targets), ...
    "path_nodes", localNodePaths(nodes, pathNodes));
end

function witness = localPhysicalWitnessRows(nodes, chain)
witness = struct( ...
    "pass", logical(chain.pass), ...
    "role_nodes", localNodePaths(nodes, chain.role_nodes), ...
    "path_nodes", localNodePaths(nodes, chain.path_nodes));
end

function paths = localNodePaths(nodes, indices)
indices = unique(indices(:), "stable");
indices = indices(indices >= 1 & indices <= numel(nodes));
if isempty(indices)
    paths = strings(0, 1);
else
    paths = reshape(string({nodes(indices).path}), [], 1);
end
end

function matches = localMatchesTokens(value, tokens)
normalizedValue = localNormalize(value);
tokens = string(tokens);
normalizedTokens = strings(size(tokens));
for index = 1:numel(tokens)
    normalizedTokens(index) = localNormalize(tokens(index));
end
normalizedTokens = normalizedTokens(strlength(normalizedTokens) > 0);
matches = any(contains(normalizedValue, normalizedTokens));
end

function value = localNormalize(value)
value = lower(regexprep(string(value), "[^A-Za-z0-9]", ""));
if ~isscalar(value), value = join(value(:), ""); end
end

function rows = localPortConnectivityRows(block)
% Kept as a named read-only adapter for audit diagnostics and review.
try
    rows = get_param(block, "PortConnectivity");
catch
    rows = struct([]);
end
end

function count = localConnectedPortCount(block, field)
count = 0;
try
    ports = get_param(block, "PortHandles");
catch
    return
end
if ~isfield(ports, field), return, end
for port = reshape(double(ports.(field)), 1, [])
    count = count + double(localPortConnected(port));
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

function ports = localConnectedLinePorts(port)
ports = zeros(0, 1);
try
    line = double(get_param(port, "Line"));
catch
    return
end
if isempty(line) || ~isfinite(line(1)) || line(1) < 0, return, end
line = line(1);
while true
    try
        parent = double(get_param(line, "LineParent"));
    catch
        parent = -1;
    end
    if isempty(parent) || ~isfinite(parent(1)) || parent(1) < 0, break, end
    line = parent(1);
end
lineQueue = line;
lineHandles = zeros(0, 1);
while ~isempty(lineQueue)
    current = lineQueue(1);
    lineQueue(1) = [];
    if any(current == lineHandles), continue, end
    lineHandles(end + 1, 1) = current; %#ok<AGROW>
    try
        children = double(get_param(current, "LineChildren"));
        children = children(isfinite(children) & children >= 0);
        lineQueue = [lineQueue; children(:)]; %#ok<AGROW>
    catch
    end
end
for lineHandle = lineHandles(:).'
    for parameter = ["SrcPortHandle", "DstPortHandle"]
        try
            values = double(get_param(lineHandle, parameter));
            values = values(isfinite(values) & values >= 0 & values ~= port);
            ports = [ports; values(:)]; %#ok<AGROW>
        catch
        end
    end
end
ports = unique(ports, "stable");
end

function row = localConnectionRowForHandle(rows, handle)
row = [];
if isempty(rows), return, end
index = find(double([rows.handle]) == double(handle), 1, "first");
if ~isempty(index), row = rows(index); end
end

function indices = localPhysicalEndpointNodes(nodes, port)
indices = zeros(0, 1);
parentIndex = localNodeIndex(nodes, localParentHandle(port));
if parentIndex <= 0, return, end
parentType = lower(nodes(parentIndex).block_type);
if ~any(parentType == ["subsystem", "modelreference"])
    indices = parentIndex;
    return
end
if parentType == "modelreference", return, end
externalRow = localConnectionRowForHandle( ...
    nodes(parentIndex).connection_ports, port);
if isempty(externalRow), return, end
for index = 1:numel(nodes)
    if nodes(index).parent ~= nodes(parentIndex).path || ...
            lower(nodes(index).block_type) ~= "pmioport"
        continue
    end
    childPort = localNumericBlockParameter(nodes(index).path, "Port");
    childSide = localNormalize(localGet(nodes(index).path, "Side"));
    expectedSide = localNormalize(externalRow.side);
    ordinalMatch = isfinite(childPort) && ...
        childPort == double(externalRow.ordinal);
    sideMatch = (contains(childSide, "left") && ...
        contains(expectedSide, "lconn")) || ...
        (contains(childSide, "right") && ...
        contains(expectedSide, "rconn"));
    nameMatch = localNormalize(nodes(index).name) == ...
        localNormalize(externalRow.name) || ...
        localNormalize(nodes(index).name) == ...
        localNormalize(externalRow.label);
    if (ordinalMatch && sideMatch) || ...
            (nameMatch && strlength(localNormalize(nodes(index).name)) > 0)
        indices(end + 1, 1) = index; %#ok<AGROW>
    end
end
indices = unique(indices, "stable");
end

function value = localNumericPortParameter(port, parameter)
value = nan;
try
    item = get_param(port, parameter);
    if isnumeric(item) && isscalar(item)
        value = double(item);
    else
        value = str2double(string(item));
    end
catch
end
end

function value = localNumericBlockParameter(block, parameter)
value = nan;
try
    item = get_param(block, parameter);
    if isnumeric(item) && isscalar(item)
        value = double(item);
    else
        value = str2double(string(item));
    end
catch
end
end

function value = localStandardPortOrdinal(block, port, field)
value = nan;
try
    handles = get_param(block, "PortHandles");
    if ~isfield(handles, field), return, end
    match = find(double(handles.(field)) == double(port), 1, "first");
    if ~isempty(match), value = double(match); end
catch
end
end

function handle = localParentHandle(port)
handle = -1;
try
    parent = get_param(port, "Parent");
    handle = double(get_param(parent, "Handle"));
catch
end
end

function index = localNodeIndex(nodes, handle)
index = 0;
if isempty(handle) || ~isfinite(double(handle)), return, end
match = find(double([nodes.handle]) == double(handle), 1, "first");
if ~isempty(match), index = match; end
end

function index = localNodePathIndex(nodes, pathValue)
index = 0;
if strlength(pathValue) == 0, return, end
match = find(string({nodes.path}) == string(pathValue), 1, "first");
if ~isempty(match), index = match; end
end

function value = localGet(block, parameter)
value = "";
try
    value = string(get_param(block, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
catch
end
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function rows = localOutputs
rows = localRows(["motion_state", "delivery_state", "safety_state"], ...
    [4, 4, 4]);
rows(3).interpolation = "previous";
end

function inputs = localInputs(scenario, ~)
inputs = rmfield(scenario, intersect(fieldnames(scenario), ...
    {"id", "class", "stop_time_s"}));
end

function requested = localRequested(scenario, ~)
requested = rmfield(scenario, intersect(fieldnames(scenario), ...
    {"id", "class"}));
end

function row = localPostprocess(row, outputs, scenario, ~)
t = double(outputs.time_s(:));
motion = double(outputs.motion_state);
delivery = double(outputs.delivery_state);
safety = double(outputs.safety_state);
reference = motion(:, 1);
speed = motion(:, 2);
voltage = motion(:, 3);
piston = motion(:, 4);
upstream = delivery(:, 1);
patientFlow = delivery(:, 2);
pressure = delivery(:, 3);
patientUnits = delivery(:, 4);
force = safety(:, 1);
alarm = safety(:, 2);
remaining = safety(:, 4);
upstreamUnits = cumtrapz(t, max(upstream, 0)) / 60 / 15;
outputs.derived = struct("upstream_cumulative_units", upstreamUnits);
active = abs(reference) > max(1, 0.02 * max(abs(reference)));
if nnz(active) >= 2
    rmse = sqrt(mean((speed(active) - reference(active)).^2));
    relative = rmse / max(sqrt(mean(reference(active).^2)), eps);
    p95 = localPercentile(abs(speed(active) - reference(active)), 95);
else
    rmse = 0;
    relative = 0;
    p95 = 0;
end
area = pi * (0.4720 * 25.4)^2 / 4;
volumePerUnit = 15;
pistonUnits = max(0, (piston(end) - piston(1)) * area / volumePerUnit);
lead = (1 / 24) * 25.4 / 216;
target = trapz(t, max(reference, 0)) / 60 * lead * area / volumePerUnit;
alarmOnset = localFirst(t, alarm > 0.5, 0);
if isfinite(alarmOnset)
    alarmIndex = find(t >= alarmOnset, 1);
    postUnits = patientUnits(end) - patientUnits(alarmIndex);
    mask = t >= alarmOnset + 2;
    if any(mask), postReference = max(abs(reference(mask)));
    else, postReference = nan;
    end
else
    postUnits = nan;
    postReference = nan;
end
row.metrics = struct( ...
    "reference_speed_peak_RPM", max(abs(reference)), ...
    "measured_speed_peak_RPM", max(abs(speed)), ...
    "motor_tracking_rmse_RPM", rmse, ...
    "motor_tracking_relative_rmse", relative, ...
    "motor_tracking_p95_error_RPM", p95, ...
    "motor_voltage_peak_V", max(abs(voltage)), ...
    "active_delivery_transition_count", ...
        sum(diff(double(active)) == 1), ...
    "target_motion_equivalent_units", target, ...
    "upstream_delivered_units", upstreamUnits(end), ...
    "patient_delivered_units", patientUnits(end), ...
    "piston_displacement_equivalent_units", pistonUnits, ...
    "patient_to_target_relative_error", ...
        abs(patientUnits(end) - target) / max(target, 1e-9), ...
    "piston_to_target_relative_error", ...
        abs(pistonUnits - target) / max(target, 1e-9), ...
    "patient_to_piston_relative_error", ...
        abs(patientUnits(end) - pistonUnits) / max(pistonUnits, 1e-9), ...
    "upstream_to_patient_relative_error", ...
        abs(upstreamUnits(end) - patientUnits(end)) / ...
        max(upstreamUnits(end), 1e-9), ...
    "patient_flow_mean_active_mm3_per_min", ...
        localMean(patientFlow(active)), ...
    "patient_flow_peak_mm3_per_min", max(patientFlow), ...
    "line_pressure_peak_Pa", max(pressure), ...
    "line_pressure_final_Pa", pressure(end), ...
    "load_force_peak_N", max(force), ...
    "occlusion_alarm_onset_s", alarmOnset, ...
    "occlusion_detection_delay_s", ...
        alarmOnset - double(scenario.occlusion_onset_s), ...
    "post_alarm_delivered_units", postUnits, ...
    "post_alarm_reference_speed_max_RPM", postReference, ...
    "alarm_fraction", mean(alarm > 0.5), ...
    "remaining_units_initial", remaining(1), ...
    "remaining_units_final", remaining(end), ...
    "remaining_units_change", remaining(end) - remaining(1), ...
    "commanded_mode", double(scenario.delivery_mode), ...
    "requested_basal_rate_units_per_hour", ...
        double(scenario.basal_rate_units_per_hour), ...
    "requested_occlusion_fraction", double(scenario.occlusion_fraction));
row.outputs = outputs;
row.valid = row.output_contract.all_required_pass;
end

function value = localMean(values)
if isempty(values), value = nan; else, value = mean(values); end
end

function value = localFirst(time, mask, threshold)
index = find(mask & time >= threshold, 1);
if isempty(index), value = nan; else, value = time(index); end
end

function value = localPercentile(values, percentile)
values = sort(double(values(:)));
if isempty(values), value = nan; return, end
position = 1 + (numel(values) - 1) * percentile / 100;
lowerIndex = floor(position);
upperIndex = ceil(position);
value = values(lowerIndex) + ...
    (position - lowerIndex) * (values(upperIndex) - values(lowerIndex));
end

function rows = localRows(names, widths)
rows = repmat(struct( ...
    "name", "", "evidence_name", "", "width", 0, ...
    "interpolation", "linear"), numel(names), 1);
for index = 1:numel(names)
    rows(index).name = names(index);
    rows(index).evidence_name = names(index);
    rows(index).width = widths(index);
end
end

function [taskRoot, sharedRoot] = localRoots(taskId)
scriptRoot = fileparts(mfilename("fullpath"));
tasksRoot = fileparts(scriptRoot);
sharedRoot = fullfile(tasksRoot, "_shared");
repoRoot = tasksRoot;
for level = 1:3, repoRoot = fileparts(repoRoot); end
taskRoot = string(getenv("SIMUVERITY_TASK_ROOT"));
end
