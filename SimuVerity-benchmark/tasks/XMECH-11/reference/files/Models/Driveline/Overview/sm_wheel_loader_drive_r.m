%% Wheel Loader Rear Axle Test Harness
% 
% <<sm_wheel_loader_drive_r_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
% 
% This example models a rear axle in a simple test harness.
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a wheel loader rear axle.
%
% <matlab:open_system('sm_wheel_loader_drive_r'); Open Model>

open_system('sm_wheel_loader_drive_r')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param(find_system('sm_wheel_loader_drive_r','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Differential Subsystem
%
% The differential is modeled using four bevel gear constraints.
%
% <matlab:open_system('sm_wheel_loader_drive_r');open_system('sm_wheel_loader_drive_r/Differential','force'); Open Subsystem>

set_param('sm_wheel_loader_drive_r/Differential','LinkStatus','none')
open_system('sm_wheel_loader_drive_r/Differential','force')

%% Planetary RR Subsystem
%
% The planetary gear is modeled using six common gear constraints.
%
% <matlab:open_system('sm_wheel_loader_drive_r');open_system('sm_wheel_loader_drive_r/Planetary%20FR','force'); Open Subsystem>

set_param('sm_wheel_loader_drive_r/Planetary RR','LinkStatus','none')
open_system('sm_wheel_loader_drive_r/Planetary RR','force')


%% Simulation Results: Locked Left Wheel
%%
%
% Run test with locked left wheel. 
%

sim('sm_wheel_loader_drive_r');
sm_wheel_loader_drive_r_plot1shaftspd

%%

close all
bdclose('sm_wheel_loader_drive_r');
