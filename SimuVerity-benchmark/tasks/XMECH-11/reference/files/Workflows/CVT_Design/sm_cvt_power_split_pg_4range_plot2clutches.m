function sm_cvt_power_split_pg_4range_plot2clutches(simlog)
% Code to plot simulation results from sm_cvt_power_split_pg_4range
%% Plot Description:
%
% The plot below shows the speeds of the three shafts attached to the
% planetary gear as different pairs of shafts are driven and locked.
%
% Copyright 2017-2025 The MathWorks, Inc.

% Generate simulation results if they don't exist
if ~exist('simlog', 'var')
    sim('sm_cvt_power_split_pg_4range')
end

% Reuse figure if it exists, else create new figure
figString = ['h1_' mfilename];
% Only create a figure if no figure exists
figExist = 0;
fig_hExist = evalin('base',['exist(''' figString ''')']);
if (fig_hExist)
    figExist = evalin('base',['ishandle(' figString ') && strcmp(get(' figString ', ''type''), ''figure'')']);
end
if ~figExist
    fig_h = figure('Name',figString);
    assignin('base',figString,fig_h);
else
    fig_h = evalin('base',figString);
end
figure(fig_h)
clf(fig_h)

temp_colororder = get(gca,'defaultAxesColorOrder');

% Get simulation results
simlog_t = simlog.Input_PG1_Ring.Revolute.Rz.w.series.time;
K1_data  = simlog.K1.PS_Switch.I2.series.values;
K2_data  = simlog.K2.PS_Switch.I2.series.values;
K3_data  = simlog.K3.PS_Switch.I2.series.values;
K4_data  = simlog.K4.PS_Switch.I2.series.values;
Kb_data  = simlog.Kb.PS_Switch.I2.series.values;

simlog_PG1r = simlog.Input_PG1_Ring.Revolute.Rz.w.series.values('rpm');
simlog_PG1s = simlog.Input_PG1_Sun.Revolute.Rz.w.series.values('rpm');

% Plot results
Pd_data     = simlog_PG1s./simlog_PG1r;
plot(simlog_t, 0.9*Pd_data/(max(Pd_data)-min(Pd_data)+eps)+5.45, 'LineWidth', 1)
hold on
plot(simlog_t, 0.9*K1_data/(max(K1_data)+eps)+4.05, 'LineWidth', 1)
plot(simlog_t, 0.9*K2_data/(max(K2_data)+eps)+3.05, 'LineWidth', 1)
plot(simlog_t, 0.9*K3_data/(max(K3_data)+eps)+2.05, 'LineWidth', 1)
plot(simlog_t, 0.9*K4_data/(max(K4_data)+eps)+1.05, 'LineWidth', 1)
plot(simlog_t, 0.9*Kb_data/(max(Kb_data)+eps)+0.05, 'LineWidth', 1)
hold off

set(gca,'YLim',[0 6])
set(gca,'YTick',0.5:1:6.5)
set(gca,'YTickLabel',{...
    'Kb',...
    'K4',...
    'K3',...
    'K2',...
    'K1',...
    'wS/wE'...
    })

xlabel('Time (s)');
title('Sun Speed/Engine Speed, Clutch States')
xlabel('Time (s)')

% Remove temporary variables
clear simlog_t temp_colororder

