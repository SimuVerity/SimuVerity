% Code to plot simulation results from sm_wheel_loader_diff_f
%
%% Plot Description:
%
% The plot below shows the results simulation with a locked right wheel.

% Copyright 2023-2025 The MathWorks, Inc.

%% Generate simulation results if they don't exist
if ~exist('simlog_sm_wheel_loader_diff_f', 'var')
    sim('sm_wheel_loader_diff_f')
end

%% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_wheel_loader_diff_f', 'var') || ...
        ~isgraphics(h1_sm_wheel_loader_diff_f, 'figure')
    h1_sm_wheel_loader_diff_f = figure('Name', 'sm_wheel_loader_diff_f');
end
figure(h1_sm_wheel_loader_diff_f)
clf(h1_sm_wheel_loader_diff_f)

%% Get simulation results
simlog_t    = simlog_sm_wheel_loader_diff_f.Revolute_Pinion.Rz.w.series.time;
simlog_wPin = simlog_sm_wheel_loader_diff_f.Revolute_Pinion.Rz.w.series.values('rpm');
simlog_wShL = simlog_sm_wheel_loader_diff_f.Revolute_Shaft_L.Rz.w.series.values('rpm');
simlog_wShR = simlog_sm_wheel_loader_diff_f.Revolute_Shaft_R.Rz.w.series.values('rpm');

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
