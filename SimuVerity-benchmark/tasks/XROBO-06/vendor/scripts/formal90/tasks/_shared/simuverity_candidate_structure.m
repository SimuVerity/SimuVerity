function report = simuverity_candidate_structure(model, outputNames)
%simuverity_candidate_structure Name-neutral structural evidence primitives.
%
% Public output names are used only to locate their declared sinks. Core
% mechanism evidence is based on actual block capabilities, physical
% conserving ports, signal connections, state-bearing block types, and
% library/mask semantics. Block display names and canvas coordinates are
% deliberately excluded.
arguments
    model (1,1) string
    outputNames (:,1) string
end

blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
blocks = blocks(blocks ~= model);
rows = repmat(struct( ...
    "block_type", "", ...
    "source_block", "", ...
    "reference_block", "", ...
    "mask_type", "", ...
    "semantic_type", "", ...
    "has_physical_ports", false, ...
    "has_signal_input", false, ...
    "has_signal_output", false), numel(blocks), 1);
for index = 1:numel(blocks)
    block = blocks(index);
    blockType = localGet(block, "BlockType");
    sourceBlock = localGet(block, "SourceBlock");
    referenceBlock = localGet(block, "ReferenceBlock");
    maskType = localGet(block, "MaskType");
    rows(index).block_type = blockType;
    rows(index).source_block = sourceBlock;
    rows(index).reference_block = referenceBlock;
    rows(index).mask_type = maskType;
    rows(index).semantic_type = lower(strjoin( ...
        [blockType, sourceBlock, referenceBlock, maskType], " "));
    try
        handles = get_param(block, "PortHandles");
        rows(index).has_physical_ports = ...
            ~isempty(handles.LConn) || ~isempty(handles.RConn);
        rows(index).has_signal_input = ~isempty(handles.Inport);
        rows(index).has_signal_output = ~isempty(handles.Outport);
    catch
    end
end

types = string({rows.block_type});
semanticTypes = string({rows.semantic_type});
dynamicTypes = ["Integrator", "DiscreteIntegrator", "StateSpace", ...
    "TransferFcn", "UnitDelay", "Memory", "Delay", "S-Function"];
physical = logical([rows.has_physical_ports]);
outputBindings = localOutputBindings(model, outputNames);

report = struct;
report.block_count = numel(rows);
report.dynamic_block_count = nnz(ismember(types, dynamicTypes));
report.physical_connection_block_count = nnz(physical);
report.signal_input_block_count = nnz([rows.has_signal_input]);
report.signal_output_block_count = nnz([rows.has_signal_output]);
report.constant_count = nnz(types == "Constant");
report.from_workspace_count = nnz(types == "FromWorkspace");
report.to_workspace_count = nnz(types == "ToWorkspace");
report.output_bindings = outputBindings;
report.connected_output_count = nnz([outputBindings.connected]);
report.nontrivial_output_source_count = nnz( ...
    ~ismember(string({outputBindings.source_block_type}), ...
    ["", "Constant", "FromWorkspace"]));
report.signal_cycle_present = localSignalCyclePresent(blocks);
report.semantic_types = semanticTypes;
report.block_rows = rows;
end

function bindings = localOutputBindings(model, outputNames)
bindings = repmat(struct( ...
    "name", "", ...
    "connected", false, ...
    "source_block_type", ""), numel(outputNames), 1);
workspaceSinks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "BlockType", "ToWorkspace"));
outportSinks = string(find_system(model, "SearchDepth", 1, ...
    "BlockType", "Outport"));
for index = 1:numel(outputNames)
    name = outputNames(index);
    bindings(index).name = name;
    sink = "";
    for block = workspaceSinks'
        if string(localGet(block, "VariableName")) == name
            sink = block;
            break
        end
    end
    if strlength(sink) == 0
        for block = outportSinks'
            if string(localGet(block, "Name")) == name
                sink = block;
                break
            end
        end
    end
    if strlength(sink) == 0, continue, end
    try
        handles = get_param(sink, "PortHandles");
        line = get_param(handles.Inport(1), "Line");
        sourcePort = get_param(line, "SrcPortHandle");
        sourceBlock = string(get_param(sourcePort, "Parent"));
        bindings(index).connected = true;
        bindings(index).source_block_type = ...
            string(get_param(sourceBlock, "BlockType"));
    catch
    end
end
end

function present = localSignalCyclePresent(blocks)
present = false;
if isempty(blocks), return, end
handles = zeros(numel(blocks), 1);
for index = 1:numel(blocks)
    try, handles(index) = get_param(blocks(index), "Handle"); catch, end
end
edgesFrom = zeros(0, 1);
edgesTo = zeros(0, 1);
for index = 1:numel(blocks)
    try
        ports = get_param(blocks(index), "PortHandles");
        for port = reshape(ports.Outport, 1, [])
            line = get_param(port, "Line");
            if line < 0, continue, end
            destinations = get_param(line, "DstBlockHandle");
            destinations = double(reshape(destinations, [], 1));
            destinations = destinations(destinations > 0);
            edgesFrom = [edgesFrom; ...
                repmat(handles(index), numel(destinations), 1)]; %#ok<AGROW>
            edgesTo = [edgesTo; destinations]; %#ok<AGROW>
        end
    catch
    end
end
if isempty(edgesFrom), return, end
nodes = unique([edgesFrom; edgesTo]);
[~, fromIndex] = ismember(edgesFrom, nodes);
[~, toIndex] = ismember(edgesTo, nodes);
graphValue = digraph(fromIndex, toIndex);
components = conncomp(graphValue, "Type", "strong");
counts = accumarray(components(:), 1);
present = any(counts > 1) || any(fromIndex == toIndex);
end

function value = localGet(block, parameter)
value = "";
try, value = string(get_param(block, parameter)); catch, end
end
