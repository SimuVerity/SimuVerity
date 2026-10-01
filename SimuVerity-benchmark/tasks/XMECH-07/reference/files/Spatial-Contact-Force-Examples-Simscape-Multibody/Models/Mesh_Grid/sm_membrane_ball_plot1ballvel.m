% Code to plot simulation results from sm_membrane_ball
%% Plot Description:
%
% Plot ball velocities as the ball falls on the first eigenfunction of the
% L-shaped membrane.  100 points are used for the point cloud.
%
% Copyright 2021-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_membrane_ball', 'var')
    sim('sm_membrane_ball')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_membrane_ball', 'var') || ...
        ~isgraphics(h1_sm_membrane_ball, 'figure')
    h1_sm_membrane_ball = figure('Name', 'sm_membrane_ball');
end
figure(h1_sm_membrane_ball)
clf(h1_sm_membrane_ball)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t   = simlog_sm_membrane_ball.Joint_Ball_1.Pz.v.series.time;
simlog_b1z = simlog_sm_membrane_ball.Joint_Ball_1.Pz.v.series.values;
simlog_b2z = simlog_sm_membrane_ball.Joint_Weight.Pz.v.series.values;
simlog_b1x = simlog_sm_membrane_ball.Joint_Ball_1.Px.v.series.values;
simlog_b2x = simlog_sm_membrane_ball.Joint_Weight.Px.v.series.values;

% Plot results
simlog_handles(1) = subplot(2, 1, 1);
plot(simlog_t, simlog_b2z, 'LineWidth', 1,'DisplayName','Ball 1')
hold on
plot(simlog_t, simlog_b1z, 'LineWidth', 1,'DisplayName','Ball 2')
hold off
grid on
title('Ball Vertical Velocity')
ylabel('Velocity (m/s)')
legend('Location','Best');

simlog_handles(2) = subplot(2, 1, 2);
plot(simlog_t, simlog_b2x, 'LineWidth', 1,'DisplayName','Ball 1')
hold on
plot(simlog_t, simlog_b1x, 'LineWidth', 1,'DisplayName','Ball 2')
hold off
grid on
title('Ball Velocity Along Global X')
ylabel('Velocity (m/s)')
xlabel('Time (s)')

linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_handles
clear simlog_R1i simlog_C1v temp_colororder

