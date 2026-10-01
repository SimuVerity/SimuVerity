%% Hydromechanical Power Split CVT
% 
% This example models a continuously variable transmission (CVT) using
% four different methods.  An abstract option models the CVT as a variable
% ratio gear which enables engineers to refine the requirements for the CVT
% before a technology is chosen. A second option is a pure hydrostatic CVT
% with a variable displacement pump and a fixed displacement motor. The
% third option is an electrical CVT, where the engine drives a generator
% and power is transmitted electrically to a motor which powers the
% drivetrain. The fourth option is a power-split CVT with parallel
% hydraulic and mechancial paths.
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example provides a simple test harness for a hydromechanical power
% split transmission.  The engine is assumed to run at a perfectly constant
% speed as the ratio of desired vehicle speed to engine speed is ramped up,
% cycling the transmission through each speed range.  A longitudinal
% vehicle model with a four-wheel drive powetrain serves as the mechanical
% load for the transmission.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt'); Open Model>

open_system('ssc_hydromech_power_split_cvt')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Power_Split_HM')
set_param(find_system('ssc_hydromech_power_split_cvt','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Transmission Variant Subsystems
%
% Four options for modeling the CVT are included in the model.  Using
% variant subsystems, one of them can be activated for a test.  The
% subsystems all have the same interface, which includes a mechanical
% connection to the engine and a mechanical connection to the driveline.
% Intefaces based on physical connections are particularly well-suited to
% swapping between models of different technologies or fidelity.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Transmission','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt/Transmission','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Transmission','force')

%% CVT: Abstract
%
% Models a CVT as a variable ratio gear. This model can be used in early
% stages of development to refine requirements for the transmission.  It
% can also be tuned to match a more detailed model of the CVT so as to
% provide accurate behavior with less computation.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Transmission/Abstract','force'); Open Subsystem>

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Abstract')
set_param('ssc_hydromech_power_split_cvt/Transmission/Abstract','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Transmission/Abstract','force')
set_param(bdroot,'SimulationCommand','update')

%% CVT: Hydrostatic
%
% Hydrostatic transmission with variable-displacement pump and
% fixed-displacement motor.  This system alone can also serve as a CVT, but
% it is not as efficient as the power-split design, as the mechanical path
% has a higher efficiency.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Transmission/Hydrostatic/Hydrostatic','force'); Open Subsystem>

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Hydrostatic')
set_param('ssc_hydromech_power_split_cvt/Transmission/Hydrostatic/Hydrostatic','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Transmission/Hydrostatic/Hydrostatic','force')
set_param(bdroot,'SimulationCommand','update')

%% CVT: Electrical
%
% Electrical transmission with generator, motor, and battery.  The input
% shaft drives a generator which is electrically connected to a motor which
% mechanically connected to the drivetrain.  A control system adjusts the
% torque request to the generator and motor so that the desired ratio of
% (input shaft speed/output shaft speed) is achieved.
% 
% The power source on the DC bus maintains stability of the DC bus and
% provides the current required of the motor that the generator cannot
% provide.  This can be due to variations in time constants for the motor
% and generator or if the generator reaches its power limit. 
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Transmission/Electrical','force'); Open Subsystem>

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Electrical')
set_param('ssc_hydromech_power_split_cvt/Transmission/Electrical','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Transmission/Electrical','force')
set_param(bdroot,'SimulationCommand','update')

%% CVT: Power Split Hydromechanical
%
% Transmission with four planetary gears, clutches, and a parallel power
% path through a hydrostatic transmission. A hydraulic regenerative braking
% system is also included to improve fuel economy by storing kinetic energy
% as pressure in an accumulator.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Transmission/Power%20Split%20Hydromech','force'); Open Subsystem>

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Power_Split_HM')
set_param('ssc_hydromech_power_split_cvt/Transmission/Power Split Hydromech','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Transmission/Power Split Hydromech','force')
set_param(bdroot,'SimulationCommand','update')

%% Vehicle Subsystem
%
% Models driveline and chassis of vehicle.  The output of the CVT connects to
% the output transfer gear of the driveline, and each driveshaft of the
% driveline connects to the chassis model.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Vehicle','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt/Vehicle','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Vehicle','force')

%% Driveline Subsystem
%
% Models a four-wheel drive driveline.  The output of the CVT connects to
% the output transfer gear which is connected via differentials to all four
% wheels.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Vehicle/Driveline','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt/Vehicle/Driveline','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Vehicle/Driveline','force')

%% Tires and Body Subsystem
%
% Models the chassis and tires of the vehicle.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt/Vehicle/Tires%20and%20Body');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Vehicle/Tires%20and%20Body','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt/Vehicle/Tires and Body','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt/Vehicle/Tires and Body','force')

%% Simulation Results: Accelerate and Decelerate, Abstract CVT 
%%
%
% Run acceleration and deceleration test with the abstract CVT.
%

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Abstract')
set_param([bdroot '/Transmission/Abstract'],'LinkStatus','none')
open_system([bdroot '/Transmission/Abstract'],'force')
set_param(bdroot,'SimulationCommand','update')

%%
sim('ssc_hydromech_power_split_cvt');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt)
ssc_hydromech_power_split_cvt_plot2pressure(simlog_ssc_hydromech_power_split_cvt.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt.Transmission)

% Get engine torque data
trqAbs = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.values('N*m');
timAbs = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.time;
CVTLoss_Abs = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt);
simlog_vVeh_Abs = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

%% Simulation Results: Accelerate and Decelerate, Hydrostatic CVT 
%%
%
% Run acceleration and deceleration test with the hydrostatic CVT.
%

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Hydrostatic')
set_param([bdroot '/Transmission/Hydrostatic'],'LinkStatus','none')
open_system([bdroot '/Transmission/Hydrostatic'],'force')
set_param(bdroot,'SimulationCommand','update')

%%
sim('ssc_hydromech_power_split_cvt');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt)
ssc_hydromech_power_split_cvt_plot2pressure(simlog_ssc_hydromech_power_split_cvt.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt.Transmission)

% Get engine torque data, CVT losses
trqHst = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.values('N*m');
timHst = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.time;
CVTLoss_HST = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt);
simlog_vVeh_HST = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

%% Simulation Results: Accelerate and Decelerate, Electrical CVT 
%%
%
% Run acceleration and deceleration test with the electrical CVT.
%

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Electrical')
set_param([bdroot '/Transmission/Electrical'],'LinkStatus','none')
open_system([bdroot '/Transmission/Electrical'],'force')
set_param(bdroot,'SimulationCommand','update')

%%
sim('ssc_hydromech_power_split_cvt');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt)
ssc_hydromech_power_split_cvt_plot4ecvtcurrent(simlog_ssc_hydromech_power_split_cvt.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt.Transmission)

% Get engine torque data
trqEle = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.values('N*m');
timEle = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.time;
CVTLoss_Ele = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt);
simlog_vVeh_Ele = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

%% Simulation Results: Accelerate and Decelerate, Power Split CVT 
%%
%
% Run acceleration and deceleration test with the power split CVT.
%

set_param([bdroot '/Transmission'],'LabelModeActiveChoice','Power_Split_HM')
set_param([bdroot '/Transmission/Power Split Hydromech'],'LinkStatus','none')
open_system([bdroot '/Transmission/Power Split Hydromech'],'force')
set_param(bdroot,'SimulationCommand','update')

%%
sim('ssc_hydromech_power_split_cvt');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt)
ssc_hydromech_power_split_cvt_plot2pressure(simlog_ssc_hydromech_power_split_cvt.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt.Transmission)

% Get engine torque data
trqPSP = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.values('N*m');
timPSP = simlog_ssc_hydromech_power_split_cvt.Velocity_Source.t.series.time;
CVTLoss_PSP = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt);
simlog_vVeh_PSP = simlog_ssc_hydromech_power_split_cvt.Vehicle.Tires_and_Body.Vehicle_Body.v.series.values('km/hr');

%% Comparison of CVT Models
%
% The following plot compares the input torque for tests with the power
% split CVT and the abstract CVT models.  The input shaft is spun at a
% fixed velocity, so we can see that the abstract CVT has been tuned to
% give similar performance as the power split hydromechanical CVT. 
%
% The power split hydromechanical CVT is more efficient than the
% hydrostatic CVT for this drive cycle.  The parallel mechanical path has a
% higher efficiency, and as a result for this test that goes up to maximum
% speed and back down again the losses are lower for power split CVT than
% the pure hydrostatic CVT.

figure(44)
subplot(211)
plot(timPSP,simlog_vVeh_PSP,'LineWidth',2,'DisplayName','Power Split');
hold on
plot(timAbs,simlog_vVeh_Abs,'--','LineWidth',2,'DisplayName','Abstract');
plot(timHst,simlog_vVeh_HST,'-.','LineWidth',2,'DisplayName','Hydrostatic');
plot(timEle,simlog_vVeh_Ele,':','LineWidth',2,'DisplayName','Electrical');
hold off
title('Vehicle Speed (km/h)')
legend('Location','Best')
ylabel('Speed (km/h)')
subplot(212)
plot(timPSP,trqPSP,'LineWidth',1,'DisplayName',['Power Split Losses: '   sprintf('%3.2f',CVTLoss_PSP) ' kWh']);
hold on
plot(timAbs,trqAbs,'LineWidth',2,'DisplayName',['Abstract Losses:      ' sprintf('%3.2f',CVTLoss_Abs) ' kWh']);
plot(timHst,trqHst,'LineWidth',2,'DisplayName',['Hydrostatic Losses: '   sprintf('%3.2f',CVTLoss_HST) ' kWh']);
plot(timEle,trqEle,'LineWidth',2,'DisplayName',['Electrical Losses:    ' sprintf('%3.2f',CVTLoss_Ele) ' kWh']);
hold off
ylabel('CVT Input Torque (N*m)')
xlabel('Time (s)');
yRange = abs(max([trqAbs;trqHst])-min([trqAbs;trqHst]));
set(gca,'YLim',[min([trqAbs;trqHst])-0.1*yRange max([trqAbs;trqHst])+0.1*yRange])
legend('Location','Best')
title('Comparison of CVT Models')

%%

close all
bdclose('ssc_hydromech_power_split_cvt');
