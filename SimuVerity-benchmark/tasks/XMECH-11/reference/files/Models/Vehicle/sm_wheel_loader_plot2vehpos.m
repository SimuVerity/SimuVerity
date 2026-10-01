function sm_wheel_loader_plot2vehpos(simlog_veh)
% Code to plot simulation results from sm_wheel_loader
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Reuse figure if it exists, else create new figure
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

%% Get simulation results
simlog_t    = simlog_veh.Wheel_Loader.Body_to_World.Px.p.series.time;
simlog_posx = simlog_veh.Wheel_Loader.Body_to_World.Px.p.series.values('m');
simlog_posy = simlog_veh.Wheel_Loader.Body_to_World.Py.p.series.values('m');

%% Plot results
plot(simlog_posx, simlog_posy,'Color',[1.0000 0.5961 0.0549],'LineWidth', 2,'DisplayName','Vehicle Position')
grid on
title('Vehicle Position')
ylabel('Position (m)')
xlabel('Position (m)')
%legend('Location','Best');

temp_xLimits = get(gca, 'XLim');
temp_yLimits = get(gca, 'YLim');
xticks(round(temp_xLimits(1)):1:round(temp_xLimits(2)))
yticks(round(temp_yLimits(1)):1:round(temp_yLimits(2)))
set(gca,'Color',[0.9 0.9 0.9])
set(gca,'GridColor',[1 1 1],'GridLineWidth',1.5,'GridAlpha',1)
axis equal
