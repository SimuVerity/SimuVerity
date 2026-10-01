function animateBatteryAndPlateTemp3D(simlogNode, batteryName, batteryData, ...
    logsout, coolingPlateData, options)
% This function creates a 3-D animation of the temperature distribution of the 
% battery pack and the cooling plate for a load cycle over a time period.
%
%   Inputs:
%       simlogNode       - simscape.logging.Node object.
%       batteryName      - Name of the battery pack.
%       batteryData      - struct consisting of battery pack data (data 
%                          exported as .MAT file by Battery Builder app).
%       logsout          - Simulation logsout object; first element must contain
%                          a timeseries object with partition temperatures.
%       coolingPlateData - An instance of the class ComponentConnectivity.
%
%   Optional inputs:
%       LocationCoolingPlate - Location of cooling plate relative
%                              to the battery pack (Bottom or Top).
%       CycleName            - Name of load cycle.
%       ShowBattery          - Battery visualization enabled (=true) 
%                              or disabled (=false) in plot.
%       ShowCoolingPlate     - Cooling plate visualization enabled (=true) 
%                              or disabled (=false) in plot.
%       UpdateFreq           - Time (sec) interval of successive updates of plots.
%       FrameRate            - Frame rate of the video of the animation.
%       PlaybackSpeed        - Playback speed of the video of the animation.
%       SaveVideo            - Video saving enabled (=true) or disabled (=false).
%       VideoFile            - Name of video file.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    simlogNode simscape.logging.Node
    batteryName (1,1) string
    batteryData struct {mustBeNonempty}
    logsout Simulink.SimulationData.Dataset
    coolingPlateData ComponentConnectivity
    options.LocationCoolingPlate (1,1) string ...
        {mustBeMember(options.LocationCoolingPlate,["Top","Bottom"])} = "Bottom"
    options.CycleName (1,1) string = "Charging";
    options.ShowBattery = true;
    options.ShowCoolingPlate = true;
    options.UpdateFreq (1,1) double {mustBePositive} = 50;
    options.FrameRate (1,1) double {mustBeInteger} = 10;
    options.PlaybackSpeed (1,1) double = 0.2;
    options.SaveVideo = false;
    options.VideoFile = "BatteryCooling.mp4";
end


%% Figure Setup

fig = figure('Name', 'Battery & Plate Temperature Animation','Visible','on',...
    'Units','pixels');
fig.Color = "w";
fig.Position(3:4) = [840 480];
fig.Resize = "off";
set(fig,'Renderer','opengl');

ax  = axes(fig);

axis(ax,"equal")
view(ax,3)
rotate3d(fig, 'on')

% Extract timeseries data
tempPartitionTS = logsout{1}.Values; % timeseries object
allTimes = tempPartitionTS.Time;     % time vector

% Animation time vector
tStart = allTimes(1);
tEnd = allTimes(end);
tAnim = tStart:options.UpdateFreq:tEnd;

% Determine number of thermal models for each cell in the model
    modelNameBattThermalSys = simlogNode.id;
    numDiscreteCellZ = str2num(get_param(strcat(modelNameBattThermalSys,"/",...
        batteryName,"/ModuleAssembly1/Module1"),"NumThermalModelsCell"));

% Compute global temperature limits
[Tmin, Tmax] = computeGlobalTemperatureLimits( ...
    simlogNode, batteryName, batteryData, logsout, numDiscreteCellZ);

% Optional padding
dT = 0.05 * (Tmax - Tmin);
Tlim = [Tmin - dT, Tmax + dT];

cb = colorbar(ax);
cb.Label.String = 'Temperature (K)';
clim(ax, Tlim);

%% Video writer

if options.SaveVideo
    vw = VideoWriter(options.VideoFile, "MPEG-4");
    vw.FrameRate = 10;
    open(vw);
end

%% Preallocate movie frames
recordAnimationData(numel(tAnim)) = struct('cdata',[],'colormap',[]);


%% Animation Loop
for iSecs = 1:numel(tAnim)

    tCurr = tAnim(iSecs);

    % Find closest simulation index
    [~, idx] = min(abs(allTimes - tCurr));

        plotBatteryAndPlateTemp3D(simlogNode, batteryName, batteryData, ...
        logsout, coolingPlateData, allTimes(idx), ...
        Axis=ax, LocationCoolingPlate=options.LocationCoolingPlate, ...
        ShowBattery=options.ShowBattery, ShowCoolingPlate=options.ShowCoolingPlate);

        if options.ShowBattery == true && options.ShowCoolingPlate == true
            title(ax, sprintf("Battery & Cold Plate Temperature (%s cycle) at t = %.1f s", ...
                options.CycleName, allTimes(idx)));
        elseif options.ShowBattery == true && options.ShowCoolingPlate == false
            title(ax, sprintf("Battery Temperature (%s cycle) at t = %.1f s", ...
                options.CycleName, allTimes(idx)));
        elseif options.ShowBattery == false && options.ShowCoolingPlate == true
            title(ax, sprintf("Cold Plate Temperature (%s cycle) at t = %.1f s", ...
                options.CycleName, allTimes(idx)));
        end

    drawnow limitrate   % CRITICAL for live animation

    % Capture frame
    frame = getframe(fig);
    recordAnimationData(iSecs) = frame;

    if options.SaveVideo
        % Write to video
        writeVideo(vw, frame);
    end

end

if options.SaveVideo
    % Cleanup
    close(vw);
end

%% Inline playback for live script
figMovie = figure('Color','w');
axMovie  = axes('Parent',figMovie,'Position',[0 0 1 1]);
axis(axMovie,'off')

movie(axMovie, recordAnimationData, 1, options.FrameRate * options.PlaybackSpeed);

end

function [Tmin, Tmax] = computeGlobalTemperatureLimits( ...
    simlogNode, batteryName, batteryData, logsout, numDiscreteCellZ)

Tmin = inf;
Tmax = -inf;

%% Battery temperatures (all times)

logBattery = simlogNode.(batteryName);
moduleAssemblyData = batteryData.(batteryName);

for iAsm = 1:numel(moduleAssemblyData.ModuleAssembly)
    for iMod = 1:numel(moduleAssemblyData.ModuleAssembly(iAsm).Module)
        numGroups = moduleAssemblyData.ModuleAssembly(iAsm).Module(iMod).NumModels;

        for iGrp = 1:numGroups
            for kZ = 1:numDiscreteCellZ

                asmField = sprintf('ModuleAssembly%d', iAsm);
                modField = sprintf('Module%d', iMod);

                ts = logBattery.(asmField).(modField) ...
                    .BattEqCircuitCell(iGrp).HDistributed(kZ).T.series;

                Tmin = min(Tmin, min(ts.values));
                Tmax = max(Tmax, max(ts.values));
            end
        end
    end
end

%% Cooling plate temperatures (all times)

tempTS = logsout{1}.Values;
plateData = tempTS.Data;  

Tmin = min(Tmin, min(plateData(:)));
Tmax = max(Tmax, max(plateData(:)));

end
