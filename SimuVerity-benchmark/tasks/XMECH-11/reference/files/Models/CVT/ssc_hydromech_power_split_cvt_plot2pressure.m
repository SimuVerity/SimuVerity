function ssc_hydromech_power_split_cvt_plot2pressure(simlog_trans)
% Code to plot simulation results from ssc_hydromech_power_split_cvt

% Copyright 2023-2025 The MathWorks, Inc.

createPlot = false;
%% Get simulation results
if(~isempty(find(strcmp(fieldnames(simlog_trans),'Power_Split_Hydromech'))))
    simlog_t          = simlog_trans.Power_Split_Hydromech.Hydrostatic.Pump.p_diff.series.time;
    simlog_PumpPDiff  = simlog_trans.Power_Split_Hydromech.Hydrostatic.Pump.p_diff.series.values('MPa');
    simlog_MotorPDiff = simlog_trans.Power_Split_Hydromech.Hydrostatic.Motor.p_diff.series.values('MPa');
    simlog_PumpD      = simlog_trans.Power_Split_Hydromech.Hydrostatic.Pump.D.series.values('cm^3/rev');
    createPlot = true;
elseif(~isempty(find(strcmp(fieldnames(simlog_trans),'Hydrostatic'))))
    simlog_t          = simlog_trans.Hydrostatic.Hydrostatic.Pump.p_diff.series.time;
    simlog_PumpPDiff  = simlog_trans.Hydrostatic.Hydrostatic.Pump.p_diff.series.values('MPa');
    simlog_MotorPDiff = simlog_trans.Hydrostatic.Hydrostatic.Motor.p_diff.series.values('MPa');
    simlog_PumpD      = simlog_trans.Hydrostatic.Hydrostatic.Pump.D.series.values('cm^3/rev');
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
    plot(simlog_t, simlog_PumpPDiff,'LineWidth', 1,'DisplayName','Pump')
    hold on
    plot(simlog_t, simlog_MotorPDiff,'-.','LineWidth', 1,'DisplayName','Motor')
    grid on
    title('Pressure Difference')
    ylabel('MPa')
    legend('Location','Best')
    hold off
    ah(2) = subplot(212);
    plot(simlog_t, simlog_PumpD,'LineWidth', 1,'DisplayName','Pump Disp.')
    grid on
    title('Pump Displacement')
    ylabel('cm^3/rev')
    xlabel('Time (s)');

    linkaxes(ah,'x')
end