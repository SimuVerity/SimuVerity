function sm_wheel_loader_steer_plot2steering(simlog)
% Code to plot simulation results from sm_wheel_loader_steer
%
% Copyright 2023-2025 The MathWorks, Inc.

if(~isempty(find(strcmp(fieldnames(simlog),'Pump_Steer'), 1)))

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
    temp_colororder = colororder;

    %% Get simulation results
    simlog_t           = simlog.Pump_Steer.p_diff.series.time;
    simlog_qWhl        = simlog.Frame_Rear.Revolute_Steer.Rz.q.series.values('rev');
    simlog_xCyl        = simlog.Actuator_Steer.Actuator_Steer.hard_stop.x.series.values('m');
    simlog_qFtoR       = simlog.Revolute_Front_Rear.Rz.q.series.values('deg');

    %% Plot results
    ah(1) = subplot(2,1,1);
    yyaxis left
    plot(simlog_t, simlog_qFtoR,'LineWidth', 1,'DisplayName','Articulation Angle')
    ylabel('deg')
    yLims = get(gca,'YLim');
    set(gca,'YLim',[-1.1 1.1]*max(abs(yLims)))
    hold on
    yyaxis right
    plot(simlog_t, simlog_qWhl,'LineWidth', 1,'DisplayName','Steering Wheel Angle')
    ylabel('rev')
    yLims = get(gca,'YLim');
    set(gca,'YLim',[-1.1 1.1]*max(abs(yLims)))
    hold off
    grid on
    title('Articulation Angle')
    xlabel('Time (s)')
    legend('Location','Best');
    
    ah(2) = subplot(2,1,2);
    plot(simlog_t, simlog_xCyl,'LineWidth', 1)
    grid on
    title('Cylinder Position')
    ylabel('m')

    linkaxes(ah,'x')
    %% Remove temporary variables
end