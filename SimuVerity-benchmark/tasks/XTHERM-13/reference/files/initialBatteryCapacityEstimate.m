% This function calculates initial estimate of required thermal battery
% capacity to meet the heating requiremnets of the building by calculating
%yearly total heat transferred to the ambient atmosphere while maintainanig a
% set room temperature

% Copyright 2023 - 2024 The MathWorks, Inc.

function heatCapacity = initialBatteryCapacityEstimate(dimensionHouse,roomT,overallHeatTransferCoeff,airCirculationF,ambdataS)
    avgAmbT = (ambdataS.("Avg Temperature(degC)"));
    airHeatcapacity = 1125; % Air heat capacity J/K-m^3
    airCirculation = prod(dimensionHouse)*airCirculationF; % Air circulation rate through the building (m^3/hr)
    houseExtArea = 2*(dimensionHouse(1)+dimensionHouse(2))*dimensionHouse(3);  % Building  external surface area
    convHeat = overallHeatTransferCoeff*houseExtArea*(roomT-mean(avgAmbT))*365*24; % Heat transferred to the atmosphere due to convection from the external surface of the building 
    leakageHeat =  airHeatcapacity*airCirculation*(roomT-mean(avgAmbT))*365*24; % Heat transferred to the atmosphere due air leakage and positive ventilation 
    heatCapacity = round((convHeat + leakageHeat),3,'significant'); % Total heat transferred from building inside air to the atmosphere
end