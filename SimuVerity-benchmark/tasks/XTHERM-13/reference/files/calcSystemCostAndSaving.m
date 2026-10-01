% This function returns TES system installation cost and yearly saving

% Copyright 2023-24 The MathWorks, Inc.

function [cost , saving] = calcSystemCostAndSaving(tesCost,powConsump,numPV,houseH)
    boilEff = 0.8;% Asuumed Boiler efficiency
    Joule2Kwh = 2.77778e-7;% Coversion factor Joules to kWh
    simObject = load_system('ResidentialBuildingTESandPVcell');
    hexTubes= get_param('ResidentialBuildingTESandPVcell/Heat exchanger/HEX','value@tube_num_TL'); % Number of heat exchanger tubes
    close_system(simObject, 0);
    elecUnit = powConsump*Joule2Kwh;% Total electricity units spent during the year
    numBlr = 1; %Number of air blowers
    gasVol = houseH/(26e6*boilEff);% Yearly gas consumption for house heating ,m^3
    qtVec = [numPV,hexTubes,numBlr,elecUnit,gasVol];% Vector of consumption quantity
    unitpriceVec = [125,8,400,0.15,1.2];% Unit price, USD($)
    costVec = unitpriceVec.*qtVec;% Vector of all costs
    cost = sum(costVec(:,1:3)) + tesCost;% Installation cost
    saving = costVec(5)-costVec(4); % Yearly savings
end