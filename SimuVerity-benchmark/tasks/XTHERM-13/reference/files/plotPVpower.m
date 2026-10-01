% This function plots the monthly average variation in the Solar power
% recieved at a location

% Copyright 2023 - 2024 The MathWorks, Inc.

function plotPVpower(PVPowTbl,avgIRR)
    months = categorical(["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]); % Define categorical variables months 
    months = reordercats(months,["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]);% Set the order for categorical variables months
    figure("Name","Solar Power");    
    bar(months,PVPowTbl.monthPVpow.("Total PV Power[kWh]"));
    hold on
    plot(months,avgIRR.("Average Total Solar Irradiation(W/m^2)"))
    hold off
    title('Monthly Averaged Total Photovoltaic Power Output and Total Solar Irradiation');   
    ylabel('Total Power(kWh)');
end

