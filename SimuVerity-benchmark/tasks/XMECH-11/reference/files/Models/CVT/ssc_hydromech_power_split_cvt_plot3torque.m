function ssc_hydromech_power_split_cvt_plot3torque(simlog_vehicle)
% Code to plot simulation results from ssc_hydromech_power_split_cvt

% Copyright 2023-2025 The MathWorks, Inc.

createPlot = false;
%% Get simulation results
if(~isempty(find(strcmp(fieldnames(simlog_vehicle),'Body_to_World'))))
    % For model sm_wheel_loader
    simlog_t          = simlog_vehicle.Power_Sensor1_Engine_Out.Power_Sensor.t_S.series.time;
    simlog_trqEng     = simlog_vehicle.Power_Sensor1_Engine_Out.Power_Sensor.t_S.series.values('N*m');
    simlog_trqCVTOut  = simlog_vehicle.Power_Sensor2_CVT_Out.Power_Sensor.t_S.series.values('N*m');

    % Extract results 1D or 3D driveline
    if(isempty(find(strcmp(fieldnames(simlog_vehicle.Vehicle.Driveline.Driveline),'Driveline_1D'))))
        simlog_drv = simlog_vehicle.Vehicle.Driveline.Driveline.Driveline_3D;
    else
        simlog_drv = simlog_vehicle.Vehicle.Driveline.Driveline.Driveline_1D;
    end

    % Obtain rotational speeds of wheels (for sign only)
    simlog_wLF = simlog_drv.Planetary_FL.Revolute_Ring_Carrier.Rz.w.series.values('rad/s');
    simlog_wRF = simlog_drv.Planetary_FR.Revolute_Ring_Carrier.Rz.w.series.values('rad/s');
    simlog_wLR = simlog_drv.Planetary_RL.Revolute_Ring_Carrier.Rz.w.series.values('rad/s');
    simlog_wRR = simlog_drv.Planetary_RR.Revolute_Ring_Carrier.Rz.w.series.values('rad/s');

    % Calculate signed vehicle chassis speed
    % Components
    simlog_vx         = simlog_vehicle.Body_to_World.Px.v.series.values('km/hr');
    simlog_vy         = simlog_vehicle.Body_to_World.Py.v.series.values('km/hr');
    % Magnitude * sign from wheels
    simlog_vehspd       = sqrt(simlog_vx.^2+simlog_vy.^2).*sign(simlog_wLF+simlog_wRF+simlog_wLR+simlog_wRR);

    createPlot = true;
else
    simlog_t          = simlog_vehicle.Power_Sensor1_Engine_Out.Power_Sensor.t_S.series.time;
    simlog_trqEng     = simlog_vehicle.Power_Sensor1_Engine_Out.Power_Sensor.t_S.series.values('N*m');
    simlog_trqCVTOut  = simlog_vehicle.Power_Sensor2_CVT_Out.Power_Sensor.t_S.series.values('N*m');
    simlog_vehspd     = simlog_vehicle.Vehicle.Tires_and_Body.Vehicle_Body.V.series.values('km/hr');
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
    plot(simlog_t, simlog_trqEng,'LineWidth', 1,'DisplayName','Engine')
    hold on
    plot(simlog_t, simlog_trqCVTOut,'-.','LineWidth', 1,'DisplayName','CVT Out')
    grid on
    title('Torque')
    ylabel('N*m')
    legend('Location','Best')
    hold off
    ah(2) = subplot(212);
    plot(simlog_t, simlog_vehspd,'LineWidth', 1)
    grid on
    title('Vehicle Speed')
    ylabel('km/hr')
    xlabel('Time (s)');

    linkaxes(ah,'x')
end