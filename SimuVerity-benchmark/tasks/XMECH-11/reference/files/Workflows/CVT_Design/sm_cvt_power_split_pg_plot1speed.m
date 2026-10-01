function sm_cvt_power_split_pg_plot1speed(simlog,logsout,cvtPar)
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
simlog_t    = simlog.Input_PG1_Ring.Revolute.Rz.w.series.time;
simlog_PG1r = simlog.Input_PG1_Ring.Revolute.Rz.w.series.values('rpm');
simlog_PG1s = simlog.Input_PG1_Sun.Revolute.Rz.w.series.values('rpm');
simlog_POut = squeeze(logsout.get('CVT Output').Values.Data);

nS2R = simlog_PG1s./simlog_PG1r;
nE2R = simlog_POut./simlog_PG1r;
nRangeStr = sprintf('wSun/wEngine Range:     %1.2f, %1.2f\nwOutput/wEngine Range: %1.2f, %1.2f',...
    min(nS2R),max(nS2R),min(nE2R),max(nE2R));

%nE2RrangeStr = sprintf('wSun/Engine Range: %1.2f, %1.2f',min(nE2R),max(nE2R));


% Plot results
plot(simlog_t, simlog_PG1r,'Color',cvtPar.clr.inputE, 'LineWidth', 2, 'DisplayName','Engine')
hold on
plot(simlog_t, simlog_PG1s, 'Color',cvtPar.clr.inputH*0.9,'LineWidth', 2, 'DisplayName','PG 1 Sun')
plot(simlog_t, simlog_POut, 'Color',cvtPar.clr.output, 'LineWidth', 2, 'DisplayName','CVT Output')
text(0.05,0.9,nRangeStr,'Color',[1 1 1]*0.6,'Units','Normalized','HorizontalAlignment','left')
hold off
grid on
title('Power Split Shaft Speeds')
ylabel('Speed (RPM)')
legend('Location','SouthEast');
xlabel('Time (s)')

% Remove temporary variables
clear simlog_t temp_colororder
clear simlog_wCarr simlog_wSun simlog_wRing
