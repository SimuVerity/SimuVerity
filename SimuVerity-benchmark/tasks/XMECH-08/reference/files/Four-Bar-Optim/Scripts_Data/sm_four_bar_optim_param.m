% Parameters for sm_four_bar_optim
% Copyright 2017-2025 The MathWorks, Inc.

% Fixed lengths
c = 0.2;  % m
d = 0.25; % m
h = 0.2;  % m

% Adjustable lengths (default)
a = 0.2;  % m
b = 0.25; % m

% Adjustable lengths (initial values for trajectory optimization)
a_orig = 0.18; % m
b_orig = 0.25; % m

% Adjustable lengths (values for generating desired trajectory)
a_des = 0.12;
b_des = 0.27;

% Load initial and desired trajectories
load sm_four_bar_optim_des
xy_pos_orig_unshifted = xy_pos_orig; 
xy_pos_des_unshifted = xy_pos_des; 

% Parameters for visualizing trajectories
vis_traj_opc = 1;
vis_traj_clr_initial = [1.0 0.4 0.4];
vis_traj_clr_des = [0.6 0.6 0.6];

% Geometric parameters
link_w = 0.02; 
link_t = 0.01;
pin_len = link_t*2.01;
pin_rad = link_w*0.25;

% Color parameters
linkA_clr = [1 1 1]*0.8;
linkB_clr = [0.0 0.4 0.6];
linkC_clr = [1 1 1]*0.8;
pinW_clr = [1 1 1]*0.2;

% Stop Time
% Some configurations may require more than 
% one full revolution of the driving link
StopTime = 10;

% Opacity for reference visualization
opac_orig_design = 0.3;
