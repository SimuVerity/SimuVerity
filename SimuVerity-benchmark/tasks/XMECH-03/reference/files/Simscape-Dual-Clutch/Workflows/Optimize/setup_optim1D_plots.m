% Copyright 2013-2025 MathWorks, Inc.
% PLOT DATA FROM PARAMETER SWEEP
load FuelUsedSweep1D_AbsRea_7
fuelUse_h = figure;
set(gcf,'Position',[8   227   445   419]);
plot(FuelUsedSweep1D_AbsRea_7.rampconst,FuelUsedSweep1D_AbsRea_7.FuelUsedSET,'b-.o','LineWidth',2,'MarkerFaceColor','b');
title('Fuel Use With Varying Shift Schedule','FontWeight','Bold','FontSize',14);
xlabel('Shift Schedule Parameter','FontWeight','Bold','FontSize',12);
ylabel('Fuel Used (L)','FontWeight','Bold','FontSize',12);
legend('Parameter Sweep','Location','NorthWest');

% PLOT INITIAL SHIFT MAP
[Upshift_Speeds, Downshift_Speeds, Pedal_Positions] = Calc_Shift_Map_RO(rampconst0,17);
map_h = figure;
set(gcf,'Position',[468   226   560   420]);
Plot_Gear_Shift_Schedule(Pedal_Positions,Upshift_Speeds,Downshift_Speeds);
set(gca,'XLim',[0 120])
