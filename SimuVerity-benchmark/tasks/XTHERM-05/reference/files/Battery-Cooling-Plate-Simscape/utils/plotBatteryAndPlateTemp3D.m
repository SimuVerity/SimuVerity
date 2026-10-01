function plotBatteryAndPlateTemp3D(simlogNode, batteryName, batteryData, ...
    logsout, coolingPlateData, timeInstance, options)
% This function creates a 3-D plot of the temperature distribution of the 
% battery pack and the cooling plate for a load cycle at a given time instance.
%
%   Inputs:
%       simlogNode       - simscape.logging.Node object.
%       batteryName      - Name of the battery pack.
%       batteryData      - struct consisting of battery pack data (data 
%                          exported as .MAT file by Battery Builder app).
%       logsout          - Simulation logsout object; first element must contain
%                          a timeseries object with partition temperatures.
%       coolingPlateData - An instance of the class ComponentConnectivity.
%       timeInstance     - Time instance (sec) of logged data for plot.
%
%   Optional inputs:
%       LocationCoolingPlate - Location of cooling plate relative
%                              to the battery pack (Bottom or Top).
%       GapBatteryToPlate    - Gap between battery pack and cooling
%                              plate only for visual representation in plot.
%       CycleName            - Name of load cycle.
%       Axis                 - Plot axis of class matlab.graphics.axis.Axes
%       ShowBattery          - Battery visualization enabled (=true) 
%                              or disabled (=false) in plot.
%       ShowCoolingPlate     - Cooling plate visualization enabled (=true) 
%                              or disabled (=false) in plot.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    simlogNode simscape.logging.Node
    batteryName (1,1) string
    batteryData struct {mustBeNonempty}
    logsout Simulink.SimulationData.Dataset
    coolingPlateData ComponentConnectivity
    timeInstance (1,1) double
    options.LocationCoolingPlate (1,1) string ...
        {mustBeMember(options.LocationCoolingPlate,["Top","Bottom"])} = "Bottom"
    options.GapBatteryToPlate (1,1) double = 0.01
    options.CycleName (1,1) string = "Charging"
    options.Axis = []
    options.ShowBattery = true;
    options.ShowCoolingPlate = true;
end


% Figure setup & Axes management

if isempty(options.Axis)
    fig = figure("Color","w");
    ax = axes(fig);
    ownsAxes = true;
else
    ax = options.Axis;
    validateattributes(ax, ...
        {'matlab.graphics.axis.Axes','matlab.ui.control.UIAxes'}, ...
        {'scalar','nonempty'});
    ownsAxes = false;
end

axis(ax,"equal")
daspect(ax,[1 1 0.25])
view(ax,3)

xlabel(ax,'X (Cell Length) in m')
ylabel(ax,'Y (Cell Stack Direction) in m')
zlabel(ax,'Z (Cell Height) in m')

grid(ax,"on")
box(ax,"on")
rotate3d on;

%% Battery Cell Groups
if options.ShowBattery == true

    logBattery = simlogNode.(batteryName);
    moduleAssemblyData = batteryData.(batteryName);

    cellLengthX = moduleAssemblyData.ModuleAssembly(1).Module(1) ...
        .ParallelAssembly.Cell.Geometry.Length.value;

    cellWidthY  = moduleAssemblyData.ThermalNodes.Bottom.Dimensions(1,2);
    cellHeightZ = moduleAssemblyData.ModuleAssembly(1).Module(1) ...
        .ParallelAssembly.Cell.Geometry.Height.value;

    % Determine number of thermal models for each cell in the model
    modelNameBattThermalSys = simlogNode.id;
    numDiscreteCellZ = str2num(get_param(strcat(modelNameBattThermalSys,"/",...
        batteryName,"/ModuleAssembly1/Module1"),"NumThermalModelsCell"));

    dz = cellHeightZ / numDiscreteCellZ;

    countThermalNode = 0;
    locBottom = moduleAssemblyData.ThermalNodes.Bottom.Locations;

    for iAsm = 1:numel(moduleAssemblyData.ModuleAssembly)

        asm = moduleAssemblyData.ModuleAssembly(iAsm);

        for iMod = 1:numel(asm.Module)

            mod = asm.Module(iMod);
            numGroups = mod.NumModels;

            for iGrp = 1:numGroups

                % XY bounds
                countThermalNode = countThermalNode + 1;

                x0 = locBottom(countThermalNode,1) - 0.5*cellLengthX;
                y0 = locBottom(countThermalNode,2) - 0.5*cellWidthY;
                x1 = x0 + cellLengthX;
                y1 = y0 + cellWidthY;

                % Z temperatures
                Tz = zeros(numDiscreteCellZ,1);

                for kZ = 1:numDiscreteCellZ
                    asmField = sprintf('ModuleAssembly%d', iAsm);
                    modField = sprintf('Module%d', iMod);

                    ts = logBattery.(asmField).(modField) ...
                        .BattEqCircuitCell(iGrp).HDistributed(kZ).T.series;

                    [~, idx] = min(abs(ts.time - timeInstance));
                    TVals = ts.values;
                    Tz(kZ) = TVals(idx);

                end

                % Draw voxel stack
                for kZ = 1:numDiscreteCellZ
                    zTop = cellHeightZ - (kZ-1)*dz;
                    zBot = zTop - dz;
                    TTop = Tz(kZ);
                    TBot = Tz(min(kZ+1,end));

                    drawCuboidZGradient( ...
                        x0, x1, ...
                        y0, y1, ...
                        zBot, zTop, ...
                        TBot, TTop);
                end
            end
        end
    end

end

if options.ShowCoolingPlate == true
    %% Cooling Plate Partitions

    tempTS = logsout{1}.Values;
    [~, idx] = min(abs(tempTS.Time - timeInstance));
    plateTemps = squeeze(tempTS.Data(1,:,idx));

    if options.LocationCoolingPlate == "Bottom"
        zPlateTop    = -options.GapBatteryToPlate;
    elseif options.LocationCoolingPlate == "Top"
        zPlateTop = cellHeightZ + options.GapBatteryToPlate + coolingPlateData.MaterialProp.ThicknessPlate.value;
    end

    zPlateBottom = zPlateTop - coolingPlateData.MaterialProp.ThicknessPlate.value;

    nPartitions = numel(coolingPlateData.Partition);

    for iP = 1:nPartitions

        corners = coolingPlateData.Partition(iP).Corners;

        x0 = min(corners(:,1));
        x1 = max(corners(:,1));
        y0 = min(corners(:,2));
        y1 = max(corners(:,2));

        T = plateTemps(iP);

        drawCuboid( ...
            x0, x1, ...
            y0, y1, ...
            zPlateBottom, zPlateTop, ...
            T,"w");

    end

    %% Cooling Channels (3-D Overlay)

    % Small lift above plate for visibility
    zChannel = zPlateTop + 1e-4;

    plotCoolingChannels(coolingPlateData.ConnectivityData,Axis=ax, PlotType="3D", ...
        ZLevel=zChannel, LineWidth=1.5);

end

if ownsAxes
    if options.ShowBattery == true && options.ShowCoolingPlate == true
        title(ax, sprintf("Battery & Cold Plate Temperature (%s cycle) at t = %.1f s", ...
            options.CycleName, timeInstance))
    elseif options.ShowBattery == true && options.ShowCoolingPlate == false
        title(ax, sprintf("Battery Temperature (%s cycle) at t = %.1f s", ...
            options.CycleName, timeInstance))
    elseif options.ShowBattery == false && options.ShowCoolingPlate == true
        title(ax, sprintf("Cold Plate Temperature (%s cycle) at t = %.1f s", ...
            options.CycleName, timeInstance))
    end
end

rotate3d on;
hold off;


end

function drawCuboid(x1,x2,y1,y2,z1,z2,value,edgeColor)

% 8 vertices
V = [ ...
    x1 y1 z1;
    x2 y1 z1;
    x2 y2 z1;
    x1 y2 z1;
    x1 y1 z2;
    x2 y1 z2;
    x2 y2 z2;
    x1 y2 z2 ];

% 6 faces
F = [ ...
    1 2 3 4;  % bottom
    5 6 7 8;  % top
    1 2 6 5;  % front
    2 3 7 6;  % right
    3 4 8 7;  % back
    4 1 5 8]; % left

patch('Vertices', V, ...
    'Faces', F, ...
    'FaceVertexCData', value * ones(8,1), ...
    'FaceColor', 'flat', ...
    'EdgeColor', edgeColor);

end

function drawCuboidZGradient(x0,x1,y0,y1,z0,z1,Tbot,Ttop)

% Vertices
V = [
    x0 y0 z0;  % 1
    x1 y0 z0;  % 2
    x1 y1 z0;  % 3
    x0 y1 z0;  % 4
    x0 y0 z1;  % 5
    x1 y0 z1;  % 6
    x1 y1 z1;  % 7
    x0 y1 z1;  % 8
    ];

% Per-vertex temperatures (Z-gradient only)
C = [
    Tbot; Tbot; Tbot; Tbot;
    Ttop; Ttop; Ttop; Ttop
    ];

%% Bottom face (XY, flat)
patch('Vertices',V,'Faces',[1 2 3 4], ...
    'FaceColor','flat', ...
    'FaceVertexCData',Tbot, ...
    'EdgeColor','k');

%% Top face (XY, flat)
patch('Vertices',V,'Faces',[5 6 7 8], ...
    'FaceColor','flat', ...
    'FaceVertexCData',Ttop, ...
    'EdgeColor','k');

%% Side faces (YZ + XZ, interpolated in Z)
sideFaces = [1 2 6 5;  % XZ
    2 3 7 6;           % YZ
    3 4 8 7;           % XZ
    4 1 5 8];          % YZ

patch('Vertices',V,'Faces',sideFaces, ...
    'FaceVertexCData',C, ...
    'FaceColor','interp', ...
    'EdgeColor','k');

end