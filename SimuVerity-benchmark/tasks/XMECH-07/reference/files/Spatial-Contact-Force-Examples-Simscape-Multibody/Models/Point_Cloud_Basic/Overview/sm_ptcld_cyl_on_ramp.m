%% Multibody Point Cloud Contact Cylinder on Ramp
%
% This example models a cylinder rolling down a ramp using two contact
% methods.  It compares contact between two solids with contact between a
% point cloud and a solid. The number of points in the point cloud can be
% varied.  To maintain the same penetration, the stiffness parameter is
% scaled with the number of points.  Fewer points, however, results in more
% speed variation as the cylinder rolls down the ramp.
%
% Copyright 2022-2026 The MathWorks, Inc.


%% Model

open_system('sm_ptcld_cyl_on_ramp')

set_param(find_system('sm_ptcld_cyl_on_ramp','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Simulation Results from Simscape Logging
%%
%
% The plot below compares the vertical and horizontal speed of the
% cylinders as they roll down the ramp.  The penetration into the ramp is
% quite similar for the two solids, but the rotational speeds differ.
%

[cyl, ptcld] = sm_ptcld_cyl_on_ramp_param(100,'plot');

%% 
%
% <<sm_ptcld_cyl_on_ramp_anim_fewPts.png>>

%%

sim('sm_ptcld_cyl_on_ramp')
sm_ptcld_cyl_on_ramp_plot1vel;

%% Simulation Results from Simscape Logging: More Points 
%%
%
% The plot below compares the vertical and horizontal speed of the
% cylinders as they roll down the ramp.  The penetration into the ramp is
% quite similar for the two solids, and with an increased number of points
% the rotational speeds of the cylinder with the point cloud has less
% variation.
%

[cyl, ptcld] = sm_ptcld_cyl_on_ramp_param(500,'plot');

%% 
%
% <<sm_ptcld_cyl_on_ramp_anim_manyPts.png>>

%%

sim('sm_ptcld_cyl_on_ramp')
sm_ptcld_cyl_on_ramp_plot1vel;

%%
%clear all
close all
bdclose all
