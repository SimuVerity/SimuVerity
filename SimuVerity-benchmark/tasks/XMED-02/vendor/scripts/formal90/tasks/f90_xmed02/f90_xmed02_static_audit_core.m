function audit = f90_xmed02_static_audit_core(modelOrPath)
%f90_xmed02_static_audit_core Connection-based minimum mechanism audit.
%
% Names are used only for the three public output variables.  Physical
% roles come from block identities, conserving ports, and real signal
% reachability.

inputWasPath = isfile(modelOrPath);
if inputWasPath
    [~, model] = fileparts(modelOrPath);
    load_system(modelOrPath);
    cleanup = onCleanup(@() close_system(model, 0));
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
    ["controlled current source", "controlled flow rate source", ...
    "controlled mass flow rate source", "centrifugal pump"]));

rootBlocks = find_system(model, "SearchDepth", 1, "Type", "Block");
rootBlocks = string(rootBlocks(:));
rootBlocks(rootBlocks == model) = [];
[edgesFrom, edgesTo] = localRootEdges(model);

pressureOwners = localOwners(rootBlocks, ...
    ["voltage sensor", "pressure sensor"]);
flowOwners = localOwners(rootBlocks, ...
    ["current sensor", "flow rate sensor", "mass flow sensor"]);
actuatorOwners = localOwners(rootBlocks, ...
    ["controlled current source", "controlled flow rate source", ...
    "controlled mass flow rate source", "centrifugal pump"]);

[feedbackOk, feedbackPath] = localAnyReachable( ...
    pressureOwners, actuatorOwners, edgesFrom, edgesTo);
dynamicOnPath = localPathHasDynamicControl(feedbackPath);
feedbackOk = feedbackOk && dynamicOnPath;

pressureSink = localOutputSink(model, "pressure_state");
flowSink = localOutputSink(model, "flow_state");
commandSink = localOutputSink(model, "pump_command");
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
structureOk = counts.resistive >= 8 && counts.compliance >= 4 && ...
    counts.inertance >= 3 && counts.valve >= 4;
physicalIoOk = counts.pressure_sensor >= 3 && ...
    counts.flow_sensor >= 3;
pumpOk = counts.controlled_flow_actuator >= 1 && ...
    ~isempty(actuatorOwners);

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
audit.components = components;
audit.score = mean(values);
audit.core_mechanism_ok = structureOk && physicalIoOk && pumpOk && ...
    feedbackOk && interfaceOk && pressureProvenanceOk && ...
    flowProvenanceOk && commandProvenanceOk;
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

function identity = localIdentity(block)
parts = strings(0, 1);
for parameter = ["BlockType", "MaskType", "ReferenceBlock", "SourceBlock"]
    try
        value = string(get_param(block, parameter));
        if strlength(value) > 0, parts(end + 1, 1) = value; end %#ok<AGROW>
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

function [from, to] = localRootEdges(model)
from = strings(0, 1);
to = strings(0, 1);
lines = find_system(model, "FindAll", "on", "SearchDepth", 1, ...
    "Type", "line");
for index = 1:numel(lines)
    try
        sourcePort = get_param(lines(index), "SrcPortHandle");
        destinationPorts = get_param(lines(index), "DstPortHandle");
        if sourcePort == -1 || isempty(destinationPorts), continue; end
        source = string(getfullname(get_param(sourcePort, "Parent")));
        for destinationPort = destinationPorts(:).'
            if destinationPort == -1, continue; end
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
            return;
        end
    catch
    end
end
end

function ancestors = localAncestors(sink, from, to)
ancestors = strings(0, 1);
if strlength(sink) == 0, return; end
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
        return;
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
        return;
    end
    children = unique(to(from == node));
    for child = children(:).'
        if any(seen == child), continue; end
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
        return;
    end
end
end
