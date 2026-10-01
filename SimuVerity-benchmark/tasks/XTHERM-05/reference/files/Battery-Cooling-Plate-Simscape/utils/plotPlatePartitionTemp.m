function plotPlatePartitionTemp(logsout,timeInstance,options)
% This function creates a heatmap plot of cooling plate partition 
% temperatures at a given time instance.
%
%   Inputs:
%       logsout                 - Simulation logsout object; first element must contain
%                                 a timeseries object with partition temperatures.
%       timeInstance            - Time instance (sec) of logged data for plot.
%
%   Optional inputs:
%         NumPartitionsX - Number of partitions in X direction (columns).
%         NumPartitionsY - Number of partitions in Y direction (rows).

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    logsout Simulink.SimulationData.Dataset
    timeInstance (1,1) double
    options.NumPartitionsX (1,1) double {mustBeInteger} = 5;
    options.NumPartitionsY (1,1) double {mustBeInteger} = 5;
end

nPartitions = options.NumPartitionsX * options.NumPartitionsY;
if exist('allTimes', 'var')
    clear allTimes
end
if exist('allData', 'var')
    clear allData
end

tempPartitionTS = logsout{1}.Values; % Timeseries object
allTimes = tempPartitionTS.Time;     % Time vector
allData = tempPartitionTS.Data;      % Data matrix

% Verify if timeInstance is out of simulation log bounds
if min(allTimes) <= timeInstance && timeInstance <= max(allTimes)

    % Find the index of the time closest to specified time instance
    [~, idx] = min(abs(allTimes - timeInstance));

    % Extract the temperature for each partition at time t1
    tempPartitionAtT1 = zeros(1,size(allData,2));
    for indexPartition = 1:nPartitions
        tempPartitionAtT1(indexPartition) = allData(1,indexPartition,idx);
    end

    % Reshape into a 2D grid: [rows (Y) x columns (X)]
    % Assuming row-major order: left to right, top to bottom
    tempGrid = reshape(tempPartitionAtT1, [options.NumPartitionsX, options.NumPartitionsY])';

    % Plot the heatmap
    figure;
    h = heatmap(tempGrid);
    h.CellLabelFormat = '%.2f';
    h.YDisplayData = flip(h.YDisplayData);
    h.XLabel = "X (Cell Length)";
    h.YLabel = "Y (Cell Stack Direction)";
    colormap(parula);
    colorbar;

    title(strcat("Temperature Distribution (K) in Cooling Plate at time = ",string(timeInstance)," s"));

else
    error("Specified time instance is out of bounds of the simulation log.");

end

end