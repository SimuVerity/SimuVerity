function sm_wheel_loader_plot6linkagehydr(simlog_hydr)
% Code to plot simulation results from sm_wheel_loader
%
% Copyright 2023-2025 The MathWorks, Inc.


if(~isempty(find(strcmp(fieldnames(simlog_hydr),'Pump_Impl'), 1)))

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
    simlog_t       = simlog_hydr.Pump_Impl.p_diff.series.time;
    simlog_liftAp  = simlog_hydr.Actuator_Linkage.Actuator_LiftL.A.p.series.values('bar');
    simlog_liftBp  = simlog_hydr.Actuator_Linkage.Actuator_LiftL.B.p.series.values('bar');
    simlog_tiltAp  = simlog_hydr.Actuator_Linkage.Actuator_Tilt.A.p.series.values('bar');
    simlog_tiltBp  = simlog_hydr.Actuator_Linkage.Actuator_Tilt.B.p.series.values('bar');
    simlog_liftAmdot  = simlog_hydr.Actuator_Linkage.Actuator_LiftL.chamber_A.mdot_A.series.values('kg/s');
    simlog_tiltAmdot  = simlog_hydr.Actuator_Linkage.Actuator_Tilt.chamber_A.mdot_A.series.values('kg/s');

    %% Plot results
    ah(1) = subplot(2,1,1);
    plot(simlog_t, simlog_liftAmdot,'LineWidth', 1,'DisplayName','Lift')
    hold on
    plot(simlog_t, simlog_tiltAmdot,'LineWidth', 1,'DisplayName','Tilt')
    hold off
    grid on
    title('Mass Flow Rate')
    ylabel('Flow Rate (kg/s) ')
    legend('Location','Best');

    ah(2) = subplot(2,1,2);

    plot(simlog_t, simlog_liftAp,'LineWidth', 1,'Color',temp_colororder(1,:),'DisplayName','Lift pA')
    hold on
    plot(simlog_t, simlog_liftBp,'LineWidth', 1,'Color',temp_colororder(1,:),'LineStyle','--','DisplayName','Lift pB')
    plot(simlog_t, simlog_tiltAp,'LineWidth', 1,'Color',temp_colororder(2,:),'DisplayName','Tilt pA')
    plot(simlog_t, simlog_tiltBp,'LineWidth', 1,'Color',temp_colororder(2,:),'LineStyle','--','DisplayName','Tilt pB')
    hold off
    grid on
    title('Pressures')
    ylabel('bar')
    xlabel('Time (s)')
    legend('Location','Best');

    linkaxes(ah,'x')
    %% Remove temporary variables
end