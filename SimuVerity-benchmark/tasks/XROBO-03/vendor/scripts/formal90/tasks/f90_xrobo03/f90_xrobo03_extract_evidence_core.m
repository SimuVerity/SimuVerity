function evidence = f90_xrobo03_extract_evidence_core(modelPath, outDir)
%f90_xrobo03_extract_evidence_core Candidate candidate evidence adapter.
%   SCORING_CORE seeds the eight declared nominal workspace inputs before the unchanged
%   METRICS extractor can load, update, or compile the candidate.  METRICS continues to
%   own all six scenario assignments and simulations.  After METRICS returns, SCORING_CORE
%   replaces only the name-based static counts with a read-only
%   identity, parameter, connection, and upstream-origin audit.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

root = localProjectRoot;
official = jsondecode(fileread(simuverity_official_scenarios_path()));
policy = localLoadPolicy;
addpath(fileparts(mfilename("fullpath")), "-begin");

modelPresenceBefore = localFilePresence(modelPath);
nominalSeed = localApplyNominalPublicInputs(official);
evidence = f90_xrobo03_extract_evidence_foundation(modelPath, outDir);

% Scenario values remain those assigned by METRICS immediately before each sim.
% Re-seeding here makes a fresh read-only static load deterministic as well.
localApplyNominalPublicInputs(official);
try
    audit = localStaticAudit(modelPath, policy);
    evidence.static_audit_current_pass = true;
catch ME
    audit = localEmptyAudit;
    audit.audit_error_identifier = string(ME.identifier);
    audit.audit_error_message = string(ME.message);
    evidence.static_audit_current_pass = false;
    evidence.errors.static_audit = localError(ME);
end

modelPresenceAfter = localFilePresence(modelPath);
assert(modelPresenceBefore == modelPresenceAfter, ...
    "SimuVerity:F90:XROBO03:CandidateChanged", ...
    "The read-only SCORING_CORE audit changed the sealed candidate model.");
assert(~isfield(evidence, "model_file_presence") || ...
    lower(string(evidence.model_file_presence)) == modelPresenceAfter, ...
    "SimuVerity:F90:XROBO03:CandidateBindingMismatch", ...
    "METRICS simulation and SCORING_CORE static evidence bind different candidates.");

evidence.static_audit = audit;
evidence.structure_evidence_schema = ...
    "simuverity.f90-xrobo03-structure-evidence.v1";
evidence.precompile_public_input_seed = struct( ...
    "applied_before_current_entry", true, ...
    "values", nominalSeed, ...
    "scenario_override_owner", ...
        "unchanged METRICS localApplyPublicScenario before each simulation");
evidence.static_audit_policy_file_presence = localFilePresence(fullfile( ...
    fileparts(mfilename("fullpath")), ...
    "f90_xrobo03_static_audit_policy_core.json"));
evidence.current_evidence_engine_file_presence = localFilePresence(fullfile( ...
    fileparts(mfilename("fullpath")), ...
    "f90_xrobo03_extract_evidence_foundation.m"));
evidence.candidate_evidence_ready = true;
localWriteJson(fullfile(outDir, "evidence.json"), evidence);
end

function assigned = localApplyNominalPublicInputs(official)
policy = localLoadPolicy;
fields = string(policy.public_input_fields);
assert(isfield(official, "scenarios") && ~isempty(official.scenarios), ...
    "SimuVerity:F90:XROBO03:NominalScenario", ...
    "The official contract has no nominal scenario.");
nominal = official.scenarios(1);
assigned = struct;
for field = fields(:).'
    assert(isfield(nominal, field), ...
        "SimuVerity:F90:XROBO03:NominalInput", ...
        "Nominal scenario is missing public input %s.", field);
    value = double(nominal.(field));
    assert(~isempty(value) && all(isfinite(value), "all"), ...
        "SimuVerity:F90:XROBO03:NominalInputValue", ...
        "Nominal public input %s is empty or nonfinite.", field);
    assignin("base", field, value);
    assigned.(field) = value;
end
end

function policy = localLoadPolicy
pathValue = fullfile(fileparts(mfilename("fullpath")), ...
    "f90_xrobo03_static_audit_policy_core.json");
policy = jsondecode(fileread(pathValue));
assert(string(policy.schema) == ...
    "simuverity.f90-xrobo03-static-audit-policy.v1", ...
    "SimuVerity:F90:XROBO03:StaticPolicySchema", ...
    "Unsupported SCORING_CORE static-audit policy.");
identityParameters = string(policy.identity_parameters);
assert(~any(strcmpi(identityParameters, "Name")) && ...
    ~any(strcmpi(identityParameters, "MaskType")), ...
    "SimuVerity:F90:XROBO03:UntrustedIdentityField", ...
    "Display Name and candidate MaskType cannot grant physical identity.");
end

function audit = localStaticAudit(modelPath, policy)
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
sensorChannels = zeros(size(blocks));

for index = 1:numel(blocks)
    block = blocks(index);
    types(index) = localGet(block, "BlockType");
    identities(index) = localIdentityDescriptor(block, policy);
    physicalConnections = localConnectedPhysicalPortCount(block);
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
        physicalConnections >= 1 && ...
        localConnectedSignalPortCount(block, "Outport") >= 1;
    actuated(index) = physicalJoint(index) && ...
        localJointActuationQualified(block, policy);
    sensorChannels(index) = ...
        localConnectedJointSenseChannelCount(block, physicalJoint(index), policy) + ...
        localConnectedPhysicalSensorChannelCount(block, ...
            actualSensor(index) || spatialContact(index));
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
    "physical_sensor_count", sum(sensorChannels), ...
    "standard_public_output_count", standardCount, ...
    "constant_or_workspace_output_count", replayOnlyCount, ...
    "display_name_identity_used", false, ...
    "candidate_mask_identity_used", false, ...
    "joint_identity_fields", string(policy.identity_parameters), ...
    "public_output_origin_rows", originRows, ...
    "model_file_presence", localFilePresence(modelPath));
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

function count = localConnectedJointSenseChannelCount(block, isJoint, policy)
count = 0;
if ~isJoint, return, end
enabled = 0;
for parameter = string(policy.sense_parameters(:)).'
    mode = lower(strtrim(localGet(block, parameter)));
    enabled = enabled + double(any(mode == ["on", "true", "1", "yes"]));
end
count = min(enabled, localConnectedSignalPortCount(block, "Outport"));
end

function count = localConnectedPhysicalSensorChannelCount(block, isSensor)
if ~isSensor
    count = 0;
else
    count = localConnectedSignalPortCount(block, "Outport");
end
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
    handles = double(ports.(field));
    for port = reshape(handles, 1, [])
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
handles = double(ports.(field));
for port = reshape(handles, 1, [])
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
    handles = double(ports.(field));
    for port = reshape(handles, 1, [])
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
            localTraceUpstreamOrigins(sourceBlock, policy, visited, depth + 1);
        hasReplay = hasReplay || parentReplay;
        hasCausal = hasCausal || parentCausal;
        visitedCount = max(visitedCount, parentVisited);
    catch
    end
end
end

function audit = localEmptyAudit
audit = struct( ...
    "block_count", 0, ...
    "dynamic_block_count", 0, ...
    "physical_joint_count", 0, ...
    "spatial_contact_count", 0, ...
    "actuated_joint_count", 0, ...
    "physical_sensor_count", 0, ...
    "standard_public_output_count", 0, ...
    "constant_or_workspace_output_count", 0, ...
    "display_name_identity_used", false, ...
    "candidate_mask_identity_used", false, ...
    "joint_identity_fields", strings(0, 1), ...
    "public_output_origin_rows", struct([]));
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

function value = localError(ME)
value = struct( ...
    "identifier", string(ME.identifier), ...
    "message", string(ME.message), ...
    "report", string(getReport(ME, "extended", ...
        "hyperlinks", "off")));
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

function localWriteJson(pathValue, value)
fid = fopen(pathValue, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XROBO03:JsonOpen", ...
    "Cannot write SCORING_CORE evidence output: %s", pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(value, PrettyPrint=true), "char");
end

function root = localProjectRoot
root = fileparts(mfilename("fullpath"));
for level = 1:4
    root = fileparts(root);
end
end
