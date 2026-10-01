%% Dual Clutch Transmission
%
% This example shows a vehicle with a five-speed automatic dual-clutch
% transmission. The transmission controller converts the pedal deflection
% into a demanded torque. This demanded torque is then passed to the engine
% management. The pedal deflection and the vehicle speed are also used by
% the transmission controller to determine when the gear shifts should
% occur. Gear shifts are implemented via the two clutches, one clutch
% pressure being ramped up as the other clutch pressure is ramped down.
% Gear pre-selection via dog clutches ensures that the correct gear is
% fully selected before the on-going clutch is enabled.
% 
% This model can be configured for fixed-step simulation, making it
% suitable for hardware-in-the-loop testing.
% Copyright 2014-2025 The MathWorks, Inc.


%% Model

open_system('Dual_Clutch_Trans')

set_param(find_system('Dual_Clutch_Trans','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Abstract Transmission Subsystem
%
% <matlab:open_system('Dual_Clutch_Trans');open_system('Dual_Clutch_Trans/Dual%20Clutch%20Transmission/Abstracted','force'); Open Subsystem>

set_param('Dual_Clutch_Trans/Dual Clutch Transmission','LabelModeActiveChoice','Abstracted');
set_param('Dual_Clutch_Trans/Dual Clutch Transmission/Abstracted','LinkStatus','none')
open_system('Dual_Clutch_Trans/Dual Clutch Transmission/Abstracted','force')

%% Detailed Transmission Subsystem
%
% <matlab:open_system('Dual_Clutch_Trans');open_system('Dual_Clutch_Trans/Dual%20Clutch%20Transmission/Detailed','force'); Open Subsystem>

set_param('Dual_Clutch_Trans/Dual Clutch Transmission','LabelModeActiveChoice','Detailed');
set_param('Dual_Clutch_Trans/Dual Clutch Transmission/Detailed','LinkStatus','none')
open_system('Dual_Clutch_Trans/Dual Clutch Transmission/Detailed','force')

%% Full Vehicle Subsystem
%
% <matlab:open_system('Dual_Clutch_Trans');open_system('Dual_Clutch_Trans/Vehicle%20Dynamics/Full','force'); Open Subsystem>

set_param('Dual_Clutch_Trans/Vehicle Dynamics/','LabelModeActiveChoice','Full');
set_param('Dual_Clutch_Trans/Vehicle Dynamics/Full','LinkStatus','none')
open_system('Dual_Clutch_Trans/Vehicle Dynamics/Full','force')

%% Shifting Logic Subsystem
%
% <matlab:open_system('Dual_Clutch_Trans');open_system('Dual_Clutch_Trans/Transmission%20Controller/Shift%20state/Chart','force'); Open Subsystem>

set_param('Dual_Clutch_Trans/Transmission Controller/Shift state/Chart','LinkStatus','none')
open_system('Dual_Clutch_Trans/Transmission Controller/Shift state/Chart','force')

%% Fuel Economy Subsystem
%
% <matlab:open_system('Dual_Clutch_Trans');open_system('Dual_Clutch_Trans/Fuel%20Economy','force'); Open Subsystem>

set_param('Dual_Clutch_Trans/Fuel Economy','LinkStatus','none')
open_system('Dual_Clutch_Trans/Fuel Economy','force')

%% Simulation Results from Simscape Logging
%%
%
% The plots below show the engine and vehicle speed as it accelerates
% through the first three gears in the dual-clutch transmission.  The
% half-gear states indicate gear shifts are taking place by engaging and
% disengaging the dual clutches.
bdclose('Dual_Clutch_Trans');

load_system('Dual_Clutch_Trans');
Drive_Cycle_Num = 7;
set_param('Dual_Clutch_Trans/Dual Clutch Transmission','LabelModeActiveChoice','Detailed');
set_param('Dual_Clutch_Trans/Vehicle Dynamics','LabelModeActiveChoice','Full')
sim('Dual_Clutch_Trans');
Dual_Clutch_Trans_plot1speed;

%% Abstract Transmission, Simple Vehicle

Drive_Cycle_Num = 7;
set_param('Dual_Clutch_Trans/Dual Clutch Transmission','LabelModeActiveChoice','Abstracted');
set_param('Dual_Clutch_Trans/Vehicle Dynamics','LabelModeActiveChoice','Simple')
sim('Dual_Clutch_Trans');
Dual_Clutch_Trans_plot1speed;


%%

%clear all
close all
bdclose all
