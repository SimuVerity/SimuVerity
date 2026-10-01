function ConnectivityData = createConnectivityDataStruct(design,index,uiaxes,options)
% This function creates a connectivity data structure describing the layout and
% interconnections of cooling channels for a cooling plate design and
% visualizes the channel layout on the specified UI axes.
%
% ConnectivityData = createConnectivityDataStruct(..., options)
%   additionally allows customization of channel geometry and layout
%   parameters using name-value pair arguments.
%
%   Inputs:
%       design           - Cooling channel layout type. Must be either:
%                          "Parallel" or "Serpentine".
%       index            - Configuration index of the cooling plate for
%                          which the connectivity data is generated.
%       uiaxes           - UIAxes handle used for plotting the channel layout.
%
%   Optional inputs (Name-Value Pairs):
%       nChannels        - Number of parallel channels in the cooling plate.
%                          Must be an integer greater than 1. (Default: 5)
%       nTurns           - Number of turns in a serpentine channel layout.
%       lChannel         - Length of an individual channel.
%       dChannel         - Diameter of the cooling channels.
%       spacingChannel   - Center-to-center spacing between adjacent channels.
%       dDistributor     - Diameter of the inlet and outlet distributor
%
%   Output:
%       ConnectivityData - Structure defining the cooling channel network.
%                          This structure contains flow network connectivity 
%                          information and geometry data.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    design (1,1) string {mustBeMember(design,["Parallel","Serpentine"])}
    index (1,1) {mustBeInteger}
    uiaxes (1,1) matlab.ui.control.UIAxes
    options.nChannels (1,1) {mustBeInteger, mustBeGreaterThan(options.nChannels,1)} = 5;
    options.nTurns (1,1) {mustBeInteger} = 4;
    options.lChannel (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.lChannel, 'm')} = simscape.Value(0.2,"m");
    options.dChannel (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.dChannel, 'm')} = simscape.Value(0.002,"m");
    options.spacingChannel (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.spacingChannel, 'm')} = simscape.Value(0.05,"m");
    options.dDistributor (1,1) simscape.Value {simscape.mustBeCommensurateUnit(options.dDistributor, 'm')} = simscape.Value(0.002,"m");
end

clear ConnectivityData

ConnectivityData = struct;
xRef = 0; yRef = 0;

% Convert values of channel length and inter-channel spacing to common
% units
lenChannel = convert(options.lChannel,string(unit(options.dChannel)));
spaceChannel = convert(options.spacingChannel,string(unit(options.dChannel)));

if strcmp(design,"Parallel")
    % Assumption: Bend radius or corner fillet radius is equal to diameter of
    % parallel cooling channel
    rBend = value(options.dChannel);
elseif strcmp(design,"Serpentine")
    rBend = value(0.5*spaceChannel);
end

if strcmp(design,"Parallel")
    % ------ Create connectivity data (Component name & diameter) for Cooling channels -------
    for iComp = 1:options.nChannels
        ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
        ConnectivityData(iComp).Parameters.diameter = options.dChannel;
    end

    switch index
        case 1 % Channels along X-axis; Flow bottom left to top right in XY plane

            % ------- Create connectivity data (Component name & diameter) for Distributor pipes ------
            for iComp = options.nChannels+1:options.nChannels+2*(options.nChannels-1)
                ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
                ConnectivityData(iComp).Parameters.diameter = options.dDistributor;
            end

            % ------- Create connectivity data (Component name & diameter) for Bends ------
            for iComp = 3*options.nChannels-1:3*options.nChannels
                ConnectivityData(iComp).Component = strcat("Bend",string(iComp - 3*options.nChannels + 2));
                ConnectivityData(iComp).Parameters.diameter = options.dChannel;
            end

            % ------ Create connectivity data for Cooling channels -------

            % Bottom edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef+value(lenChannel)-rBend  yRef],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend2";

            % Central channels
            for iComp = 2:options.nChannels-1
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp - 1)*value(spaceChannel) ...
                    xRef+value(lenChannel)  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1+options.nChannels));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1+2*options.nChannels));
            end

            % Top edge channel
            ConnectivityData(options.nChannels).Parameters.position = simscape.Value([xRef+rBend yRef+(options.nChannels - 1)*value(spaceChannel) ...
                xRef+value(lenChannel)  yRef+(options.nChannels - 1)*value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(options.nChannels).Connectivity.portAConnectedComponent = "Bend1";
            ConnectivityData(options.nChannels).Connectivity.portBConnectedComponent = "sink";

            % ------- Create connectivity data for Distributor pipes ------

            % Left edge pipes
            for iComp = options.nChannels+1:2*options.nChannels-2
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel) ...
                    xRef  yRef+(iComp-options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                if iComp == options.nChannels+1
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                else
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                end
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
            end


            % Top-left corner pipe
            ConnectivityData(2*options.nChannels-1).Parameters.position = simscape.Value([xRef yRef+(options.nChannels-2)*value(spaceChannel) ...
                xRef  yRef+(options.nChannels-1)*value(spaceChannel)-rBend],string(unit(options.dChannel)));
            if options.nChannels > 2
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-2));
            else
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = "source";
            end
            ConnectivityData(2*options.nChannels-1).Connectivity.portBConnectedComponent = "Bend1";

            % Bottom-right corner pipe
            ConnectivityData(2*options.nChannels).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+rBend ...
                xRef+value(lenChannel)  yRef+value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(2*options.nChannels).Connectivity.portAConnectedComponent = "Bend2";
            if options.nChannels > 2
                ConnectivityData(2*options.nChannels).Connectivity.portBConnectedComponent = strcat("Pipe",string(2*options.nChannels+1));
            else
                ConnectivityData(2*options.nChannels).Connectivity.portBConnectedComponent = "sink";
            end

            % Right edge pipes
            for iComp = 2*options.nChannels+1:3*options.nChannels-2
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel) ...
                    xRef+value(lenChannel)  yRef+(iComp-2*options.nChannels+1)*value(spaceChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                if iComp == 3*options.nChannels-2
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                else
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                end

            end

            % ------- Create connectivity data for Bends ------
            % Top-left bend
            ConnectivityData(3*options.nChannels-1).Parameters.position = simscape.Value([xRef yRef+(options.nChannels-1)*value(spaceChannel)-rBend ...
                xRef+rBend yRef+(options.nChannels - 1)*value(spaceChannel)],string(unit(options.dChannel)));
            bend1Pts = generateBendPts([value(ConnectivityData(3*options.nChannels-1).Parameters.position(1))  value(ConnectivityData(3*options.nChannels-1).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels-1).Parameters.position(3)) value(ConnectivityData(3*options.nChannels-1).Parameters.position(4))], rBend, "CW");
            ConnectivityData(3*options.nChannels-1).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-1));
            ConnectivityData(3*options.nChannels-1).Connectivity.portBConnectedComponent = strcat("Pipe",string(options.nChannels));

            % Bottom-right bend
            ConnectivityData(3*options.nChannels).Parameters.position = simscape.Value([xRef+value(lenChannel)-rBend  yRef ...
                xRef+value(lenChannel) yRef+rBend],string(unit(options.dChannel)));
            bend2Pts = generateBendPts([value(ConnectivityData(3*options.nChannels).Parameters.position(1))  value(ConnectivityData(3*options.nChannels).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels).Parameters.position(3)) value(ConnectivityData(3*options.nChannels).Parameters.position(4))], rBend, "CCW");            
            ConnectivityData(3*options.nChannels).Parameters.centerlinePts = simscape.Value(bend2Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels).Connectivity.portAConnectedComponent = "Pipe1";
            ConnectivityData(3*options.nChannels).Connectivity.portBConnectedComponent = strcat("Pipe",string(2*options.nChannels));

        case 2 % Channels along X-axis; Flow bottom left to bottom right in XY plane

            % ------- Create connectivity data (Component name & diameter) for Distributor pipes ------
            for iComp = options.nChannels+1:options.nChannels+2*(options.nChannels-1)
                ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
                ConnectivityData(iComp).Parameters.diameter = options.dDistributor;
            end

            % ------- Create connectivity data (Component name & diameter) for Bends ------
            for iComp = 3*options.nChannels-1:3*options.nChannels
                ConnectivityData(iComp).Component = strcat("Bend",string(iComp - 3*options.nChannels + 2));
                ConnectivityData(iComp).Parameters.diameter = options.dChannel;
            end

            % ------ Create connectivity data for Cooling channels -------

            % Bottom edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef+value(lenChannel) yRef],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "sink";

            % Central channels
            for iComp = 2:options.nChannels-1
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp - 1)*value(spaceChannel) ...
                    xRef+value(lenChannel)  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1+options.nChannels));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-2+2*options.nChannels));
            end

            % Top edge channel
            ConnectivityData(options.nChannels).Parameters.position = simscape.Value([xRef+rBend yRef+(options.nChannels - 1)*value(spaceChannel) ...
                xRef+value(lenChannel)-rBend  yRef+(options.nChannels - 1)*value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(options.nChannels).Connectivity.portAConnectedComponent = "Bend1";
            ConnectivityData(options.nChannels).Connectivity.portBConnectedComponent = "Bend2";

            % ------- Create connectivity data for Distributor pipes ------

            % Left edge pipes
            for iComp = options.nChannels+1:2*options.nChannels-2
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel) ...
                    xRef yRef+(iComp-options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                if iComp == options.nChannels+1
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                else
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                end
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
            end

            % Top-left corner pipe
            ConnectivityData(2*options.nChannels-1).Parameters.position = simscape.Value([xRef yRef+(options.nChannels-2)*value(spaceChannel) ...
                xRef yRef+(options.nChannels-1)*value(spaceChannel)-rBend],string(unit(options.dChannel)));
            if options.nChannels > 2
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-2));
            else
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = "source";
            end
            ConnectivityData(2*options.nChannels-1).Connectivity.portBConnectedComponent = "Bend1";

            % Right edge pipes - assumed flow downwards (along -ve Y-axis)
            for iComp = 2*options.nChannels:3*options.nChannels-3
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels+1)*value(spaceChannel) ...
                    xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));

                if options.nChannels > 2
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                else
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = "Bend2";
                end

                if iComp == 2*options.nChannels
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                else
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                end

            end

            % Top-right corner pipe - assumed flow downwards (along -ve Y-axis)
            ConnectivityData(3*options.nChannels-2).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(options.nChannels-1)*value(spaceChannel)-rBend ...
                xRef+value(lenChannel) yRef+(options.nChannels-2)*value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels-2).Connectivity.portAConnectedComponent = "Bend2";
            ConnectivityData(3*options.nChannels-2).Connectivity.portBConnectedComponent = strcat("Pipe",string(3*options.nChannels-3));

            % ------- Create connectivity data for Bends ------
            % Top-left bend
            ConnectivityData(3*options.nChannels-1).Parameters.position = simscape.Value([xRef yRef+(options.nChannels-1)*value(spaceChannel)-rBend ...
                xRef+rBend yRef+(options.nChannels - 1)*value(spaceChannel)],string(unit(options.dChannel)));
            bend1Pts = generateBendPts([value(ConnectivityData(3*options.nChannels-1).Parameters.position(1))  value(ConnectivityData(3*options.nChannels-1).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels-1).Parameters.position(3)) value(ConnectivityData(3*options.nChannels-1).Parameters.position(4))], rBend, "CW");            
            ConnectivityData(3*options.nChannels-1).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-1));
            ConnectivityData(3*options.nChannels-1).Connectivity.portBConnectedComponent = strcat("Pipe",string(options.nChannels));

            % Top-right bend
            ConnectivityData(3*options.nChannels).Parameters.position = simscape.Value([xRef+value(lenChannel)-rBend  yRef+(options.nChannels - 1)*value(spaceChannel) ...
                xRef+value(lenChannel) yRef+(options.nChannels - 1)*value(spaceChannel)-rBend],string(unit(options.dChannel)));
            bend2Pts = generateBendPts([value(ConnectivityData(3*options.nChannels).Parameters.position(1))  value(ConnectivityData(3*options.nChannels).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels).Parameters.position(3)) value(ConnectivityData(3*options.nChannels).Parameters.position(4))], rBend, "CW");            
            ConnectivityData(3*options.nChannels).Parameters.centerlinePts = simscape.Value(bend2Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels).Connectivity.portAConnectedComponent = strcat("Pipe",string(options.nChannels));
            ConnectivityData(3*options.nChannels).Connectivity.portBConnectedComponent = strcat("Pipe",string(3*options.nChannels-2));


        case 3 % Channels along X-axis: Flow central-left to central-right in XY plane

            % ------ Create connectivity data for Cooling channels -------

            % Bottom edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef+rBend yRef ...
                xRef+value(lenChannel)-rBend yRef],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "Bend1";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend3";

            % Central channels
            for iComp = 2:options.nChannels-1
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp - 1)*value(spaceChannel) ...
                    xRef+value(lenChannel)  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));

                if mod(options.nChannels,2) == 0 % when total even number of channels
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+options.nChannels));
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+2*options.nChannels));
                elseif iComp < (options.nChannels+1)/2 % when total odd number of channels & for bottom half channels
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+options.nChannels));
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+2*options.nChannels-1));
                elseif iComp == (options.nChannels+1)/2 % when total odd number of channels & for the central channel
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                else % when total odd number of channels & for top half channels
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+options.nChannels-1));
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+2*options.nChannels-2));
                end

            end

            % Top edge channel
            ConnectivityData(options.nChannels).Parameters.position = simscape.Value([xRef+rBend yRef+(options.nChannels - 1)*value(spaceChannel) ...
                xRef+value(lenChannel)-rBend  yRef+(options.nChannels - 1)*value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(options.nChannels).Connectivity.portAConnectedComponent = "Bend2";
            ConnectivityData(options.nChannels).Connectivity.portBConnectedComponent = "Bend4";

            % ------- Create connectivity data for Distributor pipes ------

            if mod(options.nChannels,2) == 0 % when total even number of channels

                for iComp = options.nChannels+1:3*options.nChannels
                    ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
                    ConnectivityData(iComp).Parameters.diameter = options.dDistributor;
                end

                % Left edge pipes
                for iComp = options.nChannels+1:2*options.nChannels
                    if iComp == options.nChannels+1
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+value(spaceChannel) ...
                            xRef yRef+rBend],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "Bend1";
                    elseif iComp < 3*options.nChannels/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    elseif iComp == 3*options.nChannels/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-0.5)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    elseif iComp == 3*options.nChannels/2 + 1
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-1.5)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    elseif iComp < 2*options.nChannels
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-2)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    else
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-2)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)-rBend],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "Bend2";
                    end

                end

                % Right edge pipes
                for iComp = 2*options.nChannels+1:3*options.nChannels
                    if iComp == 2*options.nChannels+1
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+rBend ...
                            xRef+value(lenChannel) yRef+value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "Bend3";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    elseif iComp < 5*options.nChannels/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-1)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    elseif iComp == 5*options.nChannels/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-1)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-0.5)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                    elseif iComp == 5*options.nChannels/2 + 1
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-1)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-1.5)*value(spaceChannel) ],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                    elseif iComp < 3*options.nChannels
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-1)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-2)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    else
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-1)*value(spaceChannel)-rBend ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels-2)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "Bend4";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    end

                end

            else % when total odd number of channels

                for iComp = options.nChannels+1:3*options.nChannels-2
                    ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
                    ConnectivityData(iComp).Parameters.diameter = options.dDistributor;
                end

                % Left edge pipes
                for iComp = options.nChannels+1:2*options.nChannels-1
                    if iComp == options.nChannels+1
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+value(spaceChannel) ...
                            xRef yRef+rBend],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "Bend1";
                    elseif iComp < options.nChannels+(options.nChannels-1)/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    elseif iComp == options.nChannels+(options.nChannels-1)/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    elseif iComp == options.nChannels+(options.nChannels+1)/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    elseif iComp < 2*options.nChannels-1
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    else
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef yRef+(iComp-options.nChannels-1)*value(spaceChannel) ...
                            xRef yRef+(iComp-options.nChannels)*value(spaceChannel)-rBend],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "Bend2";
                    end

                end

                % Right edge pipes
                for iComp = 2*options.nChannels:3*options.nChannels-2
                    if iComp == 2*options.nChannels
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+rBend ...
                            xRef+value(lenChannel) yRef+value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "Bend3";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    elseif iComp < 2*options.nChannels+(options.nChannels-3)/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels+1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                    elseif iComp == 2*options.nChannels+(options.nChannels-3)/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels+1)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                    elseif iComp == 2*options.nChannels+(options.nChannels-1)/2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels+1)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel) ],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                    elseif iComp < 3*options.nChannels-2
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels+1)*value(spaceChannel) ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    else
                        ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+value(lenChannel) yRef+(iComp-2*options.nChannels+1)*value(spaceChannel)-rBend ...
                            xRef+value(lenChannel) yRef+(iComp-2*options.nChannels)*value(spaceChannel)],string(unit(options.dChannel)));
                        ConnectivityData(iComp).Connectivity.portAConnectedComponent = "Bend4";
                        ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                    end

                end

            end

            % ------- Create connectivity data for Bends ------

            % ------- Create connectivity data (Component name & diameter) for Bends ------
            if mod(options.nChannels,2) == 0 % when total even number of channels
                iBend1 = 3*options.nChannels+1;
                iBend4 = 3*options.nChannels+4;
            else % when total odd number of channels
                iBend1 = 3*options.nChannels-1;
                iBend4 = 3*options.nChannels+2;
            end
            for iComp = iBend1:iBend4
                ConnectivityData(iComp).Component = strcat("Bend",string(iComp - iBend1 + 1));
                ConnectivityData(iComp).Parameters.diameter = options.dChannel;
            end
            

            % Bottom-left bend (Bend1)
            if mod(options.nChannels,2) == 0 % when total even number of channels
                iBend1 = 3*options.nChannels+1;               
            else % when total odd number of channels
                iBend1 = 3*options.nChannels-1;             
            end
            ConnectivityData(iBend1).Parameters.position = simscape.Value([xRef yRef+rBend ...
                xRef+rBend yRef],string(unit(options.dChannel)));
            bend1Pts = generateBendPts([value(ConnectivityData(iBend1).Parameters.position(1))  value(ConnectivityData(iBend1).Parameters.position(2))], ...
                [value(ConnectivityData(iBend1).Parameters.position(3)) value(ConnectivityData(iBend1).Parameters.position(4))], rBend, "CCW");
            ConnectivityData(iBend1).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
            ConnectivityData(iBend1).Connectivity.portAConnectedComponent = strcat("Pipe",string(options.nChannels+1));
            ConnectivityData(iBend1).Connectivity.portBConnectedComponent = "Pipe1";

            % Top-left bend (Bend2)            
            if mod(options.nChannels,2) == 0 % when total even number of channels
                iBend2 = 3*options.nChannels+2;
                ConnectivityData(3*options.nChannels+2).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels));
            else % when total odd number of channels
                iBend2 = 3*options.nChannels;
                ConnectivityData(3*options.nChannels).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-1));              
            end
            ConnectivityData(iBend2).Parameters.position = simscape.Value([xRef yRef+(options.nChannels-1)*value(spaceChannel)-rBend ...
                xRef+rBend yRef+(options.nChannels - 1)*value(spaceChannel)],string(unit(options.dChannel)));
            bend2Pts = generateBendPts([value(ConnectivityData(iBend2).Parameters.position(1))  value(ConnectivityData(iBend2).Parameters.position(2))], ...
                [value(ConnectivityData(iBend2).Parameters.position(3)) value(ConnectivityData(iBend2).Parameters.position(4))], rBend, "CW");
            ConnectivityData(iBend2).Parameters.centerlinePts = simscape.Value(bend2Pts,string(unit(options.dChannel)));
            ConnectivityData(iBend2).Connectivity.portBConnectedComponent = strcat("Pipe",string(options.nChannels));
            
            % Bottom-right bend (Bend3)
            if mod(options.nChannels,2) == 0 % when total even number of channels
                iBend3 = 3*options.nChannels+3;
                ConnectivityData(iBend3).Connectivity.portBConnectedComponent = strcat("Pipe",string(2*options.nChannels+1));
            else % when total odd number of channels
                iBend3 = 3*options.nChannels+1;
                ConnectivityData(iBend3).Connectivity.portBConnectedComponent = strcat("Pipe",string(2*options.nChannels));
            end
            ConnectivityData(iBend3).Parameters.position = simscape.Value([xRef+value(lenChannel)-rBend  yRef ...
                xRef+value(lenChannel) yRef+rBend],string(unit(options.dChannel)));
            bend3Pts = generateBendPts([value(ConnectivityData(iBend3).Parameters.position(1))  value(ConnectivityData(iBend3).Parameters.position(2))], ...
                [value(ConnectivityData(iBend3).Parameters.position(3)) value(ConnectivityData(iBend3).Parameters.position(4))], rBend, "CCW");            
            ConnectivityData(iBend3).Parameters.centerlinePts = simscape.Value(bend3Pts,string(unit(options.dChannel)));
            ConnectivityData(iBend3).Connectivity.portAConnectedComponent = "Pipe1";
            
            % Top-right bend (Bend4)
            if mod(options.nChannels,2) == 0 % when total even number of channels
                iBend4 = 3*options.nChannels+4;
                ConnectivityData(iBend4).Connectivity.portBConnectedComponent = strcat("Pipe",string(3*options.nChannels));
            else % when total odd number of channels
                iBend4 = 3*options.nChannels+2;
                ConnectivityData(iBend4).Connectivity.portBConnectedComponent = strcat("Pipe",string(3*options.nChannels-2));
            end
            ConnectivityData(iBend4).Parameters.position = simscape.Value([xRef+value(lenChannel)-rBend  yRef+(options.nChannels-1)*value(spaceChannel) ...
                xRef+value(lenChannel) yRef+(options.nChannels-1)*value(spaceChannel)-rBend],string(unit(options.dChannel)));
            bend4Pts = generateBendPts([value(ConnectivityData(iBend4).Parameters.position(1))  value(ConnectivityData(iBend4).Parameters.position(2))], ...
                [value(ConnectivityData(iBend4).Parameters.position(3)) value(ConnectivityData(iBend4).Parameters.position(4))], rBend, "CW");            
            ConnectivityData(iBend4).Parameters.centerlinePts = simscape.Value(bend4Pts,string(unit(options.dChannel)));
            ConnectivityData(iBend4).Connectivity.portAConnectedComponent = strcat("Pipe",string(options.nChannels));
     

        case 4 % Channels along Y-axis; Flow bottom left to top right in XY plane

             % ------- Create connectivity data (Component name & diameter) for Distributor pipes ------
            for iComp = options.nChannels+1:options.nChannels+2*(options.nChannels-1)
                ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
                ConnectivityData(iComp).Parameters.diameter = options.dDistributor;
            end

            % ------- Create connectivity data (Component name & diameter) for Bends ------
            for iComp = 3*options.nChannels-1:3*options.nChannels
                ConnectivityData(iComp).Component = strcat("Bend",string(iComp - 3*options.nChannels + 2));
                ConnectivityData(iComp).Parameters.diameter = options.dChannel;
            end

            % ------ Create connectivity data for Cooling channels -------

            % Left edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef  yRef+value(lenChannel)-rBend],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend1";

            % Central channels
            for iComp = 2:options.nChannels-1
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp - 1)*value(spaceChannel) yRef ...
                    xRef+(iComp - 1)*value(spaceChannel) yRef+value(lenChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1+options.nChannels));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1+2*options.nChannels));
            end

            % Right edge channel
            ConnectivityData(options.nChannels).Parameters.position = simscape.Value([xRef+(options.nChannels - 1)*value(spaceChannel) yRef+rBend ...
                xRef+(options.nChannels - 1)*value(spaceChannel) yRef+value(lenChannel)],string(unit(options.dChannel)));
            ConnectivityData(options.nChannels).Connectivity.portAConnectedComponent = "Bend2";
            ConnectivityData(options.nChannels).Connectivity.portBConnectedComponent = "sink";

            % ------- Create connectivity data for Distributor pipes ------

            % Bottom edge pipes
            for iComp = options.nChannels+1:2*options.nChannels-2
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-options.nChannels-1)*value(spaceChannel) yRef ...
                    xRef+(iComp-options.nChannels)*value(spaceChannel)  yRef],string(unit(options.dChannel)));
                if iComp == options.nChannels+1
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                else
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                end
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
            end

            % Bottom-right corner pipe
            ConnectivityData(2*options.nChannels-1).Parameters.position = simscape.Value([xRef+(options.nChannels-2)*value(spaceChannel) yRef ...
                xRef+(options.nChannels-1)*value(spaceChannel)-rBend  yRef],string(unit(options.dChannel)));
            if options.nChannels > 2
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-2));
            else
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = "source";
            end
            ConnectivityData(2*options.nChannels-1).Connectivity.portBConnectedComponent = "Bend2";

            % Top-left corner pipe
            ConnectivityData(2*options.nChannels).Parameters.position = simscape.Value([xRef+rBend yRef+value(lenChannel) ...
                xRef+value(spaceChannel)  yRef+value(lenChannel)],string(unit(options.dChannel)));
            ConnectivityData(2*options.nChannels).Connectivity.portAConnectedComponent = "Bend1";
            if options.nChannels > 2
                ConnectivityData(2*options.nChannels).Connectivity.portBConnectedComponent = strcat("Pipe",string(2*options.nChannels+1));
            else
                ConnectivityData(2*options.nChannels).Connectivity.portBConnectedComponent = "sink";
            end

            % Top edge pipes
            for iComp = 2*options.nChannels+1:3*options.nChannels-2
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-2*options.nChannels)*value(spaceChannel) yRef+value(lenChannel) ...
                    xRef+(iComp-2*options.nChannels+1)*value(spaceChannel)  yRef+value(lenChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                if iComp == 3*options.nChannels-2
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                else
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
                end

            end

            % ------- Create connectivity data for Bends ------
            % Top-left bend
            ConnectivityData(3*options.nChannels-1).Parameters.position = simscape.Value([xRef yRef+value(lenChannel)-rBend ...
                xRef+rBend yRef+value(lenChannel)],string(unit(options.dChannel)));
            bend1Pts = generateBendPts([value(ConnectivityData(3*options.nChannels-1).Parameters.position(1))  value(ConnectivityData(3*options.nChannels-1).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels-1).Parameters.position(3)) value(ConnectivityData(3*options.nChannels-1).Parameters.position(4))], rBend, "CW");
            ConnectivityData(3*options.nChannels-1).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels-1).Connectivity.portAConnectedComponent = "Pipe1";
            ConnectivityData(3*options.nChannels-1).Connectivity.portBConnectedComponent = strcat("Pipe",string(2*options.nChannels));

            % Bottom-right bend
            ConnectivityData(3*options.nChannels).Parameters.position = simscape.Value([xRef+(options.nChannels-1)*value(spaceChannel)-rBend  yRef ...
                xRef+(options.nChannels - 1)*value(spaceChannel) yRef+rBend],string(unit(options.dChannel)));
            bend2Pts = generateBendPts([value(ConnectivityData(3*options.nChannels).Parameters.position(1))  value(ConnectivityData(3*options.nChannels).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels).Parameters.position(3)) value(ConnectivityData(3*options.nChannels).Parameters.position(4))], rBend, "CCW");            
            ConnectivityData(3*options.nChannels).Parameters.centerlinePts = simscape.Value(bend2Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-1));
            ConnectivityData(3*options.nChannels).Connectivity.portBConnectedComponent = strcat("Pipe",string(options.nChannels));

        case 5 % Channels along Y-axis; Flow bottom left to top left in XY plane

            % ------- Create connectivity data (Component name & diameter) for Distributor pipes ------
            for iComp = options.nChannels+1:options.nChannels+2*(options.nChannels-1)
                ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
                ConnectivityData(iComp).Parameters.diameter = options.dDistributor;
            end

            % ------- Create connectivity data (Component name & diameter) for Bends ------
            for iComp = 3*options.nChannels-1:3*options.nChannels
                ConnectivityData(iComp).Component = strcat("Bend",string(iComp - 3*options.nChannels + 2));
                ConnectivityData(iComp).Parameters.diameter = options.dChannel;
            end

            % ------ Create connectivity data for Cooling channels -------

            % Left edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef  yRef+value(lenChannel)],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "sink";

            % Central channels
            for iComp = 2:options.nChannels-1
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp - 1)*value(spaceChannel) yRef ...
                    xRef+(iComp - 1)*value(spaceChannel) yRef+value(lenChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1+options.nChannels));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-2+2*options.nChannels));
            end

            % Right edge channel
            ConnectivityData(options.nChannels).Parameters.position = simscape.Value([xRef+(options.nChannels - 1)*value(spaceChannel) yRef+rBend ...
                xRef+(options.nChannels - 1)*value(spaceChannel) yRef+value(lenChannel)-rBend],string(unit(options.dChannel)));
            ConnectivityData(options.nChannels).Connectivity.portAConnectedComponent = "Bend1";
            ConnectivityData(options.nChannels).Connectivity.portBConnectedComponent = "Bend2";

            % ------- Create connectivity data for Distributor pipes ------

            % Bottom edge pipes
            for iComp = options.nChannels+1:2*options.nChannels-2
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-options.nChannels-1)*value(spaceChannel) yRef ...
                    xRef+(iComp-options.nChannels)*value(spaceChannel)  yRef],string(unit(options.dChannel)));
                if iComp == options.nChannels+1
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = "source";
                else
                    ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-1));
                end
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp+1));
            end

            % Bottom-right corner pipe
            ConnectivityData(2*options.nChannels-1).Parameters.position = simscape.Value([xRef+(options.nChannels-2)*value(spaceChannel) yRef ...
                xRef+(options.nChannels-1)*value(spaceChannel)-rBend  yRef],string(unit(options.dChannel)));
            if options.nChannels > 2
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-2));
            else
                ConnectivityData(2*options.nChannels-1).Connectivity.portAConnectedComponent = "source";
            end
            ConnectivityData(2*options.nChannels-1).Connectivity.portBConnectedComponent = "Bend1";

            % Top edge pipes
            for iComp = 2*options.nChannels:3*options.nChannels-3
                ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-2*options.nChannels)*value(spaceChannel) yRef+value(lenChannel) ...
                    xRef+(iComp-2*options.nChannels+1)*value(spaceChannel)  yRef+value(lenChannel)],string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp+1));
                if iComp == 2*options.nChannels
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = "sink";
                else
                    ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-1));
                end

            end

            % Top-right corner pipe
            ConnectivityData(3*options.nChannels-2).Parameters.position = simscape.Value([xRef+(options.nChannels-1)*value(spaceChannel)-rBend ...
                yRef+value(lenChannel) xRef+(options.nChannels-2)*value(spaceChannel)  ...
                yRef+value(lenChannel)],string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels-2).Connectivity.portAConnectedComponent = "Bend2";
            if options.nChannels > 2
                ConnectivityData(3*options.nChannels-2).Connectivity.portBConnectedComponent = strcat("Pipe",string(3*options.nChannels-3));
            else
                ConnectivityData(3*options.nChannels-2).Connectivity.portBConnectedComponent = "sink";
            end

            % ------- Create connectivity data for Bends ------
            % Bottom-right bend
            ConnectivityData(3*options.nChannels-1).Parameters.position = simscape.Value([xRef+(options.nChannels-1)*value(spaceChannel)-rBend  yRef ...
                xRef+(options.nChannels - 1)*value(spaceChannel) yRef+rBend],string(unit(options.dChannel)));
            bend1Pts = generateBendPts([value(ConnectivityData(3*options.nChannels-1).Parameters.position(1))  value(ConnectivityData(3*options.nChannels-1).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels-1).Parameters.position(3)) value(ConnectivityData(3*options.nChannels-1).Parameters.position(4))], rBend, "CCW");            
            ConnectivityData(3*options.nChannels-1).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels-1).Connectivity.portAConnectedComponent = strcat("Pipe",string(2*options.nChannels-1));
            ConnectivityData(3*options.nChannels-1).Connectivity.portBConnectedComponent = strcat("Pipe",string(options.nChannels));

            % Top-right bend
            ConnectivityData(3*options.nChannels).Parameters.position = simscape.Value([xRef+(options.nChannels - 1)*value(spaceChannel) yRef+value(lenChannel)-rBend ...
                xRef+(options.nChannels - 1)*value(spaceChannel)-rBend yRef+value(lenChannel)],string(unit(options.dChannel)));
            bend2Pts = generateBendPts([value(ConnectivityData(3*options.nChannels).Parameters.position(1))  value(ConnectivityData(3*options.nChannels).Parameters.position(2))], ...
                [value(ConnectivityData(3*options.nChannels).Parameters.position(3)) value(ConnectivityData(3*options.nChannels).Parameters.position(4))], rBend, "CCW");
            ConnectivityData(3*options.nChannels).Parameters.centerlinePts = simscape.Value(bend2Pts,string(unit(options.dChannel)));
            ConnectivityData(3*options.nChannels).Connectivity.portAConnectedComponent = strcat("Pipe",string(options.nChannels));
            ConnectivityData(3*options.nChannels).Connectivity.portBConnectedComponent = strcat("Pipe",string(3*options.nChannels-2));

    end

elseif strcmp(design,"Serpentine")

    lenCentralChannels = (value(lenChannel) - rBend*(2+pi*options.nTurns))/(options.nTurns+1);

    % ------ Create connectivity data (Component name & diameter) for Cooling channel -------
    for iComp = 1:options.nTurns+1
        ConnectivityData(iComp).Component = strcat("Pipe",string(iComp));
        ConnectivityData(iComp).Parameters.diameter = options.dChannel;
    end

    % ------- Create connectivity data (Component name & diameter) for Bends ------
    for iComp = options.nTurns+2:2*options.nTurns+1
        ConnectivityData(iComp).Component = strcat("Bend",string(iComp - options.nTurns -1));
        ConnectivityData(iComp).Parameters.diameter = options.dChannel;
    end

    switch index
        case 1 % Channels along X-axis: Flow bottom-left to top-right in XY plane - even number of turns

            % ------ Create connectivity data for Cooling channels -------

            % Bottom edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef+lenCentralChannels+rBend yRef],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend1";

            % Central channels
            for iComp = 2:options.nTurns
                if mod(iComp,2) == 0 % even-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+lenCentralChannels+rBend yRef+(iComp - 1)*value(spaceChannel) ...
                        xRef+rBend  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));
                else % odd-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+rBend yRef+(iComp - 1)*value(spaceChannel) ...
                        xRef+lenCentralChannels+rBend  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));
                end
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Bend",string(iComp-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Bend",string(iComp));
            end

            % Top edge channel
            ConnectivityData(options.nTurns+1).Parameters.position = simscape.Value([xRef+rBend yRef+(options.nTurns)*value(spaceChannel) ...
                xRef+lenCentralChannels+2*rBend  yRef+(options.nTurns)*value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(options.nTurns+1).Connectivity.portAConnectedComponent = strcat("Bend",string(options.nTurns));
            ConnectivityData(options.nTurns+1).Connectivity.portBConnectedComponent = "sink";

            % ------- Create connectivity data for Bends ------

            for iComp = options.nTurns+2:2*options.nTurns+1
                if mod(iComp,2) == 0 % even-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel) ...
                        xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel)], ...
                        [xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)], rBend, "CCW");

                else % odd-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel) ...
                        xRef+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel)], ...
                        [xRef+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)], rBend, "CW");
                end
                ConnectivityData(iComp).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-options.nTurns-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-options.nTurns));
            end


        case 2 % Channels along X-axis: Flow bottom-left to top-left in XY plane - odd number of turns

            % ------ Create connectivity data for Cooling channels -------

            % Bottom edge channel - same as case 1
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef+lenCentralChannels+rBend yRef],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend1";

            % Central channels - same as case 1
            for iComp = 2:options.nTurns
                if mod(iComp,2) == 0 % even-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+lenCentralChannels+rBend yRef+(iComp - 1)*value(spaceChannel) ...
                        xRef+rBend  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));
                else % odd-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+rBend yRef+(iComp - 1)*value(spaceChannel) ...
                        xRef+lenCentralChannels+rBend  yRef+(iComp - 1)*value(spaceChannel)],string(unit(options.dChannel)));
                end
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Bend",string(iComp-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Bend",string(iComp));
            end

            % Top edge channel
            ConnectivityData(options.nTurns+1).Parameters.position = simscape.Value([xRef+rBend+lenCentralChannels yRef+(options.nTurns)*value(spaceChannel) ...
                xRef  yRef+(options.nTurns)*value(spaceChannel)],string(unit(options.dChannel)));
            ConnectivityData(options.nTurns+1).Connectivity.portAConnectedComponent = strcat("Bend",string(options.nTurns));
            ConnectivityData(options.nTurns+1).Connectivity.portBConnectedComponent = "sink";

            % ------- Create connectivity data for Bends ------

            for iComp = options.nTurns+2:2*options.nTurns+1
                if mod(iComp,2) == 0 % even-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel) ...
                        xRef+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel)], ...
                        [xRef+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)], rBend, "CW");

                else % odd-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel) ...
                        xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-2)*value(spaceChannel)], ...
                        [xRef+lenCentralChannels+rBend  yRef+(iComp-options.nTurns-1)*value(spaceChannel)], rBend, "CCW");

                end
                ConnectivityData(iComp).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-options.nTurns-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-options.nTurns));
            end


        case 3 % Channels along Y-axis:Flow bottom-left to top-right in XY plane - even number of turns

            % ------ Create connectivity data for Cooling channels -------

            % Left edge channel
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef yRef+lenCentralChannels+rBend],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend1";

            % Central channels
            for iComp = 2:options.nTurns
                if mod(iComp,2) == 0 % even-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp - 1)*value(spaceChannel) yRef+lenCentralChannels+rBend ...
                        xRef+(iComp - 1)*value(spaceChannel) yRef+rBend],string(unit(options.dChannel)));
                else % odd-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp - 1)*value(spaceChannel) yRef+rBend ...
                        xRef+(iComp - 1)*value(spaceChannel) yRef+lenCentralChannels+rBend],string(unit(options.dChannel)));
                end
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Bend",string(iComp-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Bend",string(iComp));
            end

            % Right edge channel
            ConnectivityData(options.nTurns+1).Parameters.position = simscape.Value([xRef+(options.nTurns)*value(spaceChannel) yRef+rBend ...
                xRef+(options.nTurns)*value(spaceChannel)  yRef+lenCentralChannels+2*rBend],string(unit(options.dChannel)));
            ConnectivityData(options.nTurns+1).Connectivity.portAConnectedComponent = strcat("Bend",string(options.nTurns));
            ConnectivityData(options.nTurns+1).Connectivity.portBConnectedComponent = "sink";

            % ------- Create connectivity data for Bends ------

            for iComp = options.nTurns+2:2*options.nTurns+1
                if mod(iComp,2) == 0 % even-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+lenCentralChannels+rBend ...
                        xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+lenCentralChannels+rBend],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+lenCentralChannels+rBend], ...
                        [xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+lenCentralChannels+rBend], rBend, "CW");

                else % odd-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+rBend ...
                        xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+rBend],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+rBend], ...
                        [xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+rBend], rBend, "CCW");
                end
                ConnectivityData(iComp).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-options.nTurns-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-options.nTurns));
            end

        case 4 % Channels along Y-axis:Flow bottom-left to bottom-right in XY plane - odd number of turns

            % ------ Create connectivity data for Cooling channels -------

            % Left edge channel - same as Case 3
            ConnectivityData(1).Parameters.position = simscape.Value([xRef yRef ...
                xRef yRef+lenCentralChannels+rBend],string(unit(options.dChannel)));

            ConnectivityData(1).Connectivity.portAConnectedComponent = "source";
            ConnectivityData(1).Connectivity.portBConnectedComponent = "Bend1";

            % Central channels - same as Case 3
            for iComp = 2:options.nTurns
                if mod(iComp,2) == 0 % even-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp - 1)*value(spaceChannel) yRef+lenCentralChannels+rBend ...
                        xRef+(iComp - 1)*value(spaceChannel) yRef+rBend],string(unit(options.dChannel)));
                else % odd-numbered channels
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp - 1)*value(spaceChannel) yRef+rBend ...
                        xRef+(iComp - 1)*value(spaceChannel) yRef+lenCentralChannels+rBend],string(unit(options.dChannel)));
                end
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Bend",string(iComp-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Bend",string(iComp));
            end

            % Right edge channel
            ConnectivityData(options.nTurns+1).Parameters.position = simscape.Value([xRef+(options.nTurns)*value(spaceChannel) yRef+lenCentralChannels+rBend ...
                xRef+(options.nTurns)*value(spaceChannel)  yRef],string(unit(options.dChannel)));
            ConnectivityData(options.nTurns+1).Connectivity.portAConnectedComponent = strcat("Bend",string(options.nTurns));
            ConnectivityData(options.nTurns+1).Connectivity.portBConnectedComponent = "sink";

            % ------- Create connectivity data for Bends ------

            for iComp = options.nTurns+2:2*options.nTurns+1
                if mod(iComp,2) == 0 % even-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+rBend ...
                        xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+rBend],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+rBend], ...
                        [xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+rBend], rBend, "CCW");

                else % odd-numbered components
                    ConnectivityData(iComp).Parameters.position = simscape.Value([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+lenCentralChannels+rBend ...
                        xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+lenCentralChannels+rBend],string(unit(options.dChannel)));

                    bend1Pts = generateBendPts([xRef+(iComp-options.nTurns-2)*value(spaceChannel) yRef+lenCentralChannels+rBend], ...
                        [xRef+(iComp-options.nTurns-1)*value(spaceChannel) yRef+lenCentralChannels+rBend], rBend, "CW");

                end
                ConnectivityData(iComp).Parameters.centerlinePts = simscape.Value(bend1Pts,string(unit(options.dChannel)));
                ConnectivityData(iComp).Connectivity.portAConnectedComponent = strcat("Pipe",string(iComp-options.nTurns-1));
                ConnectivityData(iComp).Connectivity.portBConnectedComponent = strcat("Pipe",string(iComp-options.nTurns));
            end

    end

end

for iComp=1:numel(ConnectivityData)
    ConnectivityData(iComp).Connectivity.portAName = "A";
    ConnectivityData(iComp).Connectivity.portAConnectedPort = "B";
    ConnectivityData(iComp).Connectivity.portBName = "B";
    ConnectivityData(iComp).Connectivity.portBConnectedPort = "A";
    ConnectivityData(iComp).Connectivity.portHName = "H";
    ConnectivityData(iComp).Connectivity.portHConnected = "yes";
end

% Plot the cooling channel network schematic using connectivity data
plotCoolingChannels(ConnectivityData,Axis=uiaxes,PlotType="2D", ...
    PipeColor=[255,191,0]/255,LineWidth=3);
end