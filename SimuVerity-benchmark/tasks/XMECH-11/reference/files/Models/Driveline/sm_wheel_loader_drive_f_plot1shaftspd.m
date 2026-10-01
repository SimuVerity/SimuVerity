% Code to plot simulation results from sm_wheel_loader_drive_f
%

% Copyright 2023-2025 The MathWorks, Inc.

%% Generate simulation results if they don't exist
if ~exist('simlog_sm_wheel_loader_drive_f', 'var')
    sim('sm_wheel_loader_drive_f')
end

%% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_wheel_loader_drive_f', 'var') || ...
        ~isgraphics(h1_sm_wheel_loader_drive_f, 'figure')
    h1_sm_wheel_loader_drive_f = figure('Name', 'sm_wheel_loader_drive_f');
end
figure(h1_sm_wheel_loader_drive_f)
clf(h1_sm_wheel_loader_drive_f)

%% Get simulation results
simlog_t    = simlog_sm_wheel_loader_drive_f.Revolute_Pinion.Rz.w.series.time;
simlog_wPin = simlog_sm_wheel_loader_drive_f.Revolute_Pinion.Rz.w.series.values('rpm');
simlog_wFL  = simlog_sm_wheel_loader_drive_f.Planetary_FL.Revolute_Ring_Carrier.Rz.w.series.values('rpm');
simlog_wFR  = simlog_sm_wheel_loader_drive_f.Planetary_FR.Revolute_Ring_Carrier.Rz.w.series.values('rpm');

%% Plot results
plot(simlog_t, simlog_wPin,'LineWidth', 1,'DisplayName','Pinion')
hold on
plot(simlog_t, simlog_wFR,'LineWidth', 1,'DisplayName','Wheel R')
plot(simlog_t, simlog_wFL,'--','LineWidth', 1,'DisplayName','Wheel L')
hold off
grid on
title('Differential Shaft Speeds')
ylabel('Speed (rpm)')
xlabel('Time (s)')
legend('Location','Best');
