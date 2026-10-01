% Code to plot simulation results from sm_contact_ball
%% Plot Description:
%
% <enter plot description here if desired>
%
% Copyright 2016-2026 The MathWorks, Inc.

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_contact_ball', 'var') || ...
        ~isgraphics(h1_sm_contact_ball, 'figure')
    h1_sm_contact_ball = figure('Name', 'sm_contact_ball');
end
figure(h1_sm_contact_ball)
clf(h1_sm_contact_ball)

temp_colororder = get(gca,'defaultAxesColorOrder');

mdl = 'sm_contact_ball';
% Get simulation results, ZCs on
set_param([mdl '/Spatial Contact Force 1'],'ZeroCrossDetectContactStartAndEnd','on');

sim(mdl);
simlog_zcOn_t = simlog_sm_contact_ball.x6_DOF_Joint_Spherical_Solid.Pz.p.series.time;
simlog_zcOn_pz = simlog_sm_contact_ball.x6_DOF_Joint_Spherical_Solid.Pz.p.series.values('m');

% Get simulation results, ZCs off
set_param([mdl '/Spatial Contact Force 1'],'ZeroCrossDetectContactStartAndEnd','off');
sim(mdl);
simlog_zcOff_t = simlog_sm_contact_ball.x6_DOF_Joint_Spherical_Solid.Pz.p.series.time;
simlog_zcOff_pz = simlog_sm_contact_ball.x6_DOF_Joint_Spherical_Solid.Pz.p.series.values('m');

% Turn ZCs back on
set_param([mdl '/Spatial Contact Force 1'],'ZeroCrossDetectContactStartAndEnd','on');

%% Plot results
simlog_handles(1) = subplot(2, 1, 1);
t_interp = 0:0.01:simlog_zcOn_t(end);

% data interpolation with pchip
simlog_zcOn_pz_int = interp1(simlog_zcOn_t,simlog_zcOn_pz,t_interp,'makima');
simlog_zcOff_pz_int = interp1(simlog_zcOff_t,simlog_zcOff_pz,t_interp,'makima');

plot(t_interp, simlog_zcOn_pz_int,...
    'LineWidth', 0.5,'Color',temp_colororder(1,:))
hold on
plot(simlog_zcOn_t, simlog_zcOn_pz,...
     'x','Color',temp_colororder(1,:))
plot(t_interp, simlog_zcOff_pz_int,...
    'LineWidth', 0.5,'Color',temp_colororder(2,:))
hold on
plot(simlog_zcOff_t, simlog_zcOff_pz,...
     'o','Color',temp_colororder(2,:))
hold off
grid on
title('Ball Height')
ylabel('Height (m)')

simlog_handles(2) = subplot(2, 1, 2);
semilogy(simlog_zcOn_t(1:end-1), diff(simlog_zcOn_t), '-x')
hold on
semilogy(simlog_zcOff_t(1:end-1), diff(simlog_zcOff_t), '-o')
%grid on
title('Step Size')
ylabel('Step Size (s)')
xlabel('Time (s)')
legend({['ZCs On: ' num2str(length(simlog_zcOn_t)) ' Steps'],...
    ['ZCs Off: ' num2str(length(simlog_zcOff_t)) ' Steps']},'Location','Best');

linkaxes(simlog_handles, 'x')

% Remove temporary variables
clear simlog_t simlog_handles temp_colororder

