function audit = f90_xmed03_static_audit(modelPath)
%F90_XMED03_STATIC_AUDIT Connection-oriented mechanism/provenance audit.
arguments
    modelPath (1,1) string
end

assert(isfile(modelPath), "SimuVerity:F90:XMED03:AuditMissingModel", ...
    "Model file does not exist.");
[~, model] = fileparts(modelPath);
load_system(modelPath);
cleanup = onCleanup(@() localClose(model)); %#ok<NASGU>
set_param(model, "SimulationCommand", "update");

blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
descriptors = strings(size(blocks));
handles = zeros(size(blocks));
for index = 1:numel(blocks)
    handles(index) = get_param(blocks(index), "Handle");
    descriptors(index) = localDescriptor(blocks(index));
end

isResistance = localContainsAny(descriptors, [ ...
    "resistor", "resistance", "restriction", "orifice"]);
isCompliance = localContainsAny(descriptors, [ ...
    "capacitor", "compliance", "chamber", "constant volume"]);
isPhysicalSource = localContainsAny(descriptors, [ ...
    "controlled voltage source", "controlled pressure source", ...
    "controlled flow source", "pressure source", "flow rate source"]);
isPsToSim = localContainsAny(descriptors, [ ...
    "ps-simulink", "ps simulink converter"]);
isSimToPs = localContainsAny(descriptors, [ ...
    "simulink-ps", "simulink ps converter"]);
isPhysicalSensor = localContainsAny(descriptors, [ ...
    "current sensor", "flow rate sensor", "pressure sensor", ...
    "voltage sensor", "mass flow sensor"]);
isControlledElement = localContainsAny(descriptors, [ ...
    "variable resistor", "variable orifice", "controlled valve", ...
    "variable valve", "controlled restriction"]);

[forward, reverse] = localSignalGraph(model, handles, blocks);
measurementNodes = find(isPsToSim | isPhysicalSensor);
commandNodes = find(isSimToPs);
reachableCommands = false(size(commandNodes));
for index = 1:numel(commandNodes)
    reachableCommands(index) = localReachableFromAny( ...
        forward, measurementNodes, commandNodes(index));
end

requiredPhysicalOutputs = [ ...
    "patient_pressure", "patient_flow", "patient_volume"];
outputProvenance = false(size(requiredPhysicalOutputs));
outputBlocks = strings(size(requiredPhysicalOutputs));
for index = 1:numel(requiredPhysicalOutputs)
    [sinkIndex, sinkPath] = localWorkspaceSink( ...
        blocks, requiredPhysicalOutputs(index));
    outputBlocks(index) = sinkPath;
    if sinkIndex > 0
        outputProvenance(index) = localReachesAny( ...
            reverse, sinkIndex, find(isPsToSim | isPhysicalSensor));
    end
end

branchCommandSink = localWorkspaceSink(blocks, "branch_command");
feedbackPathCount = nnz(reachableCommands);
mechanismChecks = struct( ...
    "shared_physical_source", nnz(isPhysicalSource) >= 1, ...
    "two_patient_resistive_mechanics", nnz(isResistance) >= 4, ...
    "two_patient_compliance_mechanics", nnz(isCompliance) >= 2, ...
    "two_commanded_physical_branch_elements", ...
        nnz(isControlledElement) >= 2 && nnz(isSimToPs) >= 2, ...
    "two_measured_feedback_paths", feedbackPathCount >= 2, ...
    "physical_pressure_flow_volume_provenance", ...
        all(outputProvenance), ...
    "branch_command_output_present", branchCommandSink > 0);

checkNames = string(fieldnames(mechanismChecks));
failed = strings(0, 1);
for index = 1:numel(checkNames)
    if ~mechanismChecks.(checkNames(index))
        failed(end+1, 1) = checkNames(index); %#ok<AGROW>
    end
end

audit = struct( ...
    "schema", "simuverity.formal90-xmed03-static-audit.v1", ...
    "model_path", string(modelPath), ...
    "block_count", numel(blocks), ...
    "resistive_element_count", nnz(isResistance), ...
    "compliance_element_count", nnz(isCompliance), ...
    "physical_source_count", nnz(isPhysicalSource), ...
    "physical_sensor_count", nnz(isPhysicalSensor), ...
    "ps_to_sim_count", nnz(isPsToSim), ...
    "sim_to_ps_count", nnz(isSimToPs), ...
    "controlled_branch_element_count", nnz(isControlledElement), ...
    "measured_feedback_command_count", feedbackPathCount, ...
    "required_output_blocks", outputBlocks, ...
    "required_output_physical_provenance", outputProvenance, ...
    "checks", mechanismChecks, ...
    "failed_checks", failed, ...
    "pass", isempty(failed));
end

function descriptor = localDescriptor(block)
properties = ["Name", "BlockType", "MaskType", "ReferenceBlock", ...
    "SourceType"];
pieces = strings(0, 1);
for property = properties
    try
        value = string(get_param(block, property));
        if strlength(value) > 0
            pieces(end+1, 1) = value; %#ok<AGROW>
        end
    catch
    end
end
descriptor = lower(regexprep(strjoin(pieces, " "), "\s+", " "));
end

function mask = localContainsAny(values, needles)
mask = false(size(values));
for needle = needles
    mask = mask | contains(values, lower(needle));
end
end

function [forward, reverse] = localSignalGraph(model, handles, blocks)
count = numel(handles);
forward = cell(count, 1);
reverse = cell(count, 1);
indexByHandle = containers.Map("KeyType", "double", "ValueType", "double");
for index = 1:count
    indexByHandle(handles(index)) = index;
end

lines = find_system(model, "FindAll", "on", "Type", "line");
for line = reshape(lines, 1, [])
    try
        sourcePort = get_param(line, "SrcPortHandle");
        destinationPorts = get_param(line, "DstPortHandle");
        if sourcePort <= 0 || isempty(destinationPorts), continue; end
        sourceBlock = get_param(sourcePort, "Parent");
        sourceHandle = get_param(sourceBlock, "Handle");
        if ~isKey(indexByHandle, sourceHandle), continue; end
        sourceIndex = indexByHandle(sourceHandle);
        for destinationPort = reshape(destinationPorts, 1, [])
            if destinationPort <= 0, continue; end
            destinationBlock = get_param(destinationPort, "Parent");
            destinationHandle = get_param(destinationBlock, "Handle");
            if ~isKey(indexByHandle, destinationHandle), continue; end
            destinationIndex = indexByHandle(destinationHandle);
            forward{sourceIndex}(end+1) = destinationIndex; %#ok<AGROW>
            reverse{destinationIndex}(end+1) = sourceIndex; %#ok<AGROW>
        end
    catch
    end
end

gotoBlocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "Goto"));
fromBlocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "From"));
for goto = gotoBlocks(:)'
    tag = string(get_param(goto, "GotoTag"));
    gotoIndex = find(blocks == goto, 1);
    if isempty(gotoIndex), continue; end
    for from = fromBlocks(:)'
        if string(get_param(from, "GotoTag")) ~= tag, continue; end
        fromIndex = find(blocks == from, 1);
        if isempty(fromIndex), continue; end
        forward{gotoIndex}(end+1) = fromIndex; %#ok<AGROW>
        reverse{fromIndex}(end+1) = gotoIndex; %#ok<AGROW>
    end
end

for index = 1:count
    forward{index} = unique(forward{index});
    reverse{index} = unique(reverse{index});
end
end

function result = localReachableFromAny(graph, starts, target)
result = false;
if isempty(starts), return; end
seen = false(numel(graph), 1);
queue = reshape(starts, 1, []);
seen(queue) = true;
while ~isempty(queue)
    node = queue(1);
    queue(1) = [];
    if node == target
        result = true;
        return;
    end
    next = graph{node};
    next = next(~seen(next));
    seen(next) = true;
    queue = [queue, next]; %#ok<AGROW>
end
end

function result = localReachesAny(graph, start, targets)
result = false;
if isempty(targets), return; end
seen = false(numel(graph), 1);
queue = start;
seen(start) = true;
while ~isempty(queue)
    node = queue(1);
    queue(1) = [];
    if any(node == targets)
        result = true;
        return;
    end
    next = graph{node};
    next = next(~seen(next));
    seen(next) = true;
    queue = [queue, next]; %#ok<AGROW>
end
end

function [index, path] = localWorkspaceSink(blocks, variable)
index = 0;
path = "";
for candidate = 1:numel(blocks)
    try
        if string(get_param(blocks(candidate), "BlockType")) == ...
                "ToWorkspace" && ...
                string(get_param(blocks(candidate), "VariableName")) == variable
            index = candidate;
            path = blocks(candidate);
            return;
        end
    catch
    end
end
end

function localClose(model)
if bdIsLoaded(model), close_system(model, 0); end
end
