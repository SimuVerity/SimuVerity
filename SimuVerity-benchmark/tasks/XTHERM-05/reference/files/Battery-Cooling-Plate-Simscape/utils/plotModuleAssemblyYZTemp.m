function plotModuleAssemblyYZTemp(simlogNode,batteryName,moduleAssemblyName, ...
    batteryData,timeInstance)
% This function creates a heatmap plot of battery module assembly 
% temperatures at a given time instance. 
%
%   Inputs:
%       simlogNode          - simscape.logging.Node object
%       batteryName         - Name of the battery pack.
%       moduleAssemblyName  - Name of the battery module assembly.
%       batteryData         - struct consisting of battery pack data (data 
%                             exported as .MAT file by Battery Builder app).
%       timeInstance        - Time instance (sec) of logged data for plot.

% Copyright 2025 - 2026 The MathWorks, Inc.

arguments
    simlogNode simscape.logging.Node 
    batteryName (1,1) string
    moduleAssemblyName (1,1) string
    batteryData struct {mustBeNonempty}
    timeInstance (1,1) double
end

logBattery = simlogNode.(batteryName);
packData = batteryData.(batteryName);

% Determine number of thermal models for each cell in the model
modelNameBattThermalSys = simlogNode.id;
numDiscreteCellZ = str2num(get_param(strcat(modelNameBattThermalSys,"/",...
    batteryName,"/ModuleAssembly1/Module1"),"NumThermalModelsCell"));

% Determine the number of thermal nodes in Y dimension
numCellGroupsY = packData.ModuleAssembly(1).ThermalNodes.Bottom.NumNodes;

nDiscreteCells = numCellGroupsY * numDiscreteCellZ;
if exist('allTimesModel', 'var')
    clear allTimesModel
end
if exist('allDataModel', 'var')
    clear allDataModel
end


iAsm = str2num(extractAfter(moduleAssemblyName,"ModuleAssembly"));
asmField = sprintf('ModuleAssembly%d', iAsm);

numModules = numel(packData.ModuleAssembly(1).Module);

% ---- Initialize variables ----
iCellDiscrete = 0;
cellTempValues = zeros(numDiscreteCellZ,1);
cellTempTimes = zeros(numDiscreteCellZ,1);

for iMod = 1:numModules

    mod = packData.ModuleAssembly(iAsm).Module(iMod);
    numGroups = mod.NumModels;

    for iGrp = 1:numGroups

        for kZ = numDiscreteCellZ:-1:1
            iCellDiscrete = iCellDiscrete + 1;
            modField = sprintf('Module%d', iMod);

            ts = logBattery.(asmField).(modField) ...
                .BattEqCircuitCell(iGrp).HDistributed(kZ).T.series;

            [~, idx] = min(abs(ts.time - timeInstance));
            TVals = ts.values;
            TTimes = ts.time;
            cellTempValues(iCellDiscrete,:) = TVals(idx);
            cellTempTimes(iCellDiscrete,:) = TTimes(idx); 
        end
    end
end

% Verify if timeInstance is out of simulation log bounds
if min(min(cellTempTimes)) <= timeInstance && timeInstance <= max(max(cellTempTimes))

    % Find the index of the time closest to specified time instance
    [~, idx] = min(min(abs(cellTempTimes - timeInstance)));

    % Extract the temperature for each partition at time t1
    tempDiscreteCellAtT1 = zeros(1,nDiscreteCells);

    for iCellDiscrete = 1:nDiscreteCells
        tempDiscreteCellAtT1(iCellDiscrete) = cellTempValues(iCellDiscrete,idx);
    end

    % Reshape
    tempGrid = reshape(tempDiscreteCellAtT1, [numDiscreteCellZ, numCellGroupsY]);

    % Plot heatmap
    figure;
    h = heatmap(tempGrid);
    h.CellLabelFormat = '%.2f';
    h.YDisplayData = flip(h.YDisplayData);  % Flip so Z=1 (bottom) appears at bottom in heatmap
    h.XLabel = "Y (Cell Stack Direction)";
    h.YLabel = "Z (Cell Height)";
    colormap(parula);
    colorbar;

    title(strcat("Height-Distributed Temperature (K) in Battery Cell Groups at time = ",string(timeInstance)," s"));

else
    error("Specified time instance is out of bounds of the simulation log.");

end

end