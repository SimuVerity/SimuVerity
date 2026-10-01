% This function calculates heating requirement for residential house for
% specified house dimensions & environmental conditions

% Copyright 2023 - 2024 The MathWorks, Inc.

function [tesVolume,numCoils,coilTurns] = getTESsize(heatCapacity,storageTemp,pipeD,coilD,coilPitch,avgRoomT)
    % Generic assumptions and constants
    sandVolCp   = 1200000;  % Volumetric heat capacity of sand (J/m^3-K)
    % Equations
    sandVolume = heatCapacity/((storageTemp - avgRoomT)*sandVolCp); % Volume of the sand required to store required energy as sensible heat
    coilDepth  = sandVolume^(1/3); % Assume cubical pit to minimize the pit surface area and resultant heat loss to the ground
    coilTurns  = coilDepth/coilPitch; % Number of Coil turns
    coilLength = coilTurns*sqrt((pi*coilD)^2 + coilPitch^2); % Length of the helical air pipe
    unitSandVol = 2*(coilDepth*(coilD^2) - coilLength*(pi*(pipeD^2)/4)); % Assume unit sand cell is made of 2 equi-volume sand columns, which have a sqaure section of size = diameter of helical coil
    numSandCell = ceil(sandVolume/unitSandVol); % Total number of sand cells to form the sand battery
    numCoils = numSandCell; % Assume each cell has single heating and air coil
    pipeVolume = 2*coilDepth*(pi*(pipeD^2)/4); % Total volume of heating and air coil
    tesVolume = sandVolume + pipeVolume; % Total volume of the sand battery 
end