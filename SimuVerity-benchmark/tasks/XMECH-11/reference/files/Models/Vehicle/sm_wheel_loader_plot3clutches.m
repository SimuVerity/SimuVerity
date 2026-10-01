function sm_wheel_loader_plot3clutches(simlog_trans)
% Code to plot simulation results from sm_wheel_loader

% Copyright 2020-2025 The MathWorks, Inc.

%% Plot results
if(~isempty(find(strcmp(fieldnames(simlog_trans),'Power_Split_Hydromech'))))
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

    K1_data = simlog_trans.Power_Split_Hydromech.K1.Clutch.P.series.values('Pa');
    K2_data = simlog_trans.Power_Split_Hydromech.K2.Clutch.P.series.values('Pa');
    K3_data = simlog_trans.Power_Split_Hydromech.K3.Clutch.P.series.values('Pa');
    K4_data = simlog_trans.Power_Split_Hydromech.K4.Clutch.P.series.values('Pa');
    Kb_data = simlog_trans.Power_Split_Hydromech.Kb.Clutch.P.series.values('Pa');
    Kv_data = simlog_trans.Power_Split_Hydromech.Kv.Clutch.P.series.values('Pa');
    Kr_data = simlog_trans.Power_Split_Hydromech.Kr.Clutch.P.series.values('Pa');

    Pd_data = simlog_trans.Power_Split_Hydromech.Hydrostatic.Pump.D.series.values;
    Mb_data = simlog_trans.Power_Split_Hydromech.Brake_Out.Brake.P.series.values('Pa');

    time_vec = simlog_trans.Power_Split_Hydromech.K1.Clutch.P.series.time;

    plot(time_vec, 0.9*Pd_data/(max(Pd_data)-min(Pd_data)+eps)+8.45, 'LineWidth', 1)
    hold on
    plot(time_vec, 0.9*Mb_data/(max(Mb_data)+eps)+7.05, 'LineWidth', 1)
    plot(time_vec, 0.9*K1_data/(max(K1_data)+eps)+6.05, 'LineWidth', 1)
    plot(time_vec, 0.9*K2_data/(max(K2_data)+eps)+5.05, 'LineWidth', 1)
    plot(time_vec, 0.9*K3_data/(max(K3_data)+eps)+4.05, 'LineWidth', 1)
    plot(time_vec, 0.9*K4_data/(max(K4_data)+eps)+3.05, 'LineWidth', 1)
    plot(time_vec, 0.9*Kb_data/(max(Kb_data)+eps)+2.05, 'LineWidth', 1)
    plot(time_vec, 0.9*Kv_data/(max(Kv_data)+eps)+1.05, 'LineWidth', 1)
    plot(time_vec, 0.9*Kr_data/(max(Kr_data)+eps)+0.05, 'LineWidth', 1)
    hold off

    set(gca,'YLim',[0 9])
    set(gca,'YTick',0.5:1:9.5)
    set(gca,'YTickLabel',{...
        'Kr',...
        'Kv',...
        'Kb',...
        'K4',...
        'K3',...
        'K2',...
        'K1',...
        'Mb',...
        'Pd'...
        })

    xlabel('Time (s)');
    title('Clutch States, Brake Pressure, Pump Displacement')

    % Remove temporary variables
    clear simlog_handles
end

