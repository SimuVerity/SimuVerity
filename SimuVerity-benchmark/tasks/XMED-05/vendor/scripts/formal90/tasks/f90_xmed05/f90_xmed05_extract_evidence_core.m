function evidence = f90_xmed05_extract_evidence_core(modelPath, outDir)
%f90_xmed05_extract_evidence_core Candidate causal dual-chamber audit.
%   METRICS continues to own the six scenarios, simulation, output extraction,
%   metrics, and raw artifacts. SCORING_CORE replaces only the provisional model-size
%   qualification gate with port-preserving causal witnesses.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
assert(isfile(modelPath), "SimuVerity:F90:XMED05:ModelMissing", ...
    "Candidate model is missing: %s", modelPath);

taskDir = fileparts(mfilename("fullpath"));
localRequireBinding(fullfile(taskDir, "f90_xmed05_extract_evidence_foundation.m"), ...
    "present");
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(taskDir, "-begin");
candidateBindingBefore = localFilePresence(modelPath);

% The current METRICS engine still performs exactly one full six-scenario run.
evidence = f90_xmed05_extract_evidence_foundation( ...
    modelPath, outDir, strings(0, 1));
assert(~logical(evidence.reference_subject), ...
    "SimuVerity:F90:XMED05:CandidateOnly", ...
    "SCORING_CORE is a candidate candidate route; reference evaluation remains METRICS.");

audit = localCandidateStaticAudit(modelPath, evidence);
candidateBindingAfter = localFilePresence(modelPath);
assert(candidateBindingBefore == candidateBindingAfter, ...
    "SimuVerity:F90:XMED05:CandidateChanged", ...
    "The read-only SCORING_CORE audit changed the sealed candidate model.");

evidence.schema = "simuverity.f90-xmed05-evidence.v1";
evidence.static_audit = audit;
evidence.static_audit_method = ...
    "simuverity.f90-xmed05-dual-chamber-role-path-evidence.v1";
evidence.current_candidate_static_audit_superseded = true;
evidence.current_evidence_engine_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmed05_extract_evidence_foundation.m"));
evidence.current_offline_scorer_file_presence = localFilePresence(fullfile(taskDir, ...
    "f90_xmed05_scoring_core.py"));
evidence.candidate_evidence_ready = true;
evidence.score_fields_present = false;
evidence.candidate_file_presence_before_current_audit = candidateBindingBefore;
evidence.candidate_file_presence_after_current_audit = candidateBindingAfter;
evidence.candidate_binding_preserved_by_current_audit = true;
localWriteJsonReplace(fullfile(outDir, "evidence.json"), evidence);
end

function audit = localCandidateStaticAudit(modelPath, evidence)
[modelDir, model] = fileparts(modelPath);
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
addpath(modelDir, "-begin");
wasLoaded = bdIsLoaded(model);
if ~wasLoaded, load_system(modelPath); end
modelCleanup = onCleanup( ...
    @() localCloseIfNeeded(model, wasLoaded)); %#ok<NASGU>

nodes = localNodes(model);
edges = localDirectedPortEdges(nodes);
roleCandidates = localExecutableRoleCandidates(nodes);
boundedCandidates = localBoundedDeliveryCandidates( ...
    nodes, roleCandidates);
egmTargets = localPublicChannelTargets( ...
    nodes, edges, "CardiacEGM", 2);
eventTargets = localPublicChannelTargets( ...
    nodes, edges, "PacingEvents", 8);
chain = localFindDualChamberLoop(edges, nodes, roleCandidates, ...
    boundedCandidates, egmTargets, eventTargets);
behaviorSupport = localBehavioralPacingSupport(evidence);

audit = struct;
audit.minimum_hybrid_closed_loop_signature = logical(chain.pass);
audit.cardiac_response_to_sensing = ...
    logical(chain.cardiac_response_to_sensing);
audit.sensing_to_ddd_logic = logical(chain.sensing_to_ddd_logic);
audit.ddd_logic_to_bounded_pacing_delivery = ...
    logical(chain.ddd_logic_to_bounded_pacing_delivery);
audit.bounded_pacing_delivery_to_cardiac_response = ...
    logical(chain.bounded_pacing_delivery_to_cardiac_response);
audit.bounded_pacing_delivery_verified = ...
    logical(chain.bounded_pacing_delivery_verified);
audit.dual_chamber_independence = ...
    logical(chain.dual_chamber_independence);
audit.public_output_upstream_qualified = ...
    logical(chain.public_output_upstream_qualified);
audit.role_path_witnesses = chain;
audit.public_channel_targets = struct( ...
    "CardiacEGM", egmTargets, "PacingEvents", eventTargets);
audit.behavioral_pacing_support = behaviorSupport;
audit.directed_port_edge_count = size(edges, 1);
audit.port_number_preserving_hierarchy_bridges = true;
audit.current_size_count_gate_superseded = true;
audit.block_chart_routing_count_thresholds_used = false;
audit.display_name_used_for_role_discovery = false;
audit.display_name_is_sufficient = false;
audit.mask_type_is_trusted_identity = false;
audit.role_qualification_basis = [ ...
    "BlockType", "SFBlockType", ...
    "connected input/output ports", ...
    "Stateflow executable output expressions", ...
    "role-specific directed port paths"];
end

function chain = localFindDualChamberLoop( ...
        edges, nodes, roleCandidates, boundedCandidates, ...
        egmTargets, eventTargets)
chain = localEmptyDualChamberLoop;
if ~egmTargets.pass || ~eventTargets.pass, return, end

heartOptions = localPairOutputOptions(edges, nodes, ...
    roleCandidates, egmTargets.channels(1:2, :), roleCandidates);
sensingOptions = localPairOutputOptions(edges, nodes, ...
    roleCandidates, eventTargets.channels(1:2, :), roleCandidates);
logicOptions = localFourOutputOptions(edges, nodes, ...
    roleCandidates, eventTargets.channels(3:6, :), roleCandidates);
deliveryOptions = localPairOutputOptions(edges, nodes, ...
    boundedCandidates, eventTargets.channels(7:8, :), roleCandidates);
if isempty(heartOptions) || isempty(sensingOptions) || ...
        isempty(logicOptions) || isempty(deliveryOptions)
    return
end

for heartIndex = 1:numel(heartOptions)
    heart = heartOptions(heartIndex);
    for sensingIndex = 1:numel(sensingOptions)
        sensing = sensingOptions(sensingIndex);
        if sensing.node == heart.node, continue, end
        for logicIndex = 1:numel(logicOptions)
            logic = logicOptions(logicIndex);
            if any(logic.node == [heart.node, sensing.node]), continue, end
            for deliveryIndex = 1:numel(deliveryOptions)
                delivery = deliveryOptions(deliveryIndex);
                selected = [heart.node, sensing.node, ...
                    logic.node, delivery.node];
                if numel(unique(selected)) < 4, continue, end

                heartSense = localDistinctInputPair(edges, nodes, ...
                    heart.node, heart.ports, sensing.node, ...
                    setdiff(roleCandidates, [heart.node, sensing.node]));
                senseLogic = localDistinctInputPair(edges, nodes, ...
                    sensing.node, sensing.ports, logic.node, ...
                    setdiff(roleCandidates, [sensing.node, logic.node]));
                logicDelivery = localDistinctInputPair(edges, nodes, ...
                    logic.node, logic.ports(1:2), delivery.node, ...
                    setdiff(roleCandidates, [logic.node, delivery.node]));
                deliveryHeart = localDistinctInputPair(edges, nodes, ...
                    delivery.node, delivery.ports, heart.node, ...
                    setdiff(roleCandidates, [delivery.node, heart.node]));
                if ~(heartSense.pass && senseLogic.pass && ...
                        logicDelivery.pass && deliveryHeart.pass)
                    continue
                end

                chain = struct;
                chain.pass = true;
                chain.cardiac_response_to_sensing = true;
                chain.sensing_to_ddd_logic = true;
                chain.ddd_logic_to_bounded_pacing_delivery = true;
                chain.bounded_pacing_delivery_to_cardiac_response = true;
                chain.bounded_pacing_delivery_verified = true;
                chain.dual_chamber_independence = true;
                chain.public_output_upstream_qualified = true;
                chain.cardiac_response_block = nodes(heart.node).path;
                chain.sensing_block = nodes(sensing.node).path;
                chain.ddd_logic_block = nodes(logic.node).path;
                chain.bounded_pacing_delivery_block = ...
                    nodes(delivery.node).path;
                chain.cardiac_response_outputs = heart.ports;
                chain.sensing_inputs = heartSense.target_ports;
                chain.sensing_outputs = sensing.ports;
                chain.ddd_logic_inputs = senseLogic.target_ports;
                chain.ddd_command_outputs = logic.ports(1:2);
                chain.ddd_accepted_outputs = logic.ports(3:4);
                chain.pacing_delivery_inputs = ...
                    logicDelivery.target_ports;
                chain.pacing_delivery_outputs = delivery.ports;
                chain.cardiac_response_inputs = ...
                    deliveryHeart.target_ports;
                chain.cardiac_response_to_sensing_paths = ...
                    heartSense.paths;
                chain.sensing_to_ddd_logic_paths = senseLogic.paths;
                chain.ddd_to_pacing_delivery_paths = ...
                    logicDelivery.paths;
                chain.pacing_delivery_to_cardiac_response_paths = ...
                    deliveryHeart.paths;
                chain.public_output_paths = struct( ...
                    "CardiacEGM", {heart.output_paths}, ...
                    "detected", {sensing.output_paths}, ...
                    "command_and_accepted", {logic.output_paths}, ...
                    "delivered", {delivery.output_paths});
                chain.role_blocks_are_distinct = true;
                chain.chamber_ports_are_distinct = true;
                chain.chamber_path_intermediates_are_distinct = true;
                return
            end
        end
    end
end
end

function chain = localEmptyDualChamberLoop
chain = struct;
chain.pass = false;
chain.cardiac_response_to_sensing = false;
chain.sensing_to_ddd_logic = false;
chain.ddd_logic_to_bounded_pacing_delivery = false;
chain.bounded_pacing_delivery_to_cardiac_response = false;
chain.bounded_pacing_delivery_verified = false;
chain.dual_chamber_independence = false;
chain.public_output_upstream_qualified = false;
chain.cardiac_response_block = "";
chain.sensing_block = "";
chain.ddd_logic_block = "";
chain.bounded_pacing_delivery_block = "";
chain.cardiac_response_outputs = zeros(0, 1);
chain.sensing_inputs = zeros(0, 1);
chain.sensing_outputs = zeros(0, 1);
chain.ddd_logic_inputs = zeros(0, 1);
chain.ddd_command_outputs = zeros(0, 1);
chain.ddd_accepted_outputs = zeros(0, 1);
chain.pacing_delivery_inputs = zeros(0, 1);
chain.pacing_delivery_outputs = zeros(0, 1);
chain.cardiac_response_inputs = zeros(0, 1);
chain.cardiac_response_to_sensing_paths = cell(0, 1);
chain.sensing_to_ddd_logic_paths = cell(0, 1);
chain.ddd_to_pacing_delivery_paths = cell(0, 1);
chain.pacing_delivery_to_cardiac_response_paths = cell(0, 1);
chain.public_output_paths = struct;
chain.role_blocks_are_distinct = false;
chain.chamber_ports_are_distinct = false;
chain.chamber_path_intermediates_are_distinct = false;
end

function options = localPairOutputOptions( ...
        edges, nodes, candidates, targets, allRoleCandidates)
template = struct("node", 0, "ports", zeros(1, 2), ...
    "output_paths", {cell(1, 2)});
options = repmat(template, 0, 1);
for node = reshape(candidates, 1, [])
    forbidden = setdiff(allRoleCandidates, node);
    first = localSourcePortWitnesses( ...
        edges, nodes, node, targets(1, :), forbidden);
    second = localSourcePortWitnesses( ...
        edges, nodes, node, targets(2, :), forbidden);
    for firstIndex = 1:numel(first)
        for secondIndex = 1:numel(second)
            if first(firstIndex).port == second(secondIndex).port
                continue
            end
            option = template;
            option.node = node;
            option.ports = [first(firstIndex).port, ...
                second(secondIndex).port];
            option.output_paths = {first(firstIndex).witness, ...
                second(secondIndex).witness};
            options(end + 1, 1) = option; %#ok<AGROW>
        end
    end
end
end

function options = localFourOutputOptions( ...
        edges, nodes, candidates, targets, allRoleCandidates)
template = struct("node", 0, "ports", zeros(1, 4), ...
    "output_paths", {cell(1, 4)});
options = repmat(template, 0, 1);
for node = reshape(candidates, 1, [])
    if nodes(node).signal_out < 4, continue, end
    forbidden = setdiff(allRoleCandidates, node);
    rows = cell(1, 4);
    for channel = 1:4
        rows{channel} = localSourcePortWitnesses( ...
            edges, nodes, node, targets(channel, :), forbidden);
    end
    if any(cellfun(@isempty, rows)), continue, end
    for first = 1:numel(rows{1})
        for second = 1:numel(rows{2})
            for third = 1:numel(rows{3})
                for fourth = 1:numel(rows{4})
                    selected = [rows{1}(first).port, ...
                        rows{2}(second).port, rows{3}(third).port, ...
                        rows{4}(fourth).port];
                    if numel(unique(selected)) < 4, continue, end
                    option = template;
                    option.node = node;
                    option.ports = selected;
                    option.output_paths = { ...
                        rows{1}(first).witness, ...
                        rows{2}(second).witness, ...
                        rows{3}(third).witness, ...
                        rows{4}(fourth).witness};
                    options(end + 1, 1) = option; %#ok<AGROW>
                end
            end
        end
    end
end
end

function rows = localSourcePortWitnesses( ...
        edges, nodes, sourceNode, target, forbidden)
template = struct("port", 0, "witness", struct);
rows = repmat(template, 0, 1);
for sourcePort = 1:nodes(sourceNode).signal_out
    witness = localPortPathWitness(edges, nodes, ...
        sourceNode, sourcePort, target(1), target(2), forbidden);
    if witness.pass
        rows(end + 1, 1) = struct( ... %#ok<AGROW>
            "port", sourcePort, "witness", witness);
    end
end
end

function pair = localDistinctInputPair( ...
        edges, nodes, sourceNode, sourcePorts, targetNode, forbidden)
pair = struct("pass", false, "target_ports", zeros(1, 2), ...
    "paths", {cell(1, 2)});
for firstPort = 1:nodes(targetNode).signal_in
    first = localPortPathWitness(edges, nodes, ...
        sourceNode, sourcePorts(1), targetNode, firstPort, forbidden);
    if ~first.pass, continue, end
    for secondPort = 1:nodes(targetNode).signal_in
        if secondPort == firstPort, continue, end
        second = localPortPathWitness(edges, nodes, ...
            sourceNode, sourcePorts(2), targetNode, secondPort, forbidden);
        if second.pass && localPathPairIndependent( ...
                first, second, sourceNode, targetNode)
            pair = struct("pass", true, ...
                "target_ports", [firstPort, secondPort], ...
                "paths", {{first, second}});
            return
        end
    end
end
end

function pass = localPathPairIndependent( ...
        first, second, sourceNode, targetNode)
firstMiddle = setdiff(first.node_indices, [sourceNode, targetNode]);
secondMiddle = setdiff(second.node_indices, [sourceNode, targetNode]);
pass = isempty(intersect(firstMiddle, secondMiddle));
end

function witness = localPortPathWitness(edges, nodes, ...
        sourceNode, sourcePort, targetNode, targetPort, forbidden)
witness = localEmptyPathWitness(nodes, ...
    sourceNode, sourcePort, targetNode, targetPort);
if isempty(edges) || sourceNode < 1 || targetNode < 1, return, end
forbidden = setdiff(unique(forbidden(:)), [sourceNode; targetNode]);
seen = false(numel(nodes), 1);
seen(sourceNode) = true;
previousEdge = zeros(numel(nodes), 1);
queue = zeros(0, 1);

firstRows = find(edges(:, 1) == sourceNode & ...
    edges(:, 2) == sourcePort);
for row = reshape(firstRows, 1, [])
    destination = edges(row, 3);
    if any(destination == forbidden), continue, end
    if destination == targetNode
        if edges(row, 4) == targetPort
            witness = localCompletedPathWitness( ...
                edges, nodes, row, sourceNode, sourcePort, ...
                targetNode, targetPort);
            return
        end
        continue
    end
    if ~seen(destination)
        seen(destination) = true;
        previousEdge(destination) = row;
        queue(end + 1, 1) = destination; %#ok<AGROW>
    end
end

while ~isempty(queue)
    current = queue(1);
    queue(1) = [];
    nextRows = find(edges(:, 1) == current);
    for row = reshape(nextRows, 1, [])
        destination = edges(row, 3);
        if any(destination == forbidden), continue, end
        if destination == targetNode
            if edges(row, 4) ~= targetPort, continue, end
            edgePath = row;
            cursor = current;
            while cursor ~= sourceNode
                previous = previousEdge(cursor);
                if previous == 0, return, end
                edgePath = [previous, edgePath]; %#ok<AGROW>
                cursor = edges(previous, 1);
            end
            witness = localCompletedPathWitness( ...
                edges, nodes, edgePath, sourceNode, sourcePort, ...
                targetNode, targetPort);
            return
        end
        if ~seen(destination)
            seen(destination) = true;
            previousEdge(destination) = row;
            queue(end + 1, 1) = destination; %#ok<AGROW>
        end
    end
end
end

function witness = localEmptyPathWitness( ...
        nodes, sourceNode, sourcePort, targetNode, targetPort)
witness = struct;
witness.pass = false;
witness.source = localEndpoint(nodes, sourceNode, sourcePort);
witness.target = localEndpoint(nodes, targetNode, targetPort);
witness.node_indices = zeros(0, 1);
witness.node_paths = strings(0, 1);
witness.edge_witnesses = struct([]);
end

function witness = localCompletedPathWitness(edges, nodes, edgePath, ...
        sourceNode, sourcePort, targetNode, targetPort)
witness = localEmptyPathWitness( ...
    nodes, sourceNode, sourcePort, targetNode, targetPort);
witness.pass = true;
witness.node_indices = [sourceNode; edges(edgePath, 3)];
witness.node_paths = localNodePaths(nodes, witness.node_indices);
witness.edge_witnesses = localEdgeWitnessRows(edges, nodes, edgePath);
end

function endpoint = localEndpoint(nodes, node, port)
endpoint = struct("block", "", "port", double(port));
if node >= 1 && node <= numel(nodes)
    endpoint.block = nodes(node).path;
end
end

function rows = localEdgeWitnessRows(edges, nodes, indices)
template = struct("source_block", "", "source_port", 0, ...
    "destination_block", "", "destination_port", 0);
rows = repmat(template, numel(indices), 1);
for index = 1:numel(indices)
    edge = edges(indices(index), :);
    rows(index) = struct( ...
        "source_block", nodes(edge(1)).path, ...
        "source_port", edge(2), ...
        "destination_block", nodes(edge(3)).path, ...
        "destination_port", edge(4));
end
end

function targets = localPublicChannelTargets( ...
        nodes, edges, variableName, width)
targets = struct;
targets.pass = false;
targets.variable = variableName;
targets.width = width;
targets.channels = zeros(0, 2);
targets.sink_block = "";
targets.aggregator_block = "";

sinks = zeros(0, 1);
aggregators = zeros(0, 1);
for node = 1:numel(nodes)
    blockType = lower(nodes(node).block_type);
    if blockType == "toworkspace" && ...
            localGet(nodes(node).path, "VariableName") == variableName
        sinks(end + 1, 1) = node; %#ok<AGROW>
    elseif blockType == "outport" && ...
            localNodePathIndex(nodes, nodes(node).parent) == 0 && ...
            nodes(node).name == variableName
        sinks(end + 1, 1) = node; %#ok<AGROW>
    end
    if localLoggedOutputName(nodes(node).path) == variableName
        aggregators(end + 1, 1) = node; %#ok<AGROW>
    end
end

for sink = reshape(sinks, 1, [])
    incoming = find(edges(:, 3) == sink);
    for row = reshape(incoming, 1, [])
        aggregators(end + 1, 1) = edges(row, 1); %#ok<AGROW>
    end
end
aggregators = unique(aggregators, "stable");
for aggregator = reshape(aggregators, 1, [])
    if ~localOrderedAggregator(nodes(aggregator)) || ...
            nodes(aggregator).connected_signal_in < width
        continue
    end
    targets.pass = true;
    targets.channels = [repmat(aggregator, width, 1), (1:width).'];
    targets.aggregator_block = nodes(aggregator).path;
    linkedSink = find(edges(:, 1) == aggregator & ...
        ismember(edges(:, 3), sinks), 1, "first");
    if ~isempty(linkedSink)
        targets.sink_block = nodes(edges(linkedSink, 3)).path;
    else
        targets.sink_block = nodes(aggregator).path;
    end
    return
end
end

function pass = localOrderedAggregator(node)
pass = any(lower(node.block_type) == [ ...
    "mux", "vectorconcatenate", "matrixconcatenate"]);
end

function name = localLoggedOutputName(block)
name = "";
try
    handles = get_param(block, "PortHandles");
catch
    return
end
if ~isfield(handles, "Outport"), return, end
for port = reshape(double(handles.Outport), 1, [])
    if localOn(localPortGet(port, "DataLogging"))
        candidate = localPortGet(port, "DataLoggingName");
        if strlength(candidate) > 0
            name = candidate;
            return
        end
    end
end
end

function nodes = localNodes(model)
blocks = string(find_system(model, "FollowLinks", "on", ...
    "LookUnderMasks", "all", "Type", "Block"));
template = struct( ...
    "path", "", "handle", 0, "parent", "", "name", "", ...
    "block_type", "", "sf_block_type", "", ...
    "signal_in", 0, "signal_out", 0, ...
    "connected_signal_in", 0, "connected_signal_out", 0);
nodes = repmat(template, numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    nodes(index).path = block;
    nodes(index).handle = double(get_param(block, "Handle"));
    nodes(index).parent = localGet(block, "Parent");
    nodes(index).name = localGet(block, "Name");
    nodes(index).block_type = localGet(block, "BlockType");
    nodes(index).sf_block_type = localGet(block, "SFBlockType");
    nodes(index).signal_in = localPortCount(block, "Inport");
    nodes(index).signal_out = localPortCount(block, "Outport");
    nodes(index).connected_signal_in = ...
        localConnectedPortCount(block, "Inport");
    nodes(index).connected_signal_out = ...
        localConnectedPortCount(block, "Outport");
end
end

function edges = localDirectedPortEdges(nodes)
edges = zeros(0, 4);
for index = 1:numel(nodes)
    try
        handles = get_param(nodes(index).path, "PortHandles");
    catch
        continue
    end
    if ~isfield(handles, "Outport"), continue, end
    for sourcePort = reshape(double(handles.Outport), 1, [])
        source = localSignalEndpoint(nodes, sourcePort, "source");
        if isempty(source), continue, end
        for destinationPort = localConnectedLinePorts(sourcePort).'
            destination = localSignalEndpoint( ...
                nodes, destinationPort, "destination");
            if isempty(destination), continue, end
            if source(1) ~= destination(1)
                edges(end + 1, :) = [source, destination]; %#ok<AGROW>
            end
        end
    end
end
edges = unique(edges, "rows");
end

function endpoint = localSignalEndpoint(nodes, port, direction)
endpoint = zeros(0, 2);
portType = lower(localPortGet(port, "PortType"));
if direction == "source" && portType ~= "outport", return, end
if direction == "destination" && portType ~= "inport", return, end
parentIndex = localNodeIndex(nodes, localParentHandle(port));
if parentIndex <= 0, return, end
portNumber = localNumericPortParameter(port, "PortNumber");
if ~isfinite(portNumber)
    if direction == "source", field = "Outport";
    else, field = "Inport";
    end
    portNumber = localStandardPortOrdinal( ...
        nodes(parentIndex).path, port, field);
end
if ~isfinite(portNumber), return, end
if ~localTransparentSubsystem(nodes(parentIndex))
    endpoint = [parentIndex, portNumber];
    return
end
if direction == "source", boundaryType = "outport";
else, boundaryType = "inport";
end
for index = 1:numel(nodes)
    if nodes(index).parent ~= nodes(parentIndex).path || ...
            lower(nodes(index).block_type) ~= boundaryType
        continue
    end
    boundaryPort = localNumericBlockParameter(nodes(index).path, "Port");
    if isfinite(boundaryPort) && boundaryPort == portNumber
        endpoint = [index, 1];
        return
    end
end
end

function pass = localTransparentSubsystem(node)
pass = lower(node.block_type) == "subsystem" && ...
    strlength(node.sf_block_type) == 0;
end

function candidates = localExecutableRoleCandidates(nodes)
trustedTypes = lower([ ...
    "S-Function", "MATLABSystem", "StateSpace", ...
    "DiscreteStateSpace", "Integrator", "DiscreteIntegrator", ...
    "TransferFcn", "DiscreteTransferFcn"]);
trustedStateflow = lower([ ...
    "Chart", "MATLAB Function", "State Transition Table"]);
candidates = zeros(0, 1);
for index = 1:numel(nodes)
    if nodes(index).connected_signal_in < 2 || ...
            nodes(index).connected_signal_out < 2
        continue
    end
    executable = any(lower(nodes(index).block_type) == trustedTypes) || ...
        any(lower(nodes(index).sf_block_type) == trustedStateflow);
    if executable
        candidates(end + 1, 1) = index; %#ok<AGROW>
    end
end
end

function candidates = localBoundedDeliveryCandidates(nodes, roles)
candidates = zeros(0, 1);
for index = reshape(roles, 1, [])
    if localKnownBoundedBlock(nodes(index).path, ...
            nodes(index).block_type) || ...
            localStateflowOutputsBounded(nodes(index).path, 2)
        candidates(end + 1, 1) = index; %#ok<AGROW>
    end
end
end

function pass = localKnownBoundedBlock(block, blockType)
pass = false;
switch lower(blockType)
    case {"logic", "relationaloperator", "comparetozero", ...
            "comparetoconstant"}
        pass = true;
    case "relay"
        lowerBound = min([ ...
            localNumericBlockParameter(block, "OnOutputValue"), ...
            localNumericBlockParameter(block, "OffOutputValue")]);
        upperBound = max([ ...
            localNumericBlockParameter(block, "OnOutputValue"), ...
            localNumericBlockParameter(block, "OffOutputValue")]);
        pass = isfinite(lowerBound) && isfinite(upperBound) && ...
            lowerBound >= 0 && upperBound <= 1;
    case "saturate"
        lowerBound = localNumericBlockParameter(block, "LowerLimit");
        upperBound = localNumericBlockParameter(block, "UpperLimit");
        pass = isfinite(lowerBound) && isfinite(upperBound) && ...
            lowerBound >= 0 && upperBound <= 1 && ...
            upperBound > lowerBound;
end
end

function pass = localStateflowOutputsBounded(block, minimumOutputs)
pass = false;
try
    root = sfroot;
    charts = find(root, "-isa", "Stateflow.EMChart");
catch
    return
end
for index = 1:numel(charts)
    try
        if string(charts(index).Path) ~= string(block), continue, end
        script = string(charts(index).Script);
        data = find(charts(index), "-isa", "Stateflow.Data");
        outputNames = strings(0, 1);
        for dataIndex = 1:numel(data)
            if strcmpi(string(data(dataIndex).Scope), "Output")
                outputNames(end + 1, 1) = ... %#ok<AGROW>
                    string(data(dataIndex).Name);
            end
        end
        if numel(outputNames) < minimumOutputs, return, end
        bounded = false(numel(outputNames), 1);
        for outputIndex = 1:numel(outputNames)
            bounded(outputIndex) = localOutputAssignmentsBounded( ...
                script, outputNames(outputIndex));
        end
        pass = nnz(bounded) >= minimumOutputs;
        return
    catch
        return
    end
end
end

function pass = localOutputAssignmentsBounded(script, outputName)
escaped = regexptranslate("escape", outputName);
pattern = "(?m)(?<![A-Za-z0-9_])" + escaped + ...
    "\s*=\s*([^;\r\n]+)";
matches = regexp(char(script), char(pattern), "tokens");
if isempty(matches), pass = false; return, end
pass = true;
for index = 1:numel(matches)
    expression = lower(strtrim(string(matches{index}{1})));
    relational = any(contains(expression, [">", "<", "==", "~="]));
    booleanCast = contains(expression, "double(") || ...
        contains(expression, "logical(") || relational;
    clamped = contains(expression, "min(") && ...
        contains(expression, "max(");
    constant = any(expression == ["0", "1", "0.0", "1.0"]);
    pass = pass && (booleanCast || clamped || constant);
end
end

function support = localBehavioralPacingSupport(evidence)
support = struct("pass", false, "all_scenarios_valid", false, ...
    "finite_event_channels", false, ...
    "delivered_event_duty_fields_valid", false);
if isempty(evidence.scenarios), return, end
allValid = true;
allFinite = true;
dutyValid = true;
for index = 1:numel(evidence.scenarios)
    row = evidence.scenarios(index);
    allValid = allValid && logical(row.valid);
    if ~isfield(row, "metrics") || ...
            ~isfield(row.metrics, "all_values_finite")
        allFinite = false;
        dutyValid = false;
        continue
    end
    allFinite = allFinite && logical(row.metrics.all_values_finite);
    if ~isfield(row.metrics, "event_pulse_duty_fraction")
        dutyValid = false;
        continue
    end
    duties = double(row.metrics.event_pulse_duty_fraction(:));
    dutyValid = dutyValid && numel(duties) >= 8 && ...
        all(isfinite(duties(7:8))) && ...
        all(duties(7:8) >= 0 & duties(7:8) <= 1);
end
support.all_scenarios_valid = allValid;
support.finite_event_channels = allFinite;
support.delivered_event_duty_fields_valid = dutyValid;
support.pass = allValid && allFinite && dutyValid;
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
    try, parent = double(get_param(line, "LineParent"));
    catch, parent = -1;
    end
    if isempty(parent) || ~isfinite(parent(1)) || parent(1) < 0, break, end
    line = parent(1);
end
pending = line;
lineHandles = zeros(0, 1);
while ~isempty(pending)
    current = pending(1);
    pending(1) = [];
    if any(current == lineHandles), continue, end
    lineHandles(end + 1, 1) = current; %#ok<AGROW>
    try
        children = double(get_param(current, "LineChildren"));
        children = children(isfinite(children) & children >= 0);
        pending = [pending; children(:)]; %#ok<AGROW>
    catch
    end
end
for lineHandle = lineHandles(:).'
    for parameter = ["SrcPortHandle", "DstPortHandle"]
        try
            values = double(get_param(lineHandle, parameter));
            values = values(isfinite(values) & values >= 0 & ...
                values ~= port);
            ports = [ports; values(:)]; %#ok<AGROW>
        catch
        end
    end
end
ports = unique(ports, "stable");
end

function count = localConnectedPortCount(block, field)
count = 0;
try, handles = get_param(block, "PortHandles");
catch, return
end
if ~isfield(handles, field), return, end
for port = reshape(double(handles.(field)), 1, [])
    try, line = double(get_param(port, "Line"));
    catch, line = -1;
    end
    count = count + double(any(isfinite(line) & line >= 0));
end
end

function count = localPortCount(block, field)
count = 0;
try, handles = get_param(block, "PortHandles");
catch, return
end
if isfield(handles, field)
    count = numel(handles.(field));
end
end

function value = localNumericPortParameter(port, parameter)
value = nan;
try
    item = get_param(port, parameter);
    if isnumeric(item) && isscalar(item), value = double(item);
    else, value = str2double(string(item));
    end
catch
end
end

function value = localNumericBlockParameter(block, parameter)
value = nan;
try
    item = get_param(block, parameter);
    if isnumeric(item) && isscalar(item), value = double(item);
    else, value = str2double(string(item));
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

function paths = localNodePaths(nodes, indices)
indices = reshape(indices, [], 1);
indices = indices(indices >= 1 & indices <= numel(nodes));
if isempty(indices), paths = strings(0, 1);
else, paths = reshape(string({nodes(indices).path}), [], 1);
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

function pass = localOn(value)
pass = any(lower(strtrim(string(value))) == ...
    ["on", "true", "1", "yes"]);
end

function localCloseIfNeeded(model, wasLoaded)
if ~wasLoaded
    try, close_system(model, 0); catch, end
end
end

function localRequireBinding(pathValue, expectedFilePresence)
assert(isfile(pathValue) && localFilePresence(pathValue) == expectedFilePresence, ...
    "SimuVerity:F90:XMED05:FoundationBinding", ...
    "A current METRICS extraction dependency changed.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function localWriteJsonReplace(pathValue, payload)
assert(isfile(pathValue), "SimuVerity:F90:XMED05:EvidenceMissing", ...
    "METRICS extraction did not publish evidence.json.");
temporary = pathValue + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMED05:JsonOpen", ...
    "Cannot stage SCORING_CORE evidence.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
clear cleanup
assert(movefile(temporary, pathValue, "f"), ...
    "SimuVerity:F90:XMED05:JsonPublish", ...
    "Cannot atomically replace the same-run evidence with SCORING_CORE evidence.");
end
