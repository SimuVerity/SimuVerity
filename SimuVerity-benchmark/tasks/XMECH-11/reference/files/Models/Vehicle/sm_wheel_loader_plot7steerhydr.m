function sm_wheel_loader_plot7steerhydr(simlog)
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
    simlog_t       = simlog.Pump_Steer.p_diff.series.time;
    simlog_steerAp  = simlog.Actuator_Steer.Actuator_Steer.A.p.series.values('bar');
    simlog_steerBp  = simlog.Actuator_Steer.Actuator_Steer.B.p.series.values('bar');
    simlog_steerAmdot  = simlog.Actuator_Steer.Actuator_Steer.chamber_A.mdot_A.series.values('kg/s');

    %% Plot results
    ah(1) = subplot(2,1,1);
    plot(simlog_t, simlog_steerAmdot,'LineWidth', 1,'DisplayName','Steer')
    grid on
    title('Mass Flow Rate')
    ylabel('Flow Rate (kg/s) ')
    legend('Location','Best');

    ah(2) = subplot(2,1,2);

    plot(simlog_t, simlog_steerAp,'LineWidth', 1,'Color',temp_colororder(1,:),'DisplayName','pA')
    hold on
    plot(simlog_t, simlog_steerBp,'LineWidth', 1,'Color',temp_colororder(1,:),'LineStyle','--','DisplayName','pB')
    hold off
    grid on
    title('Pressures')
    ylabel('bar')
    xlabel('Time (s)')
    legend('Location','Best');

    linkaxes(ah,'x')
    %% Remove temporary variables
end