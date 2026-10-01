%% Wheel Loader Planetary Gear Test Harness
% 
% <<sm_wheel_loader_planetary_gear_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
% 
% This example tests the planetary gear wheel hub in a simple test harness.
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models an in-wheel planetary gear
%
% <matlab:open_system('sm_wheel_loader_planetary_gear'); Open Model>

open_system('sm_wheel_loader_planetary_gear')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param(find_system('sm_wheel_loader_planetary_gear','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Planetary Gear Subsystem
%
% The differential is modeled using four bevel constraints.
%
% <matlab:open_system('sm_wheel_loader_planetary_gear');open_system('sm_wheel_loader_planetary_gear/Planetary%20L','force'); Open Subsystem>

set_param('sm_wheel_loader_planetary_gear/Planetary L','LinkStatus','none')
open_system('sm_wheel_loader_planetary_gear/Planetary L','force')

%% Simulation Results
%%
%
% Run test applying torque to ring gear, viscous damping on carrier
%

sim('sm_wheel_loader_planetary_gear');
sm_wheel_loader_planetary_gear_plot1shaftspd

%%

close all
bdclose('sm_wheel_loader_planetary_gear');
