% Copyright 2013-2025 MathWorks, Inc.
% PLOT DATA FROM PARAMETER SWEEP
load FuelUsedSweep2D_AbsRea_1281
rc = FuelUsedSweep2D_AbsRea_1281.rampconst;
mgd = FuelUsedSweep2D_AbsRea_1281.mingeardiff;
FU_SET = FuelUsedSweep2D_AbsRea_1281.FuelUsedSET;
[rc_array, mgd_array] = meshgrid(rc,mgd);
fuelUse_h=figure;
clf
set(fuelUse_h,'Position',[8   227   445   419]);
%surf(mgd_array,rc_array,FU_SET);
mesh(mgd_array,rc_array,FU_SET);
title('Fuel Use With Varying Shift Schedule','FontWeight','Bold','FontSize',14);
xlabel('Offset Parameter','FontWeight','Bold','FontSize',12);
ylabel('Ramp Parameter','FontWeight','Bold','FontSize',12);
zlabel('Fuel Used (L)','FontWeight','Bold','FontSize',12);
legend('Parameter Sweep','Location','NorthWest');

% PLOT INITIAL SHIFT MAP
[Upshift_Speeds, Downshift_Speeds, Pedal_Positions] = Calc_Shift_Map_RO(rampconst0,mingeardiff0);
map_h=figure;
clf
set(map_h,'Position',[468   226   560   420]);
Plot_Gear_Shift_Schedule(Pedal_Positions,Upshift_Speeds,Downshift_Speeds);
set(gca,'XLim',[0 120]);
