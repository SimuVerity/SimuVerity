% Code to plot simulation results from sm_wheel_loader_diff_r
%
%% Plot Description:
%
% The plot below shows the results of a simulation with a locked right wheel.

% Copyright 2023-2025 The MathWorks, Inc.

%% Generate simulation results if they don't exist
if ~exist('simlog_sm_wheel_loader_diff_r', 'var')
    sim('sm_wheel_loader_diff_r')
end

%% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_wheel_loader_diff_r', 'var') || ...
        ~isgraphics(h1_sm_wheel_loader_diff_r, 'figure')
    h1_sm_wheel_loader_diff_r = figure('Name', 'sm_wheel_loader_diff_r');
end
figure(h1_sm_wheel_loader_diff_r)
clf(h1_sm_wheel_loader_diff_r)

%% Get simulation results
simlog_t    = simlog_sm_wheel_loader_diff_r.Revolute_Pinion.Rz.w.series.time;
simlog_wPin = simlog_sm_wheel_loader_diff_r.Revolute_Pinion.Rz.w.series.values('rpm');
simlog_wShL = simlog_sm_wheel_loader_diff_r.Planetary_RL.Revolute_Ring_Sun.Rz.w.series.values('rpm');
simlog_wShR = simlog_sm_wheel_loader_diff_r.Planetary_RR.Revolute_Ring_Sun.Rz.w.series.values('rpm');

%% Plot results
plot(simlog_t, simlog_wPin,'LineWidth', 1,'DisplayName','Pinion')
hold on
plot(simlog_t, simlog_wShR,'LineWidth', 1,'DisplayName','Shaft R')
plot(simlog_t, simlog_wShL,'--','LineWidth', 1,'DisplayName','Shaft L')
hold off
grid on
title('Differential Shaft Speeds')
ylabel('Speed (rpm)')
xlabel('Time (s)')
legend('Location','Best');
