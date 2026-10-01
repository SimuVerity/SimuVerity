function plotCoolingChannels(ConnectivityData, options)
% This function draws cooling flow network defined in ConnectivityData as line
% segments over a cooling plate
%
%   plotCoolingChannels(ConnectivityData, options)
%   allows customization of the plotting axes, dimensionality (2D or 3D),
%   channel elevation, colors, and line styling.
%
%   The function:
%       - Draws cooling flow channels as connected line segments
%       - Supports both 2D (planar) and 3D visualization
%       - Draws exactly ONE inlet arrow (source) and ONE outlet arrow (sink)
%       - Applies appropriate directional offsets to clearly indicate flow
%         direction
%
%   Inputs:
%       ConnectivityData - Structure defining the cooling channel network.
%                          This structure contains flow network connectivity 
%                          information and geometry data.
%
%   Optional name-value inputs (options):
%       Axis            - Target axes for plotting. Can be a standard Axes
%                         or UIAxes object.
%       PlotType        - Plot dimensionality:
%                         "2D" plots channels in the XY plane
%                         "3D" plots channels at a specified Z level
%       ZLevel          - Z-coordinate used for 3D plotting of channels.
%                         Ignored when plotType is "2D".      
%       PipeColor       - RGB color used for cooling channel lines.(Default: magenta)                  
%       ArrowInColor    - RGB color of the inlet (source) arrow. (Default: blue)               
%       ArrowOutColor   - RGB color of the outlet (sink) arrow. (Default: red)                  
%       LineWidth       - Line width of the channel paths.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    ConnectivityData struct
    options.Axis {mustBeA(options.Axis,["matlab.graphics.axis.Axes","matlab.ui.control.UIAxes"])} = gca;
    options.PlotType {mustBeMember(options.PlotType,["2D","3D"])} = "3D";
    options.ZLevel (1,1) double = 0;
    options.PipeColor = [255,0,255]/255; %[255,191,0]/255; 
    options.ArrowInColor = [0 0 1];
    options.ArrowOutColor = [1 0 0];
    options.LineWidth = 3;
end

arrowScale = 0.15;        % fraction of pipe length
arrowOffsetFactor = 0.10; % fraction of pipe length
zArrow = options.ZLevel;

if options.PlotType == "3D"
    hold(options.Axis,"on")
else
    hold(options.Axis,"off")
end

sourceArrowDrawn = false;
sinkArrowDrawn   = false;

for iComp = 1:numel(ConnectivityData)

    %% Pipes
    if contains(ConnectivityData(iComp).Component,"Pipe")

        pos = value(ConnectivityData(iComp).Parameters.position);

        x1 = pos(1); y1 = pos(2);
        x2 = pos(3); y2 = pos(4);

        % Draw pipe
        if options.PlotType == "3D"
            plot3(options.Axis, ...
                [x1 x2], ...
                [y1 y2], ...
                [options.ZLevel options.ZLevel], ...
                "LineWidth", options.LineWidth, ...
                "Color", options.PipeColor);
        else
            plot(options.Axis, ...
                [x1 x2], ...
                [y1 y2], ...
                "LineWidth", options.LineWidth, ...
                "Color", options.PipeColor);
            xlabel(options.Axis,"X Position (m)");
            ylabel(options.Axis,"Y Position (m)");
            title(options.Axis,"Cooling channel network schematic");

            hold(options.Axis,"on")
        end

        % Direction vector
        dx = x2 - x1;
        dy = y2 - y1;
        L  = hypot(dx,dy);
        if L == 0
            continue
        end

        ux = dx / L;
        uy = dy / L;

        arrowLen    = arrowScale * L;
        arrowOffset = arrowOffsetFactor * L;

        %% Flow entry arrow (Source)
        if ~sourceArrowDrawn && ...
                isfield(ConnectivityData(iComp),'Connectivity') && ...
                strcmpi(ConnectivityData(iComp).Connectivity.portAConnectedComponent,"source")

            % Tail is further back, head stops before entry point
            xTail = x1 - (arrowOffset + arrowLen)*ux;
            yTail = y1 - (arrowOffset + arrowLen)*uy;

            quiver3(options.Axis, ...
                xTail, yTail, zArrow, ...
                arrowLen*ux, arrowLen*uy, 0, ...
                "Color", options.ArrowInColor, ...
                "LineWidth", 2, ...
                "MaxHeadSize", 0.8, ...
                "AutoScale","off");

            sourceArrowDrawn = true;
        end

        %% Flow exit arrow (Sink)
        if ~sinkArrowDrawn && ...
                isfield(ConnectivityData(iComp),'Connectivity') && ...
                strcmpi(ConnectivityData(iComp).Connectivity.portBConnectedComponent,"sink")

            % Tail starts after exit point
            xTail = x2 + arrowOffset*ux;
            yTail = y2 + arrowOffset*uy;

            quiver3(options.Axis, ...
                xTail, yTail, zArrow, ...
                arrowLen*ux, arrowLen*uy, 0, ...
                "Color", options.ArrowOutColor, ...
                "LineWidth", 2, ...
                "MaxHeadSize", 0.8, ...
                "AutoScale","off");

            sinkArrowDrawn = true;
        end

        %% Bends
    elseif contains(ConnectivityData(iComp).Component,"Bend")

        pts = value(ConnectivityData(iComp).Parameters.centerlinePts);

        if options.PlotType == "3D"
        plot3(options.Axis, ...
            pts(:,1), ...
            pts(:,2), ...
            options.ZLevel*ones(size(pts,1),1), ...
            "LineWidth", options.LineWidth, ...
            "Color", options.PipeColor);
        else
            plot(options.Axis, ...
            pts(:,1), ...
            pts(:,2), ...
            "LineWidth", options.LineWidth, ...
            "Color", options.PipeColor);
        end

    end
end

hold(options.Axis,"off")

end