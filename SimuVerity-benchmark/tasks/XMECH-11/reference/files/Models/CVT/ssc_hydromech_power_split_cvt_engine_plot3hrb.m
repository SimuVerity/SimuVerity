% Code to plot simulation results from ssc_hydromech_power_split_cvt_engine
% Compares test with and without hydraulic regenerative braking (HRB)

% Copyright 2023-2025 The MathWorks, Inc.

%% Open model
mdl = 'ssc_hydromech_power_split_cvt_engine';

% Configure for power split hydromechanical CVT with HRB
set_param([mdl '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Power_Split_HM')

%% Test with HRB enabled
sim(mdl)

% Save results with HRB enabled;
simlog_cvt_engine_wiHRB = simlog_ssc_hydromech_power_split_cvt_engine;

%% Test with HRB disabled
try
    % Save stroke value
    temp_HRB_stroke = HMPST.HRB.Pump.stroke2disp; % m^2/rad
    % Turn off HRB
    HMPST.HRB.Pump.stroke2disp = 0;
    % Run simulation
    sim(mdl)
    % Save results with HRB disabled;
    simlog_cvt_engine_noHRB = simlog_ssc_hydromech_power_split_cvt_engine;

catch
    % If simulation fails, reset parameter value
    HMPST.HRB.Pump.stroke2disp = temp_HRB_stroke;
    rethrow(ME)
end

% If test completes, reset parameter value
HMPST.HRB.Pump.stroke2disp = temp_HRB_stroke;

%% Extract results from both tests
EngP_wiHRB   = simlog_cvt_engine_wiHRB.Vehicle_with_CVT.Engine.Engine_Droop.Generic_Engine.P;
HRBP_wiHRB   = simlog_cvt_engine_wiHRB.Vehicle_with_CVT.Transmission.Power_Split_Hydromech.HRB.Variable_Displacement_Hydraulic_Machine.mechanical_power;
VehSpd_wiHRB = simlog_cvt_engine_wiHRB.Vehicle_with_CVT.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

EngP_noHRB   = simlog_cvt_engine_noHRB.Vehicle_with_CVT.Engine.Engine_Droop.Generic_Engine.P;
HRBP_noHRB   = simlog_cvt_engine_noHRB.Vehicle_with_CVT.Transmission.Power_Split_Hydromech.HRB.Variable_Displacement_Hydraulic_Machine.mechanical_power;
VehSpd_noHRB = simlog_cvt_engine_noHRB.Vehicle_with_CVT.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

%% Reuse figure if it exists, else create new figure
if ~exist('h2_ssc_hydromech_power_split_cvt', 'var') || ...
        ~isgraphics(h2_ssc_hydromech_power_split_cvt, 'figure')
    h2_ssc_hydromech_power_split_cvt = figure('Name', 'ssc_hydromech_power_split_cvt');
end
figure(h2_ssc_hydromech_power_split_cvt)
clf(h2_ssc_hydromech_power_split_cvt)

ah(1) = subplot(211);
plot(EngP_wiHRB.series.time,EngP_wiHRB.series.values('kW'),'LineWidth',2,'DisplayName','Engine Power With HRB');
hold on
plot(EngP_noHRB.series.time,EngP_noHRB.series.values('kW'),'--','LineWidth',2,'DisplayName','Engine Power No HRB');
plot(HRBP_wiHRB.series.time,HRBP_wiHRB.series.values('kW'),'LineWidth',2,'DisplayName','HRB Power');
hold off
legend('Location','Best')
ylabel('kW')
title('Effect of Hydraulic Regenerative Braking')

ah(2) = subplot(212);
plot(HRBP_wiHRB.series.time,VehSpd_wiHRB,'LineWidth',2,'DisplayName','With HRB');
hold on
plot(HRBP_noHRB.series.time,VehSpd_noHRB,'--','LineWidth',2,'DisplayName','No HRB');
hold off
legend('Location','South')
linkaxes(ah,'x')
title('Vehicle Speed')
ylabel('km/hr')
xlabel('Time (s)')

set(gca,'XLim',[10 16.7])
set(ah(1),'YLim',[-110 250])

clear temp_HRB_stroke