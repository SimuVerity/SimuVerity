%% Open Differential Testrig
%
% This example models an open differential using multiple bevel gears.
% This gearset enables the axles to rotate at different speeds even though
% they are connected to the same input shaft
%
% Copyright 2017-2025 The MathWorks, Inc.



%% Model

open_system('sm_open_differential_testrig')

set_param(find_system('sm_open_differential_testrig','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% 
% <<sm_open_differential_testrig_mechanics_explorer_IMAGE.png>>

%% Open Differential Subsystem
%
% <matlab:open_system('sm_open_differential_testrig');open_system('sm_open_differential_testrig/Open%20Differential','force'); Open Subsystem>

set_param('sm_open_differential_testrig/Open Differential','LinkStatus','none')
open_system('sm_open_differential_testrig/Open Differential','force')

%% Open Differential Subsystem
%
% The Bevel Gear Constraint requires that the rest of the mechanism hold
% the two frames to which it is connected in alignment.  This subsystem has
% the necessary constraints and parameterized Rigid Transforms to hold the
% frames in the right position and orientation.
%
% <matlab:open_system('sm_open_differential_testrig');open_system('sm_open_differential_testrig/Open%20Differential/Differential%20Pinion%20to%20Axles/Constraints','force'); Open Subsystem>

set_param('sm_open_differential_testrig/Open Differential/Differential Pinion to Axles/Constraints','LinkStatus','none')
open_system('sm_open_differential_testrig/Open Differential/Differential Pinion to Axles/Constraints','force')
close_system('sm_open_differential_testrig/Open Differential/Differential Pinion to Axles')

%%
close_system('sm_open_differential_testrig/Open Differential/Differential Pinion to Axles')

%% Simulation Results from Simscape Logging
%%
%
% The plot below shows the input shaft and axle shaft speeds. A step change
% to the load on one of the axles causes the two axles to spin at different
% speeds.
%

sm_open_differential_testrig_plot1speed;

%%

%clear all
close all
bdclose all
