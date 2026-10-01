function animatePlatePartitionTemp(logsout, numPartitionsX, numPartitionsY, options)
% This function creates a 2-D animation of the evolution of the cooling plate 
% partition temperature over time.
%
%   Inputs:
%       logsout         - Simulation logsout object; first element must contain
%                         a timeseries object with partition temperatures.
%       numPartitionsX  - Number of partitions in X direction (columns).
%       numPartitionsY  - Number of partitions in Y direction (rows).
%
%   Optional inputs:
%       UpdateFreq      - Time (sec) interval of successive updates of
%                         heatmap plots.
%       FrameRate       - Frame rate of the video of the animation.
%       PlaybackSpeed   - Playback speed of the video of the animation.
%       SaveVideo       - Video saving enabled (=true) or disabled (=false).
%       VideoFile       - Name of video file.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    logsout Simulink.SimulationData.Dataset
    numPartitionsX (1,1) double {mustBeInteger}
    numPartitionsY (1,1) double {mustBeInteger}
    options.UpdateFreq (1,1) double {mustBePositive} = 50;
    options.FrameRate (1,1) double {mustBeInteger} = 10;
    options.PlaybackSpeed (1,1) double = 0.2;
    options.SaveVideo = false
    options.VideoFile = "CoolingPlateAnimation.mp4";
end

% Extract timeseries data
tempPartitionTS = logsout{1}.Values; % timeseries object
allTimes = tempPartitionTS.Time;     % time vector
allData = tempPartitionTS.Data;      % data matrix
nPartitions = numPartitionsX * numPartitionsY;

% Validate data dimensions
if size(allData,2) ~= nPartitions
    error('Data size does not match numPartitionsX * numPartitionsY.');
end

% Animation time vector
tStart = allTimes(1);
tEnd = allTimes(end);
tAnim = tStart:options.UpdateFreq:tEnd;

% Set up figure and heatmap
fig = figure('Name', 'Partition Temperature Animation','Visible','off');
clf(fig);
% Initial grid (all NaN)
tempGrid = nan(numPartitionsY, numPartitionsX);
h = heatmap(tempGrid, 'Colormap', parula, 'CellLabelFormat', '%.2f');
colorbar;
title('Temperature Distribution in Cooling Plate');
xlabel('X Partition');
ylabel('Y Partition');

% Set color limits for consistency
minTemp = min(allData(:));
maxTemp = max(allData(:));
h.ColorLimits = [minTemp, maxTemp];

% Reorder Y-axis labels
h.YDisplayData = flip(h.YDisplayData);

% Create MP4 file
if options.SaveVideo
    vw = VideoWriter(options.VideoFile, "MPEG-4");
    vw.FrameRate = 10;
    open(vw);
end

% Animation loop
for iSecs = 1:length(tAnim)
    tCurr = tAnim(iSecs);

    % Find the index of the time closest to current time
    [~, idx] = min(abs(allTimes - tCurr));

    % Interpolate each partition separately
    tempPartition = zeros(1, nPartitions);
    for indexPartition = 1:nPartitions
        tempPartition(indexPartition) = allData(1,indexPartition,idx);
    end

    % Reshape to 2D grid and flip for display
    tempGrid = reshape(tempPartition, [numPartitionsX, numPartitionsY])';

    % Update heatmap data
    h.ColorData = tempGrid;

    % Update title
    h.Title = sprintf('Cooling Plate Temperature Distribution at t = %.1f s', tCurr);

    drawnow limitrate   % critical for live animation

    % Record animation data for video
    frame = getframe(gcf);
    recordAnimationData(1,iSecs) = getframe(fig);

    if options.SaveVideo
        % Write to video
        writeVideo(vw, frame);
    end
  
end

if options.SaveVideo
    % Cleanup
    close(vw);
end

% Close the animation figure
close(gcf);

% Create the movie figure
figMovie = figure;
axMovie = axes('Parent',figMovie,"Position",[0 0 1 1]);
xlabel(axMovie,'X Partition');
ylabel(axMovie,'Y Partition');
movie(axMovie, recordAnimationData, 1, options.FrameRate * options.PlaybackSpeed);

end