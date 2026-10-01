% Code to plot simulation results from sm_spinning_top_totem
%% Plot Description:
%
% This is a plot of the rotational speed of the top.
%
% Copyright 2022-2026 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog_sm_spinning_top_totem', 'var')
    sim('sm_spinning_top_totem')
end

% Reuse figure if it exists, else create new figure
if ~exist('h1_sm_spinning_top_totem', 'var') || ...
        ~isgraphics(h1_sm_spinning_top_totem, 'figure')
    h1_sm_spinning_top_totem = figure('Name', 'sm_spinning_top_totem');
end
figure(h1_sm_spinning_top_totem)
clf(h1_sm_spinning_top_totem)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_wTop = logsout_sm_spinning_top_totem.get('wTop');

% Plot results
plot(simlog_wTop.Values.Time, simlog_wTop.Values.Data, 'LineWidth', 1)
grid on
title('Rotational Speed of Top')
ylabel('Speed (rev/s)')
xlabel('Time (s)')

% Remove temporary variables
clear simlog_handles
clear temp_colororder

