% Copyright 2011-2025 The MathWorks, Inc.
% Animate evolution of shift table during full optimization

pedalpos_4plot = [0.1 0.4 0.5 0.9];
load DCT_minFuelOptResMX_1803051312

figure(999)
for i=2:20:length(DCT_minFuelOptResMX)
    params_4plot_v = DCT_minFuelOptResMX(i).tableDeltas;
    params_4plot = reshape(params_4plot_v,4,[]);
    [Upshift_Speeds4plot, Downshift_Speeds4plot, Pedal_Positions] = Calc_Shift_Map_DL(params_4plot,pedalpos_4plot);
    Plot_Gear_Shift_Schedule(Pedal_Positions,Upshift_Speeds4plot,Downshift_Speeds4plot);
    pause(0.001)
end
