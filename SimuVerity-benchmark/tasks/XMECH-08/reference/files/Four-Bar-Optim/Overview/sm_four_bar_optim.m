%% Four-Bar Linkage Optimization
%
% This example shows a four-bar linkage modeled in Simscape Multibody that
% is optimized using MATLAB. 
%
% Mechanical designers often wish to design a four-bar linkage that will
% enable an end effector to follow a certain path.  The lengths of the
% links and the position of the end effector influence the trajectory of
% the end effector in a complex kinematic relationship.  Optimization
% algorithms can be used to tune those lengths to achieve the desired
% motion.
%
% In this example, a parameter sweep is performed to see which trajectories
% are possible when varying a subset of the lengths.  Then those lengths
% are tuned using MATLAB optimization algorithms until the resulting
% trajectory is within tolerances of the desired trajectory.
% 
% Copyright 2017-2025 The MathWorks, Inc.


%% Model

open_system('sm_four_bar_optim')

set_param(find_system('sm_four_bar_optim','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% 
% <<sm_four_bar_optim_mechanics_explorer_IMAGE.png>>
bdclose('sm_four_bar_optim')
open_system('sm_four_bar_optim')


%% Simulation Results from Simscape Logging
%%
%
% The plot below shows the path of a pointer on the end of a four-bar
% linkage.  Varying the lengths of the bars will change the trajectory of
% this point.
%


sm_four_bar_optim_plot1path;

%% Results from Parameter Sweep
%%
%
% Four-bar linkages can be grouped into various cases based on the lengths
% of their links.  See http://en.wikipedia.org/wiki/File:Linkage_four_bar_fixed.svg
% The resulting trajectories vary quite widely.  We will limit the scope of
% our problem to a crank-rocker mechanism.  This means:
% 
% # Link a (driven link) is the shortest link     (a <= min(b,c,d))
% # Link b (connecting link) is the longest link  (b >= max(a,c,d))
% # Link a must be able to rotate 180 degrees     (a+b <= c+d)
%

close(h1_sm_four_bar_optim)
sm_four_bar_optim_param_sweep_run;

%% Results from Optimization
%%
%
% Adhering to the same conditions as in the parameter sweep, optimization
% algorithms are used to find the lengths of Bar A and Bar B that permit
% the point on the four-bar linkage to follow the desired trajectory.  Note
% that the trajectories are translated so that the minimum x and y values
% of the trajectories are 0.  This makes visual inspection of the curves
% slightly easier.
%

close(h2_sm_four_bar_optim)
sm_four_bar_optim_match_path;


%%

%clear all
%close all
%bdclose all
