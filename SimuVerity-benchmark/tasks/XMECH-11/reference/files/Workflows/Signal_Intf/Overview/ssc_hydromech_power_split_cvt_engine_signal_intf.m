%% Wheel Loader CVT with Signal Interface
% 
% This example models a vehicle with a hydromechanical power split
% continuously variable transmission (CVT).  It contains the engine, CVT,
% and longitudinal vehicle with four-wheel drive. 
%
% This model has been decomposed into separate segments using Simulink
% signals.  This is only recommended when the model requires integration
% with other components modeled with a signal-based interface, such as
% FMUs or Simulink implementations.  To see this model implemented with
% Simscape physical connections, see <matlab:web('ssc_hydromech_power_split_cvt_engine.html') Hydromechanical Power Split CVT with Engine>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a vehicle with a hydromechanical power split
% continuously variable transmission (CVT).  The individual Simscape
% networks have been decoupled using Simulink signals so that the
% individual networks can be run with independent local solver settings or
% replaced with FMUs.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine_signal_intf'); Open Model>

open_system('ssc_hydromech_power_split_cvt_engine_signal_intf')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param([bdroot '/CVT'],'LabelModeActiveChoice','Simscape')
set_param([bdroot '/CVT/Simscape/Transmission'],'LabelModeActiveChoice','Power_Split_HM')
ann_h = find_system('ssc_hydromech_power_split_cvt_engine_signal_intf','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures');
for anhi=1:length(ann_h)
    set_param(ann_h(anhi),'Interpreter','off');
end
%% Engine Subsystem
%
% Models engine with droop controller.  This Simscape network is configured
% to use the Simscape Local Solver.  It enables this portion of the model
% to use unique Local Solver settings.  The signal interface was set up
% using the
% <matlab:web(fullfile(docroot,'simscape/ref/networkcouplerflexibleshaft.html')); Network Coupler (Flexible Shaft)>
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine_signal_intf');open_system('ssc_hydromech_power_split_cvt_engine_signal_intf/Engine/Simscape','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine_signal_intf/Engine/Simscape','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine_signal_intf/Engine/Simscape','force')

%% CVT Subsystem
%
% Three options for modeling the CVT are included in the model.  Using
% variant subsystems, one of them can be activated for a test.  The
% subsystems all have the same interface, which includes a mechanical
% connection to the engine and a mechanical connection to the driveline.
%
% The CVT subsystem is set up to have a signal interface to the engine and
% vehicle so that unique solver settings can be chosen.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine_signal_intf');open_system('ssc_hydromech_power_split_cvt_engine_signal_intf/CVT/Simscape','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine_signal_intf/CVT/Simscape','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine_signal_intf/CVT/Simscape','force')

%% Vehicle Subsystem
%
% Transmission with four planetary gears, clutches, and a parallel power
% path through a hydrostatic transmission. A hydraulic regenerative braking
% system is also included to improve fuel economy by storing kinetic energy
% as pressure in an accumulator.
%
% <matlab:open_system('ssc_hydromech_power_split_cvt_engine_signal_intf');open_system('ssc_hydromech_power_split_cvt_engine_signal_intf/Vehicle/Simscape','force'); Open Subsystem>

set_param('ssc_hydromech_power_split_cvt_engine_signal_intf/Vehicle/Simscape','LinkStatus','none')
open_system('ssc_hydromech_power_split_cvt_engine_signal_intf/Vehicle/Simscape','force')


%% Simulation Results: Load Cycle, Power Split CVT
%
% Run acceleration and deceleration cycle with the power split CVT.
%

set_param([bdroot '/Engine'],'LabelModeActiveChoice','Simscape')
set_param([bdroot '/Vehicle'],'LabelModeActiveChoice','Simscape')
set_param([bdroot '/CVT'],'LabelModeActiveChoice','Simscape')
set_param([bdroot '/CVT/Simscape/Transmission'],'LabelModeActiveChoice','Power_Split_HM')

sim('ssc_hydromech_power_split_cvt_engine_signal_intf');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt_engine_signal_intf,HMPST.Tire.Rad)
sm_wheel_loader_plot3clutches(simlog_ssc_hydromech_power_split_cvt_engine_signal_intf.CVT.Simscape.Transmission)

%% Simulation Results: Load Cycle, Abstract CVT
%
% Run load cycle with the abstract split CVT.
%

set_param([bdroot '/CVT/Simscape/Transmission'],'LabelModeActiveChoice','Abstract')
sim('ssc_hydromech_power_split_cvt_engine_signal_intf');
ssc_hydromech_power_split_cvt_plot1whlspd(simlog_ssc_hydromech_power_split_cvt_engine_signal_intf,HMPST.Tire.Rad)

%%

close all
bdclose('ssc_hydromech_power_split_cvt_engine_signal_intf');
