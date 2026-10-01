%% Ratchet Pawl Mechanism
%
% This example models a ratchet with a locking pawl.  The arm pushes the
% driving pawl to rotate the ratchet wheel.  The locking pawl holds the
% ratchet wheel in place while the arm reverses direction. Planar contact
% modeling geometry is used to streamline computation.
%
% Copyright 2023-2026 The MathWorks, Inc.


%% Model

open_system('sm_ratchet_pawl')

set_param(find_system('sm_ratchet_pawl','FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Wheel Extrusion Data
%
% This plot shows the extrusion data for the wheel.  This was created in
% MATLAB and was used to generate the data for the contact geometry along
% the edges of the wheel.

Extr_Data_Ratchet_Wheel(r_outer,r_inner,n_teeth,'plot')

%% Pawl Extrusion Data
%
% This plot shows the extrusion data for the pawl.  This was created in
% MATLAB and was used to generate the location for the frame where the
% contact geometry is placed at the tip of the pawl.

Extr_Data_Pawl(pArcRad,pArcDeg,pArcOffset,pArcScaleY,pArcScaleX,ptipRad,'plot');

%% Wheel
%
% The wheel subsystem models the mass and inertia of the wheel, contact
% geometry for the edges of the wheel, and contact forces between the wheel
% and pawls.  A Simscape Bus is used to group the geometry connections for
% each of the line segments representing the teeth edges.

set_param('sm_ratchet_pawl/Wheel','LinkStatus','none');
open_system('sm_ratchet_pawl/Wheel','force');

%% Simulation Results from Simscape Logging
%%
%
% The rotational speeds of the wheel and driver arm are plotted below.  The
% arm and wheel rotate at nearly the same speed as the driver arm rotates
% counterclockwise.  The wheel stays nearly still as the drive arm rotates
% clockwise.  The spikes in the wheel speed are due to the contact forces
% between the pawls and the wheel.
%


sm_ratchet_pawl_plot1speeds;

%%

%clear all
close all
bdclose all
