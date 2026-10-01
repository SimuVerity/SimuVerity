function audit = f90_xrobo03_static_audit(modelPath, policyPath)
%f90_xrobo03_static_audit Connection-aware Simscape structure audit.
%   Simscape measurement channels are physical-signal RConn/LConn ports,
%   not ordinary Simulink Outports.  A channel is counted only when the
%   physical-signal port is actually connected to a PS-Simulink Converter.
%   Joint channels additionally require the corresponding sense parameter.
arguments
    modelPath (1,1) string
    policyPath (1,1) string
end

policy = localLoadPolicy(policyPath);
[~, model] = fileparts(modelPath);
wasLoaded = bdIsLoaded(model);
if ~wasLoaded
    load_system(modelPath);
end
cleanup = onCleanup(@() localCloseIfNeeded(model, wasLoaded)); %#ok<NASGU>

blocks = string(find_system(model, "FollowLinks", "off", ...
    "LookUnderMasks", "all", "Type", "Block"));
types = strings(size(blocks));
identities = strings(size(blocks));
physicalJoint = false(size(blocks));
spatialContact = false(size(blocks));
actualSensor = false(size(blocks));
dynamic = false(size(blocks));
actuated = false(size(blocks));
jointSenseChannels = zeros(size(blocks));
explicitSensorChannels = zeros(size(blocks));
contactMeasurementChannels = zeros(size(blocks));

for index = 1:numel(blocks)
    block = blocks(index);
    types(index) = localGet(block, "BlockType");
    identities(index) = localIdentityDescriptor(block, policy);
    physicalConnections = localConnectedPhysicalPortCount(block);
    converterChannels = localConnectedMeasurementConverterChannelCount( ...
        block, policy);
    physicalJoint(index) = ...
        localContainsToken(identities(index), ...
            string(policy.physical_joint_tokens)) && ...
        physicalConnections >= ...
            double(policy.minimum_physical_connections_per_joint);
    spatialContact(index) = ...
        localContainsToken(identities(index), ...
            string(policy.spatial_contact_tokens)) && ...
        physicalConnections >= ...
            double(policy.minimum_physical_connections_per_contact);
    actualSensor(index) = ...
        localContainsToken(identities(index), ...
            string(policy.physical_sensor_tokens)) && ...
        physicalConnections >= 1 && converterChannels >= 1;
    actuated(index) = physicalJoint(index) && ...
        localJointActuationQualified(block, policy);
    jointSenseChannels(index) = localConnectedJointSenseChannelCount( ...
        block, physicalJoint(index), converterChannels, policy);
    explicitSensorChannels(index) = ...
        double(actualSensor(index)) * converterChannels;
    contactMeasurementChannels(index) = ...
        double(spatialContact(index)) * converterChannels;
    dynamic(index) = any(types(index) == ...
        string(policy.dynamic_block_types)) && ...
        localBlockHasAnyConnectedLine(block);
end

[standardCount, replayOnlyCount, originRows] = ...
    localPublicOutputOriginAudit(blocks, types, policy);
audit = struct( ...
    "block_count", numel(blocks), ...
    "dynamic_block_count", nnz(dynamic), ...
    "physical_joint_count", nnz(physicalJoint), ...
    "spatial_contact_count", nnz(spatialContact), ...
    "actuated_joint_count", nnz(actuated), ...
    "physical_sensor_count", sum(jointSenseChannels) + ...
        sum(explicitSensorChannels) + sum(contactMeasurementChannels), ...
    "joint_sense_channel_count", sum(jointSenseChannels), ...
    "explicit_sensor_channel_count", sum(explicitSensorChannels), ...
    "contact_measurement_channel_count", ...
        sum(contactMeasurementChannels), ...
    "standard_public_output_count", standardCount, ...
    "constant_or_workspace_output_count", replayOnlyCount, ...
    "display_name_identity_used", false, ...
    "candidate_mask_identity_used", false, ...
    "joint_identity_fields", string(policy.identity_parameters), ...
    "measurement_channel_rule", ...
        "connected Simscape physical-signal port to PS-Simulink Converter", ...
    "public_output_origin_rows", originRows, ...
    "model_file_presence", xp9_file_presence_file(modelPath));
end

function policy = localLoadPolicy(pathValue)
policy = jsondecode(fileread(pathValue));
assert(string(policy.schema) == ...
    "simuverity.f90-xrobo03-static-audit-policy.v1", ...
    "SimuVerity:F90:XROBO03:StaticPolicySchema", ...
    "Unsupported GROUP_SCORING static-audit policy.");
identityParameters = string(policy.identity_parameters);
assert(~any(strcmpi(identityParameters, "Name")) && ...
    ~any(strcmpi(identityParameters, "MaskType")), ...
    "SimuVerity:F90:XROBO03:UntrustedIdentityField", ...
    "Display Name and candidate MaskType cannot grant physical identity.");
end

function value = localIdentityDescriptor(block, policy)
parts = strings(0, 1);
for parameter = string(policy.identity_parameters(:)).'
    item = localGet(block, parameter);
    if strlength(item) > 0
        parts(end + 1, 1) = item; %#ok<AGROW>
    end
end
value = join(parts, " | ");
end

function pass = localContainsToken(identity, tokens)
compactIdentity = lower(regexprep(string(identity), "\s+", ""));
compactTokens = lower(regexprep(string(tokens), "\s+", ""));
pass = any(contains(compactIdentity, compactTokens));
end

function pass = localJointActuationQualified(block, policy)
torqueMode = localGet(block, "TorqueActuationMode");
motionMode = localGet(block, "MotionActuationMode");
pass = localModeMatches(torqueMode, string(policy.input_torque_modes)) && ...
    localModeMatches(motionMode, string(policy.computed_motion_modes)) && ...
    localHasConnectedActuationPort(block, ...
        double(policy.minimum_physical_connections_per_joint));
end

function pass = localModeMatches(actual, accepted)
actual = lower(regexprep(string(actual), "[^A-Za-z0-9]", ""));
accepted = lower(regexprep(string(accepted), "[^A-Za-z0-9]", ""));
pass = any(actual == accepted);
end

function pass = localHasConnectedActuationPort(block, framePortFloor)
pass = localConnectedSignalPortCount(block, "Inport") >= 1 || ...
    localConnectedPhysicalPortCount(block) > framePortFloor;
end

function count = localConnectedJointSenseChannelCount( ...
        block, isJoint, converterChannels, policy)
count = 0;
if ~isJoint, return, end
enabled = 0;
for parameter = string(policy.sense_parameters(:)).'
    mode = lower(strtrim(localGet(block, parameter)));
    enabled = enabled + double(any(mode == ["on", "true", "1", "yes"]));
end
count = min(enabled, converterChannels);
end

function count = localConnectedMeasurementConverterChannelCount(block, policy)
count = 0;
try
    ports = get_param(block, "PortHandles");
catch
    return;
end
for field = ["LConn", "RConn"]
    if ~isfield(ports, field), continue, end
    for port = reshape(double(ports.(field)), 1, [])
        if ~localPortLineConnected(port), continue, end
        line = get_param(port, "Line");
        neighbors = localLineNeighborBlocks(line, block);
        matched = false;
        for neighbor = neighbors(:).'
            identity = localIdentityDescriptor(neighbor, policy);
            matched = matched || localContainsToken(identity, ...
                string(policy.physical_signal_converter_tokens));
        end
        count = count + double(matched);
    end
end
end

function neighbors = localLineNeighborBlocks(line, ownerBlock)
neighbors = strings(0, 1);
ownerHandle = double(get_param(ownerBlock, "Handle"));
endpoints = zeros(0, 1);
for parameter = ["SrcPortHandle", "DstPortHandle"]
    try
        value = double(get_param(line, parameter));
        endpoints = [endpoints; value(:)]; %#ok<AGROW>
    catch
    end
end
for endpoint = reshape(endpoints, 1, [])
    if ~isfinite(endpoint) || endpoint < 0, continue, end
    try
        parent = string(get_param(endpoint, "Parent"));
        parentHandle = double(get_param(parent, "Handle"));
    catch
        continue;
    end
    if parentHandle ~= ownerHandle
        neighbors(end + 1, 1) = parent; %#ok<AGROW>
    end
end
neighbors = unique(neighbors, "stable");
end

function count = localConnectedPhysicalPortCount(block)
count = 0;
try
    ports = get_param(block, "PortHandles");
catch
    return;
end
for field = ["LConn", "RConn"]
    if ~isfield(ports, field), continue, end
    for port = reshape(double(ports.(field)), 1, [])
        count = count + double(localPortLineConnected(port));
    end
end
end

function count = localConnectedSignalPortCount(block, field)
count = 0;
try
    ports = get_param(block, "PortHandles");
catch
    return;
end
if ~isfield(ports, field), return, end
for port = reshape(double(ports.(field)), 1, [])
    count = count + double(localPortLineConnected(port));
end
end

function pass = localPortLineConnected(port)
pass = false;
try
    line = get_param(port, "Line");
    pass = isnumeric(line) && any(double(line) >= 0);
catch
end
end

function pass = localBlockHasAnyConnectedLine(block)
pass = false;
try
    ports = get_param(block, "PortHandles");
catch
    return;
end
fields = string(fieldnames(ports));
for field = fields(:).'
    for port = reshape(double(ports.(field)), 1, [])
        if localPortLineConnected(port)
            pass = true;
            return;
        end
    end
end
end

function [standardCount, replayOnlyCount, rows] = ...
        localPublicOutputOriginAudit(blocks, types, policy)
standardNames = string(policy.standard_public_outputs);
toWorkspace = blocks(types == "ToWorkspace");
standardCount = 0;
replayOnlyCount = 0;
rows = repmat(struct( ...
    "variable", "", "has_replay_origin", false, ...
    "has_causal_origin", false, "visited_block_count", 0), 0, 1);
for block = toWorkspace(:).'
    variable = localGet(block, "VariableName");
    if ~any(variable == standardNames), continue, end
    standardCount = standardCount + 1;
    replay = false;
    causal = false;
    visitedCount = 0;
    try
        ports = get_param(block, "PortHandles");
        line = get_param(ports.Inport(1), "Line");
        if isnumeric(line) && line >= 0
            sourcePort = get_param(line, "SrcPortHandle");
            sourceBlock = get_param(sourcePort, "Parent");
            [replay, causal, visitedCount] = localTraceUpstreamOrigins( ...
                sourceBlock, policy, zeros(0, 1), 0);
        end
    catch
    end
    replayOnlyCount = replayOnlyCount + double(replay && ~causal);
    rows(end + 1, 1) = struct( ... %#ok<AGROW>
        "variable", variable, ...
        "has_replay_origin", logical(replay), ...
        "has_causal_origin", logical(causal), ...
        "visited_block_count", visitedCount);
end
end

function [hasReplay, hasCausal, visitedCount] = ...
        localTraceUpstreamOrigins(block, policy, visited, depth)
hasReplay = false;
hasCausal = false;
visitedCount = numel(visited);
if depth > double(policy.maximum_upstream_trace_depth), return, end
try
    handle = double(get_param(block, "Handle"));
catch
    return;
end
if any(visited == handle), return, end
visited = [visited(:); handle]; %#ok<AGROW>
visitedCount = numel(visited);

blockType = localGet(block, "BlockType");
if any(blockType == string(policy.replay_source_block_types))
    hasReplay = true;
    return;
end
identity = localIdentityDescriptor(block, policy);
trustedPhysical = localContainsToken(identity, ...
    string(policy.trusted_physical_origin_tokens)) && ...
    localConnectedPhysicalPortCount(block) >= 1;
connectedDynamic = any(blockType == string(policy.dynamic_block_types)) && ...
    localBlockHasAnyConnectedLine(block);
if trustedPhysical || connectedDynamic
    hasCausal = true;
    return;
end

if localContainsToken(identity, ...
        string(policy.physical_signal_converter_tokens))
    try
        ports = get_param(block, "PortHandles");
        if isfield(ports, "LConn")
            for port = reshape(double(ports.LConn), 1, [])
                if ~localPortLineConnected(port), continue, end
                line = get_param(port, "Line");
                neighbors = localLineNeighborBlocks(line, block);
                for neighbor = neighbors(:).'
                    [parentReplay, parentCausal, parentVisited] = ...
                        localTraceUpstreamOrigins( ...
                            neighbor, policy, visited, depth + 1);
                    hasReplay = hasReplay || parentReplay;
                    hasCausal = hasCausal || parentCausal;
                    visitedCount = max(visitedCount, parentVisited);
                end
            end
        end
    catch
    end
end

try
    ports = get_param(block, "PortHandles");
catch
    return;
end
if ~isfield(ports, "Inport"), return, end
for port = reshape(double(ports.Inport), 1, [])
    try
        line = get_param(port, "Line");
        if ~isnumeric(line) || line < 0, continue, end
        sourcePort = get_param(line, "SrcPortHandle");
        sourceBlock = get_param(sourcePort, "Parent");
        [parentReplay, parentCausal, parentVisited] = ...
            localTraceUpstreamOrigins( ...
                sourceBlock, policy, visited, depth + 1);
        hasReplay = hasReplay || parentReplay;
        hasCausal = hasCausal || parentCausal;
        visitedCount = max(visitedCount, parentVisited);
    catch
    end
end
end

function value = localGet(block, parameter)
try
    value = string(get_param(block, parameter));
    if ~isscalar(value), value = join(value(:), " "); end
catch
    value = "";
end
end

function localCloseIfNeeded(model, wasLoaded)
if ~wasLoaded
    try, close_system(model, 0); catch, end
end
end
