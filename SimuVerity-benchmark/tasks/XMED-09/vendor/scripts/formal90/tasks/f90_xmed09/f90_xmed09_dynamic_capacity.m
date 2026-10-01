function audit = f90_xmed09_dynamic_capacity(model)
%f90_xmed09_dynamic_capacity Count vector states and dynamic kernels.
arguments
    model (1,1) string
end

blocks = string(find_system(model, "LookUnderMasks", "all", ...
    "FollowLinks", "on", "Type", "Block"));
stateDimension = 0;
kernelOutputPorts = 0;
stateBlocks = 0;
kernelBlocks = 0;
for block = blocks'
    try
        blockType = string(get_param(block, "BlockType"));
    catch
        continue
    end
    switch blockType
        case {"Integrator", "DiscreteIntegrator", "UnitDelay", ...
                "Memory", "Delay"}
            stateBlocks = stateBlocks + 1;
            stateDimension = stateDimension + localStateWidth(block);
        case "StateSpace"
            stateBlocks = stateBlocks + 1;
            stateDimension = stateDimension + localStateSpaceOrder(block);
        case "TransferFcn"
            stateBlocks = stateBlocks + 1;
            stateDimension = stateDimension + localTransferOrder(block);
        case "S-Function"
            % MATLAB Function charts compile to an S-Function kernel.  Count
            % its declared output interface once instead of treating every
            % vector-valued algorithmic core as a scalar block.
            kernelBlocks = kernelBlocks + 1;
            kernelOutputPorts = kernelOutputPorts + localOutputPortCount(block);
    end
end

audit = struct( ...
    "dynamic_state_dimension", double(stateDimension), ...
    "dynamic_kernel_output_port_count", double(kernelOutputPorts), ...
    "dynamic_capacity_units", double(stateDimension + kernelOutputPorts), ...
    "dynamic_state_block_count", double(stateBlocks), ...
    "dynamic_kernel_block_count", double(kernelBlocks), ...
    "dynamic_capacity_policy", ...
        "resolved state-vector elements plus S-Function output ports");
end

function width = localStateWidth(block)
width = 1;
try
    expression = string(get_param(block, "InitialCondition"));
    value = slResolve(char(expression), char(block));
    width = max(1, numel(value));
catch
    width = localCompiledOutputWidth(block);
end
end

function width = localCompiledOutputWidth(block)
width = 1;
try
    handles = get_param(block, "PortHandles");
    if isempty(handles.Outport), return; end
    dimensions = get_param(handles.Outport(1), "CompiledPortDimensions");
    dimensions = double(dimensions(:));
    if numel(dimensions) >= 2 && dimensions(1) >= 1
        width = max(1, prod(dimensions(2:end)));
    end
catch
    width = 1;
end
end

function order = localStateSpaceOrder(block)
order = 1;
try
    expression = string(get_param(block, "A"));
    value = slResolve(char(expression), char(block));
    order = max(1, size(value, 1));
catch
end
end

function order = localTransferOrder(block)
order = 1;
try
    expression = string(get_param(block, "Denominator"));
    value = slResolve(char(expression), char(block));
    order = max(1, numel(value) - 1);
catch
end
end

function count = localOutputPortCount(block)
count = 1;
try
    handles = get_param(block, "PortHandles");
    count = max(1, numel(handles.Outport));
catch
end
end
