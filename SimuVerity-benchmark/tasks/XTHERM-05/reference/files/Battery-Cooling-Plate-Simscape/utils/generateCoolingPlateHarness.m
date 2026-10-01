function generateCoolingPlateHarness(obj,coolingPlateLib,options)
% This function generates a test harness for a battery cooling plate 
% generated using the ComponentConnectivity class.
%
%   Inputs:
%       obj               - ComponentConnectivity object
%       coolingPlateLib   - Name of the cooling plate library 
%                           (E.g. BatteryCoolingPlate_lib) generated using 
%                           ComponentConnectivity class.
%
%   Optional inputs:
%       BattHeatFlowRate         - Heat flow rate to cooling plate due to heat
%                                  generated in battery.
%       CoolantReservoirInitTemp - Initial temperature of the coolant.
%       CoolantFlowRate          - Volumetric flow rate of the coolant.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    obj ComponentConnectivity
    coolingPlateLib (1,1) string
    options.BattHeatFlowRate (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.BattHeatFlowRate,"W")}...
        = simscape.Value(200,"W")
    options.CoolantReservoirInitTemp (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.CoolantReservoirInitTemp,"K")}...
        = simscape.Value(293.15,"K")
    options.CoolantFlowRate (1,1) simscape.Value{simscape.mustBeCommensurateUnit(options.CoolantFlowRate,"m^3/s")}...
        = simscape.Value(1,"lpm")
end

solverConfigLibPath = "nesl_utility/Solver Configuration";
thermalRefLibPath = "fl_lib/Thermal/Thermal Elements/Thermal Reference";
heatFlowSrcLibPath = sprintf("fl_lib/Thermal/Thermal Sources/Heat Flow Rate\nSource");
reservoirTLLibPath = "fl_lib/Thermal Liquid/Elements/Reservoir (TL)";
flowRateSrcLibPath = "fl_lib/Thermal Liquid/Sources/Flow Rate Source (TL)";
PSSimulinkConverterLibPath = "nesl_utility/PS-Simulink Converter";
scopeLibPath = "simulink/Commonly Used Blocks/Scope";
arrayConnLibPath = "nesl_utility/Array Connection";


if exist('obj','var') && isa(obj,'ComponentConnectivity')

    % Create and open a new model
    modelName = strcat(obj.ModelName,"Harness");

    if bdIsLoaded(modelName)
        close_system(modelName,0);
        new_system(modelName);
    else
        new_system(modelName);
    end
    open_system(modelName);

    solverConfigPath = strcat(modelName,"/Solver Configuration");
    thermalRefPath = strcat(modelName,"/Thermal Reference");
    heatFlowSrcPath = strcat(modelName,sprintf("/Heat Flow Rate\nSource"));
    reservoir1Path = strcat(modelName,"/Reservoir1");
    reservoir2Path = strcat(modelName,"/Reservoir2");
    flowSrcPath = strcat(modelName,sprintf("/Flow Rate\nSource (TL)"));
    PSSimulinkConverterPath = strcat(modelName,sprintf("/PS-Simulink\nConverter"));
    scopePath = strcat(modelName,"/Scope");
    arrayConnPath = strcat(modelName,"/Array Connection");

    %% Add blocks in test harness
    % Load cooling plate library
    load_system(coolingPlateLib);

    % Unlock library
    set_param(coolingPlateLib, "Lock", "off");

    % Get source & destination block paths for cooling plate and associated
    % blocks
    srcCoolingPlateBlkPath = string(find_system(coolingPlateLib, "SearchDepth", 1, ...
        "Type", "Block"));
    srcCoolingPlateBlkName = get_param(srcCoolingPlateBlkPath, "Name");
    dstCoolingPlateBlkPath = strcat(modelName,"/",srcCoolingPlateBlkName);

    % Add source cooling plate block to destination cooling plate block path
    add_block(srcCoolingPlateBlkPath, dstCoolingPlateBlkPath,"Position",[200    58   350   212]);

    % Disable library link
    set_param(dstCoolingPlateBlkPath,"LinkStatus","inactive");

    % Lock library
    set_param(coolingPlateLib, "Lock", "on");

    add_block(solverConfigLibPath,solverConfigPath,"Position",[35, 119, 80, 151]);
    add_block(thermalRefLibPath,thermalRefPath,"Position",[5, 45, 25, 65]);
    set_param(thermalRefPath,"Orientation","Left");
    add_block(heatFlowSrcLibPath,heatFlowSrcPath,"Position",[41, 35, 69, 75]);
    set_param(heatFlowSrcPath,"Orientation","Left");
    add_block(reservoirTLLibPath,reservoir1Path,"Position",[95, 200, 135, 240]);
    add_block(flowRateSrcLibPath,flowSrcPath,"Position",[135, 115, 175, 155]);
    set_param(flowSrcPath,"source_type","foundation.enum.constant_controlled.constant",...
        "flow_type","foundation.enum.mass_volumetric_flow.volumetric");
    add_block(reservoirTLLibPath,reservoir2Path,"Position",[480, 200, 520, 240]);
    add_block(PSSimulinkConverterLibPath,PSSimulinkConverterPath,"Position",[390 107 405 123])
    add_block(scopeLibPath,scopePath,"Position",[430, 99, 460, 131]);

    % Add Array Connection block and set domain for cooling plate
    % to battery connection
    add_block(arrayConnLibPath, arrayConnPath, "Position", [100, 5, 135, 60]);
    set_param(arrayConnPath,"Domain","foundation.thermal.thermal");

    % Set parameters in array connection
    set_param(arrayConnPath,"Mode","Sized Elements");
    numThermalNodes = str2double(get_param(dstCoolingPlateBlkPath,"numBattThermalNodes"));
    elementSizeArray = repmat("[1,1]", numThermalNodes, 1);  % Assuming lumped module
    set_param(arrayConnPath, "ElementSizes", elementSizeArray);

    % Connect test harness blocks with cooling plate
    for i=1:numThermalNodes
        ThermalArrayPort = strcat("elementNode",string(i));
        simscape.addConnection(arrayConnPath,ThermalArrayPort,heatFlowSrcPath,"B","autorouting","smart");
    end

    simscape.addConnection(thermalRefPath,"H",heatFlowSrcPath,"A","autorouting","smart");
    simscape.addConnection(reservoir1Path,"A",flowSrcPath,"A","autorouting","smart");
    simscape.addConnection(solverConfigPath,"port",flowSrcPath,"A","autorouting","smart");
    simscape.addConnection(flowSrcPath,"B",dstCoolingPlateBlkPath,"fluid_in","autorouting","smart");
    simscape.addConnection(dstCoolingPlateBlkPath,"fluid_out",reservoir2Path,"A","autorouting","smart");
    simscape.addConnection(dstCoolingPlateBlkPath,"Tp",PSSimulinkConverterPath,"input","autorouting","smart");
    add_line(modelName,sprintf("PS-Simulink\nConverter/1"),"Scope/1","autorouting","smart");
    simscape.addConnection(dstCoolingPlateBlkPath,"Surf1",arrayConnPath,"arrayNode","autorouting","smart");

    % Set parameters of test harness
    set_param(heatFlowSrcPath,"heat_flow",string(options.BattHeatFlowRate.value),"heat_flow_unit",string(options.BattHeatFlowRate.unit));
    set_param(reservoir1Path,"reservoir_temperature",string(options.CoolantReservoirInitTemp.value),"reservoir_temperature_unit",string(options.CoolantReservoirInitTemp.unit));
    set_param(reservoir2Path,"reservoir_temperature",string(options.CoolantReservoirInitTemp.value),"reservoir_temperature_unit",string(options.CoolantReservoirInitTemp.unit));
    set_param(flowSrcPath,"volumetric_flow",string(options.CoolantFlowRate.value),"volumetric_flow_unit",string(options.CoolantFlowRate.unit));

    % Enable signal logging with a custom name in logs
    portHandlesConverter = get_param(PSSimulinkConverterPath, 'PortHandles');
    tempPortHandle = portHandlesConverter.Outport;
    set_param(tempPortHandle, 'DataLogging', 'on');
    set_param(tempPortHandle, 'DataLoggingNameMode', 'Custom');
    set_param(tempPortHandle, 'DataLoggingName', 'Tp');

    % Set model canvas zoom factor to 100
    set_param(gcs, 'ZoomFactor', '100');

    % Enable scalable compilation for test harness model
    set_param(modelName, 'SimscapeCompileComponentReuse', 'on');

else
    error(['An object of the class ComponentConnectivity does not exist. To ' ...
        'generate battery cooling plate test harness, first create ' ...
        'an object of the class ComponentConnectivity.']);
end

end