% This function plots monthly averaged Total PV power and direct normal
% solar irradiation(DNI)

% Copyright 2023 - 2024 The MathWorks, Inc.

function plotPVpowerAndIrr(PVPowTbl,avgIRR)
    months = categorical(["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]); % Define categorical variables months 
    months = reordercats(months,["Jan";"Feb";"Mar";"Apr";"May";"Jun";"Jul";"Aug";"Sep";"Oct";"Nov";"Dec"]);% Set the order for categorical variables months
    figure("Name","Solar Power");    
    bar(months,PVPowTbl.monthPVpow.("Total PV Power[kWh]"));
    hold on
    plot(months,avgIRR.("Average Total Solar Irradiation(W/m^2)"),"LineWidth",1.5)
    hold off
    title('Monthly Averaged Total Photovoltaic Power and DNI');   
    ylabel('Total Power (kWh)');
end

