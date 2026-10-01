% Code to plot simulation results from ssc_hydromech_power_split_cvt

% Copyright 2023-2025 The MathWorks, Inc.

%% Generate simulation results if they don't exist
if ~exist('simlog_ssc_hydromech_power_split_cvt', 'var')
    sim('ssc_hydromech_power_split_cvt')
end

%% Reuse figure if it exists, else create new figure
if ~exist('h1_ssc_hydromech_power_split_cvt', 'var') || ...
        ~isgraphics(h1_ssc_hydromech_power_split_cvt, 'figure')
    h1_ssc_hydromech_power_split_cvt = figure('Name', 'ssc_hydromech_power_split_cvt');
end
figure(h1_ssc_hydromech_power_split_cvt)
clf(h1_ssc_hydromech_power_split_cvt)

%% Get simulation results
simlog_t   = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tire_FL.A.w.series.time;
simlog_vLF = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tire_FL.A.w.series.values('rad/s')*HMPST.Tire.Rad*3.6;
simlog_vFR = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tire_FR.A.w.series.values('rad/s')*HMPST.Tire.Rad*3.6;
simlog_vLR = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tire_RL.A.w.series.values('rad/s')*HMPST.Tire.Rad*3.6;
simlog_vRR = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tire_RR.A.w.series.values('rad/s')*HMPST.Tire.Rad*3.6;

%% Plot results
plot(simlog_t, simlog_vLF,'LineWidth', 1,'DisplayName','wLF')
hold on
plot(simlog_t, simlog_vRF,'--','LineWidth', 1,'DisplayName','wRF')
plot(simlog_t, simlog_vLR,'LineWidth', 1,'DisplayName','wLR')
plot(simlog_t, simlog_vRR,'--','LineWidth', 1,'DisplayName','wRR')
hold off
grid on
title('Vehicle Wheel Speeds (km/h)')
ylabel('Speed (km/h)')
legend('Location','Best');
xlabel('Time (s)');
