%% Wheel Loader Driveline with U Joint and CV Joint
% 
% <<sm_wheel_loader_driveline_Overview.png>>
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
% 
% This example tests the driveline with a universal joint and a constant
% velocity joint in a simple test harness
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This example models a driveline with an articulation joint.  The
% articulation joint can be configured to be a universal joint or a
% constant velocity joint
%
% <matlab:open_system('sm_wheel_loader_driveline'); Open Model>

open_system('sm_wheel_loader_driveline')
set_param(bdroot,'LibraryLinkDisplay','none')
set_param(find_system('sm_wheel_loader_driveline','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Simulation Results
%%
%
% The input shaft is rotated at at constant speed.  The bend angle of the
% shaft is increased.  The test with the universal joint shows that the
% speed of the output shaft varies.  The test with the constant velocity
% joint shows that the output speed does not vary.
%

sm_wheel_loader_driveline_plot1shaftspd

%%

close all
bdclose('sm_wheel_loader_driveline');
