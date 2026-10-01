% Code to plot simulation results from dc_motor_scratch
%% Plot Description:
%
% <enter plot description here if desired>
%
% Copyright 2016-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_dc_motor_scratch', 'var')
    sim('dc_motor_scratch')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_dc_motor_scratch', 'var') || ...
        ~isgraphics(h1_dc_motor_scratch, 'figure')
    h1_dc_motor_scratch = figure('Name', 'dc_motor_scratch');
end
figure(h1_dc_motor_scratch)
clf(h1_dc_motor_scratch)

% Get simulation results
simlog_t = simlog_dc_motor_scratch.Inertia.I.w.series.time;
simlog_xspr = simlog_dc_motor_scratch.Ideal_Rotational_Motion_Sensor.A.series.values('deg');
simlog_imotor = simlog_dc_motor_scratch.Resistor.i.series.values('A');

% Plot results
simlog_handles(1) = subplot(2, 1, 1);
plot(simlog_t, simlog_xspr, 'LineWidth', 1)
hold off
grid on
title('Shaft Angle')
ylabel('Angle (deg)')
%legend({'Side A','Side B'},'Location','Best');

simlog_handles(2) = subplot(2, 1, 2);
plot(simlog_t, simlog_imotor, 'LineWidth', 1)
grid on
title('Motor Current')
ylabel('Current (A)')
xlabel('Time (s)')

linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_shaftw simlog_shaftt simlog_handles
