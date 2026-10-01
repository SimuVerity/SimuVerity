function ssc_hydromech_power_split_cvt_plot4ecvtcurrent(simlog_trans)
% Code to plot simulation results from ssc_hydromech_power_split_cvt

% Copyright 2023-2025 The MathWorks, Inc.

createPlot = false;
%% Get simulation results
if(~isempty(find(strcmp(fieldnames(simlog_trans),'Electrical'))))
    simlog_t        = simlog_trans.Electrical.Generator.i.series.time;
    simlog_iGen     = simlog_trans.Electrical.Generator.i.series.values('A');
    simlog_iMotor   = simlog_trans.Electrical.Motor.i.series.values('A');
    simlog_iBattery = simlog_trans.Electrical.Battery.i.series.values('A');
    simlog_trqGen   = simlog_trans.Electrical.Generator.torque_elec.series.values('N*m');
    simlog_trqMotor = simlog_trans.Electrical.Motor.torque_elec.series.values('N*m');
    createPlot = true;
end

%% Reuse figure if it exists, else create new figure
if(createPlot)
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


    %% Plot results
    ah(1) = subplot(211);
    plot(simlog_t, simlog_iGen,'LineWidth', 1,'DisplayName','Generator')
    hold on
    plot(simlog_t, simlog_iMotor,'-.','LineWidth', 1,'DisplayName','Motor')
    plot(simlog_t, simlog_iBattery,'-.','LineWidth', 1,'DisplayName','Battery')
    grid on
    title('Current')
    ylabel('A')
    legend('Location','Best')
    hold off
    ah(2) = subplot(212);
    plot(simlog_t, -simlog_trqGen,'LineWidth', 1,'DisplayName','Generator')
    hold on
    plot(simlog_t, -simlog_trqMotor,'LineWidth', 1,'DisplayName','Motor')
    grid on
    title('Torque')
    ylabel('N*m')
    xlabel('Time (s)');
    legend('Location','Best')

    linkaxes(ah,'x')
end