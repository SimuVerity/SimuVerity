%% Wheel Loader Rear Differential Test Harness
% 
% <<sm_wheel_loader_diff_r_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
%
% This example models a rear differential in a simple test harness.
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a wheel loader rear differential.
%
% <matlab:open_system('sm_wheel_loader_diff_r'); Open Model>

open_system('sm_wheel_loader_diff_r')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param(find_system('sm_wheel_loader_diff_r','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Differential Subsystem
%
% The differential is modeled using four bevel constraints.
%
% <matlab:open_system('sm_wheel_loader_diff_r');open_system('sm_wheel_loader_diff_r/Differential','force'); Open Subsystem>

set_param('sm_wheel_loader_diff_r/Differential','LinkStatus','none')
open_system('sm_wheel_loader_diff_r/Differential','force')

%% Planetary RR Subsystem
%
% The planetary gear is modeled using six common gear constraints.
%
% <matlab:open_system('sm_wheel_loader_diff_r');open_system('sm_wheel_loader_diff_r/Planetary%20RR','force'); Open Subsystem>

set_param('sm_wheel_loader_diff_r/Planetary RR','LinkStatus','none')
open_system('sm_wheel_loader_diff_r/Planetary RR','force')

%% Simulation Results: Locked Right Wheel
%%
%
% Run test with locked right wheel. 
%

sim('sm_wheel_loader_diff_r');
sm_wheel_loader_diff_r_plot1shaftspd

%%

close all
bdclose('sm_wheel_loader_diff_r');
