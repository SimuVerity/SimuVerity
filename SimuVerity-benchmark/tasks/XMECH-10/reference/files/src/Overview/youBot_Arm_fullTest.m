%% youBot Arm
%
% This examples models a robotic arm and two conveyor belts.  One conveyor
% belts bring blocks to the robot.  The robot grabs the block, flips it
% over and transfers it to another conveyor belt which transports it away
% from the robot.  
%
% This example can be used to determine requirements for electrical and
% mechanical design, detect integration issues, design and test control
% logic, and optimize path planning.
% 
% Copyright 2017-2025 The MathWorks, Inc.


%% Model
% 
% The top level of the model contains hyperlinks that configure the model
% according to the test you wish to perform. The default test is for the
% entire system (robot arm and conveyor belts).  
% 
% Box transfer tests can be run to determine the amount of power required
% for a specific manipulator trajectory.
% 
% Joint tests can be run to determine required motor torque and the forces
% that the bearings will experience.
%

open_system('youBot_Arm')
ann_h = find_system('youBot_Arm','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation');
for i=1:length(ann_h)
    set_param(ann_h(i),'Interpreter','off')
end

%% Simulation Results from Simscape Logging
%%
%
% The plot below shows the current drawn by all motors in the youBot
% robotic arm.
%

youBot_configureTest(bdroot,'Default')
close_system('youBot_Arm/Arm/Actuation/Motion');
close_system('youBot_Arm/Arm/Environment/Gripper Force/Damper/Gripper Force');
close_system('youBot_Arm/Arm/Environment/Gripper Force/Damper');
close_system('youBot_Arm/Arm/Actuation/Motion');
open_system('youBot_Arm')
set_param(bdroot,'StartFcn','tic');
set_param(bdroot,'StopFcn','Elapsed_Sim_Time = toc;');
sim(bdroot,'StopTime','0.01');
sim(bdroot)
youBot_publishTest(1).Config = 'Default';
youBot_publishTest(1).numSteps = length(tout);
youBot_publishTest(1).simTime = Elapsed_Sim_Time;
youBot_Arm_plot1currents;

%%
%
% The plot below shows the 3D trajectory of the box moved by the youBot
% robotic arm.
%


youBot_Arm_plot2boxposition;
%%
%
% The plot below shows the torque or force for each motor in the youBot
% robotic arm.
%


youBot_Arm_plot3torques;
%%
%
% The plot below shows the positions of the joints in the youBot robotic
% arm.
%


youBot_Arm_plot4jointangles;
%%
%
% The plot below shows the constraint forces for each joint in the youBot
% robotic arm.
%


youBot_Arm_plot5constraintforce;

%% Optimization Results With Friction
set_param(bdroot,'StartFcn','');
set_param(bdroot,'StopFcn','');
youBot_optim_test_friction

%% Optimization Results Without Friction
youBot_optim_test_noFriction

%%
%save youBot_publishTest youBot_publishTest
%clear all
close all
bdclose all
