% Code to plot simulation results from sm_tippe_top
%% Plot Description:
%
% This plot compares the effect of selected contact proxies at the head and
% base of the top.  The Point Cloud will result in higher levels of
% friction than the sphere for the same friction coefficients.  This is
% because multi-point contact will have a higher relative velocity,
% especially for objects that spin about an axis that passes through the
% contact point.
%
% Copyright 2022-2026 The MathWorks, Inc.

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_tippe_top', 'var') || ...
        ~isgraphics(h1_sm_tippe_top, 'figure')
    h1_sm_tippe_top = figure('Name', 'sm_tippe_top');
end
figure(h1_sm_tippe_top)
clf(h1_sm_tippe_top)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Set proxies to sphere
mdl = 'sm_tippe_top';
set_param([mdl '/Top'],'popup_contact_head','Sphere');
set_param([mdl '/Top'],'popup_contact_base','Sphere');
sim(mdl)
simlog_wTop_SphSph = logsout_sm_tippe_top.get('wTop');

% Set head proxy to point cloud
mdl = 'sm_tippe_top';
set_param([mdl '/Top'],'popup_contact_head','Point Cloud');
set_param([mdl '/Top'],'popup_contact_base','Sphere');
sim(mdl)
simlog_wTop_PCSph = logsout_sm_tippe_top.get('wTop');

% Set base proxy to point cloud
mdl = 'sm_tippe_top';
set_param([mdl '/Top'],'popup_contact_head','Sphere');
set_param([mdl '/Top'],'popup_contact_base','Point Cloud');
sim(mdl)
simlog_wTop_SphPC = logsout_sm_tippe_top.get('wTop');

% Set proxies to point cloud
mdl = 'sm_tippe_top';
set_param([mdl '/Top'],'popup_contact_head','Point Cloud');
set_param([mdl '/Top'],'popup_contact_base','Point Cloud');
sim(mdl)
simlog_wTop_PCPC = logsout_sm_tippe_top.get('wTop');


% Plot results
plot(simlog_wTop_SphSph.Values.Time, simlog_wTop_SphSph.Values.Data,...
    'LineWidth', 2,'DisplayName','Head: Sphere, Base: Sphere')
hold on
plot(simlog_wTop_PCSph.Values.Time, simlog_wTop_PCSph.Values.Data,...
    'LineWidth', 2,'DisplayName','Head: Points,   Base: Sphere')
plot(simlog_wTop_SphPC.Values.Time, simlog_wTop_SphPC.Values.Data,...
    'LineWidth', 2,'DisplayName','Head: Sphere, Base: Points')
plot(simlog_wTop_PCPC.Values.Time, simlog_wTop_PCPC.Values.Data,...
    'LineWidth', 2,'DisplayName','Head: Points,   Base: Points')
hold off
grid on
title('Rotational Speed of Top')
ylabel('Speed (rev/s)')
xlabel('Time (s)')
legend('Location','Best')
% Remove temporary variables
clear simlog_handles
clear temp_colororder
