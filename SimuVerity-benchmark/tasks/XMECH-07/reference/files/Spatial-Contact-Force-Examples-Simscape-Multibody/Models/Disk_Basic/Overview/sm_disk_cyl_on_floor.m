%% Multibody Disk Contact, Cylinder on Floor
%
% This example models a cylinder bouncing on a floor using different
% contact methods. It compares contact between two solids, one solid and a
% point cloud, and one solid with two disks.  The comparison looks at the
% number of steps during the simulation.  It is seen that the
% solid-to-solid contact requires more steps as the point of contact moves
% along the contact line between the cylinder and the floor.  Both the
% point cloud and the disk contact proxies show the cylinder resting on the
% floor with no oscillations about the lateral axis.
%
% Copyright 2022-2026 The MathWorks, Inc.


%% Model

open_system('sm_disk_cyl_on_floor')

set_param(find_system('sm_disk_cyl_on_floor','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Simulation Results from Simscape Logging
%%
%
% The plot below compares the rotational speed of the lateral axis for each
% contact modeling method.  The simulations are run separately to obtain an
% independent measure of the number of steps required to complete the
% simulation, which is shown in the lower plot.  It is clear that as the
% contact point for solid-to-solid contact moves along the contact line,
% the cylinder rotates very slightly about the lateral axis which requires
% additional simulation steps.
%


sm_disk_cyl_on_floor_test_methods;

%%
%clear all
close all
bdclose all
