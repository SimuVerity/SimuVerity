%% Hydromechanical Power Split CVT with Engine
% 
% This example models a vehicle with a hydromechanical power split
% continuously variable transmission (CVT).  It contains the engine, CVT,
% and longitudinal vehicle with four-wheel drive. This model enables:
%
% * *Powertrain efficiency studies* to evaluate different technologies and
% designs to determine where power is lost
% * *Powertrain control design* to create algorithms in Simulink and
% Stateflow that control the engine and CVT.
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a vehicle with a hydromechanical power split
% continuously variable transmission (CVT).
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine'); Open Model>

open_system('ssc_hydromech_power_split_cvt_engine')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Power_Split_HM')
set_param([bdroot '/Vehicle with CVT/Engine'],'LabelModeActiveChoice','Droop')
set_param(find_system('ssc_hydromech_power_split_cvt_engine','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Vehicle with CVT Subsystem
%
% Models engine, transmission, and vehicle.  The engine can be configured
% to have droop control or a simple PI control.  The transmission can be
% swapped between multiple options to explore different technologies or to
% select a fidelity level appropriate for the current test.  The vehicle
% model includes the driveline and chassis.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT','force')
set_param(find_system('ssc_hydromech_power_split_cvt_engine','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Transmission Variant Subsystems
%
% Four options for modeling the CVT are included in the model.  Using
% variant subsystems, one of them can be activated for a test.  The
% subsystems all have the same interface, which includes a mechanical
% connection to the engine and a mechanical connection to the driveline.
% Intefaces based on physical connections are particularly well-suited to
% swapping between models of different technologies or fidelity.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Transmission','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission','force')

%% Power Split Hydromechanical CVT Subsystem
%
% Transmission with four planetary gears, clutches, and a parallel power
% path through a hydrostatic transmission. A hydraulic regenerative braking
% system is also included to improve fuel economy by storing kinetic energy
% as pressure in an accumulator.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Transmission/Power%20Split%20Hydromech','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Power Split Hydromech','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Power Split Hydromech','force')

%% Hydrostatic Transmission Subsystem
%
% Hydrostatic transmission with variable-displacement pump and
% fixed-displacement motor.  This system alone can also serve as a CVT, but
% it is not as efficient as the power-split design, as the mechanical path
% has a higher efficiency.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Transmission/Hydrostatic','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Power Split Hydromech/Hydrostatic','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Power Split Hydromech/Hydrostatic','force')

%% Electrical Transmission Subsystem
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
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Transmission/Electrical','force'); Open Subsystem>

set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Electrical')
set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Electrical','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Electrical','force')
set_param(bdroot,'SimulationCommand','update')

%% Abstract CVT Subsystem
%
% Models a CVT as a variable ratio gear. This model can be used in early
% stages of development to refine requirements for the transmission.  It
% can also be tuned to match a more detailed model of the CVT so as to
% provide accurate behavior with less computation.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt');open_system('ssc_hydromech_power_split_cvt/Vehicle%20with%20CVT/Transmission/Abstract','force'); Open Subsystem>

set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Abstract')
set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Abstract','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Transmission/Abstract','force')
set_param(bdroot,'SimulationCommand','update')


%% Driveline Subsystem
%
% Models a four-wheel drive driveline.  The output of the CVT connects to
% the output transfer gear which is connected via differentials to all four
% wheels.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Vehicle/Driveline','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Vehicle/Driveline','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Vehicle/Driveline','force')

%% Tires and Body Subsystem
%
% Models the chassis and tires of the vehicle.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Vehicle/Tires%20and%20Body');open_system('ssc_hydromech_power_split_cvt_engine/Vehicle%20with%20CVT/Vehicle/Tires%20and%20Body','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Vehicle/Tires and Body','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine/Vehicle with CVT/Vehicle/Tires and Body','force')


%% Simulation Results: Load Cycle, Power Split CVT
%
% Run load cycle with the power split CVT.
%

set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Power_Split_HM')
set_param([bdroot '/Vehicle with CVT/Engine'],'LabelModeActiveChoice','Droop')

sim('ssc_hydromech_power_split_cvt_engine');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT)
ssc_hydromech_power_split_cvt_plot2pressure(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Transmission)

% Get engine torque data
trqPSP = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.values('N*m');
timPSP = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.time;
CVTLoss_PSP = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT);

%% Simulation Results: Load Cycle, Abstract CVT
%
% Run load cycle with the abstract split CVT.
%

set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Abstract')

%%
sim('ssc_hydromech_power_split_cvt_engine');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT)
ssc_hydromech_power_split_cvt_plot2pressure(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Transmission)

% Get engine torque data
trqAbs = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.values('N*m');
timAbs = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.time;
CVTLoss_Abs = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT);

%% Simulation Results: Accelerate and Decelerate, Hydrostatic CVT 
%
% Run load cycle with the hydrostatic CVT.
%

set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Hydrostatic')

%%
sim('ssc_hydromech_power_split_cvt_engine');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT)
ssc_hydromech_power_split_cvt_plot2pressure(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT)

% Get engine torque data, CVT losses
trqHst = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.values('N*m');
timHst = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.time;
CVTLoss_HST = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT);

%% Simulation Results: Accelerate and Decelerate, Electrical CVT 
%
% Run load cycle with the electrical CVT.
%

set_param([bdroot '/Vehicle with CVT/Transmission'],'LabelModeActiveChoice','Electrical')

%%
sim('ssc_hydromech_power_split_cvt_engine');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT,HMPST.Tire.Rad)
ssc_hydromech_power_split_cvt_plot3torque(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT)
ssc_hydromech_power_split_cvt_plot4ecvtcurrent(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Transmission)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT)

% Get engine torque data, CVT losses
trqEle = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.values('N*m');
timEle = simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT.Engine.Engine_Droop.Torque_Sensor.Torque_Sensor.t.series.time;
CVTLoss_Ele = calcPowerLossCVT(simlog_ssc_hydromech_power_split_cvt_engine.Vehicle_with_CVT);

%% Comparison of CVT Models
%
% The following plot compares the input torque for tests with the power
% split CVT and the abstract CVT models.  This load cycle has long periods
% of time where the loader is not moving. During periods when the loader is
% standing still, the power split CVT has higher losses because the
% hydrostatic transmission and other shafts are spinning.  

figure(44)
plot(timPSP,trqPSP,'LineWidth',1,'DisplayName',['Power Split: CVT Losses ' sprintf('%3.2f',CVTLoss_PSP)]);
hold on
plot(timAbs,trqAbs,'LineWidth',2,'DisplayName',['Abstract:      CVT Losses ' sprintf('%3.2f',CVTLoss_Abs)]);
plot(timHst,trqHst,'LineWidth',2,'DisplayName',['Hydrostatic: CVT Losses ' sprintf('%3.2f',CVTLoss_HST)]);
plot(timEle,trqEle,'LineWidth',2,'DisplayName',['Electrical:    CVT Losses ' sprintf('%3.2f',CVTLoss_Ele)]);
hold off
ylabel('CVT Input Torque (N*m)')
xlabel('Time (s)');
yRange = abs(max([trqAbs;trqHst])-min([trqAbs;trqHst]));
set(gca,'YLim',[min([trqAbs;trqHst])-0.1*yRange max([trqAbs;trqHst])+0.1*yRange])
legend('Location','Best')
title('Comparison of CVT Models')

%% Explore Effect of Hydraulic Regenerative Braking
%
% The following plot compares a test with and without the hydraulic
% regenerative braking (HRB) system.  The HRB stores energy in an
% accumulator during braking events, and releases that energy to
% accelerate the vehicle.  This system increases the efficiency of the
% vehicle and reduces the demand on the engine.
%
% The plot below shows an acceleration and deceleration profile. During the
% acceleration phase (between 11 and 12 seconds), the engine needs to
% provide more power if the HRB is disabled.  During the deceleration
% phase, the sign of the HRB power is negative indicating energy is being
% stored in the HRB.

ssc_hydromech_power_split_cvt_engine_plot3hrb

%%

close all
bdclose('ssc_hydromech_power_split_cvt_engine');
