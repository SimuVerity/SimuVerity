% This function returns total component cost

% Copyright 2023 - 2024 The MathWorks, Inc.

function componentCost = calcComponentCost(costTbl,costInd1,qtyComp1,costInd2,qtyComp2,costInd3,qtyComp3)
    heaterPrice = costTbl.heater.("Unit Price (USD)"); % Price USD($)/m
    airPipePrice = costTbl.pipe.("Unit Price (USD)"); % Air Coil Price USD($)/m
    insulationPrice = costTbl.insulation.("Unit Price (USD)"); % Price USD($)/m^2
    componentCost = heaterPrice(costInd1)*qtyComp1 + airPipePrice(costInd2)*qtyComp2 + insulationPrice(costInd3)*qtyComp3; % Calculate the cost (USD)
end