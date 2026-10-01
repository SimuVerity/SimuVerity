%% Wheel Loader Front Axle Test Harness
% 
% <<sm_wheel_loader_drive_f_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
% 
% This example models a front axle in a simple test harness.
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a wheel loader front axle.
%
% <matlab:open_system('sm_wheel_loader_drive_f'); Open Model>

open_system('sm_wheel_loader_drive_f')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param(find_system('sm_wheel_loader_drive_f','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Differential Subsystem
%
% The differential is modeled using four bevel gear constraints.
%
% <matlab:open_system('sm_wheel_loader_drive_f');open_system('sm_wheel_loader_drive_f/Differential','force'); Open Subsystem>

set_param('sm_wheel_loader_drive_f/Differential','LinkStatus','none')
open_system('sm_wheel_loader_drive_f/Differential','force')

%% Planetary FR Subsystem
%
% The planetary gear is modeled using six common gear constraints.
%
% <matlab:open_system('sm_wheel_loader_drive_f');open_system('sm_wheel_loader_drive_f/Planetary%20FR','force'); Open Subsystem>

set_param('sm_wheel_loader_drive_f/Planetary FR','LinkStatus','none')
open_system('sm_wheel_loader_drive_f/Planetary FR','force')


%% Simulation Results: Locked Right Wheel
%%
%
% Run test with locked left wheel. 
%

sim('sm_wheel_loader_drive_f');
sm_wheel_loader_drive_f_plot1shaftspd

%%

close all
bdclose('sm_wheel_loader_drive_f');
