% Code to plot simulation results from sm_wheel_loader_planetary_gear

% Copyright 2023-2025 The MathWorks, Inc.

%% Generate simulation results if they don't exist
if ~exist('simlog_sm_wheel_loader_planetary_gear', 'var')
    sim('sm_wheel_loader_planetary_gear')
end

%% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_wheel_loader_planetary_gear', 'var') || ...
        ~isgraphics(h1_sm_wheel_loader_planetary_gear, 'figure')
    h1_sm_wheel_loader_planetary_gear = figure('Name', 'sm_wheel_loader_planetary_gear');
end
figure(h1_sm_wheel_loader_planetary_gear)
clf(h1_sm_wheel_loader_planetary_gear)

%% Get simulation results
simlog_t    = simlog_sm_wheel_loader_planetary_gear.Planetary_L.Revolute_Ring_Carrier.Rz.w.series.time;
simlog_wRC  = simlog_sm_wheel_loader_planetary_gear.Planetary_L.Revolute_Ring_Carrier.Rz.w.series.values('rpm');
simlog_wRS  = simlog_sm_wheel_loader_planetary_gear.Planetary_L.Revolute_Ring_Sun.Rz.w.series.values('rpm');

%% Plot results
plot(simlog_t, simlog_wRC,'LineWidth', 1,'DisplayName','Ring-Carrier')
hold on
plot(simlog_t, simlog_wRS,'LineWidth', 1,'DisplayName','Ring-Sun')
hold off
grid on
title('Planetary Gear Shaft Speeds')
text(0.9,0.1,sprintf('Carrier/Ring Ratio: %3.3f',simlog_wRC(end)/simlog_wRS(end)),...
    'Units','Normalized','Color',[0.6 0.6 0.6],'HorizontalAlignment','right')
ylabel('Speed (rpm)')
xlabel('Time (s)')
legend('Location','Best');
