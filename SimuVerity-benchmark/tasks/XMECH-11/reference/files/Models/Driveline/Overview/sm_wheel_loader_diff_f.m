%% Wheel Loader Front Differential Test Harness
% 
% <<sm_wheel_loader_diff_f_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
%
% This example models a front differential in a simple test harness.
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a wheel loader front differential.
%
% <matlab:open_system('sm_wheel_loader_diff_f'); Open Model>

open_system('sm_wheel_loader_diff_f')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param(find_system('sm_wheel_loader_diff_f','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Differential Subsystem
%
% The differential is modeled using four bevel constraints.
%
% <matlab:open_system('sm_wheel_loader_diff_f');open_system('sm_wheel_loader_diff_f/Differential','force'); Open Subsystem>

set_param('sm_wheel_loader_diff_f/Differential','LinkStatus','none')
open_system('sm_wheel_loader_diff_f/Differential','force')

%% Simulation Results: Locked Right Wheel
%%
%
% Run test with locked right wheel. 
%

sim('sm_wheel_loader_diff_f');
sm_wheel_loader_diff_f_plot1shaftspd

%%

close all
bdclose('sm_wheel_loader_diff_f');
