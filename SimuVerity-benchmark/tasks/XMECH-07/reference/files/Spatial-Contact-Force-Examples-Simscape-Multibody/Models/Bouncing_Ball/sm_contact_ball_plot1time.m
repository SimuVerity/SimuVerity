% Code to plot simulation results from sm_contact_ball
%% Plot Description:
%
% This script plots the height of the ball over time.
%
% Copyright 2019-2026 The MathWorks, Inc.

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_contact_ball', 'var') || ...
        ~isgraphics(h1_sm_contact_ball, 'figure')
    h1_sm_contact_ball = figure('Name', 'sm_contact_ball');
end
figure(h1_sm_contact_ball)
clf(h1_sm_contact_ball)

% Generate simulation results if they don't exist
if ~exist('simlog_sm_contact_ball', 'var')
    sim('sm_contact_ball')
end

temp_colororder = get(gca,'defaultAxesColorOrder');

simlog_t = simlog_sm_contact_ball.x6_DOF_Joint_Spherical_Solid.Pz.p.series.time;
simlog_pz = simlog_sm_contact_ball.x6_DOF_Joint_Spherical_Solid.Pz.p.series.values('m');

%% Plot results
simlog_handles(1) = subplot(2, 1, 1);
t_interp = 0:0.01:simlog_t(end);

% data interpolation with pchip
simlog_pz_int = interp1(simlog_t,simlog_pz,t_interp,'makima');

plot(t_interp, simlog_pz_int,...
    'LineWidth', 0.5,'Color',temp_colororder(1,:))
hold on
plot(simlog_t, simlog_pz,...
     'x','Color',temp_colororder(1,:))
hold off
grid on
title('Ball Height')
ylabel('Height (m)')

simlog_handles(2) = subplot(2, 1, 2);
semilogy(simlog_t(1:end-1), diff(simlog_t), '-x')

title('Step Size')
ylabel('Step Size (s)')
xlabel('Time (s)')

linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_handles temp_colororder

