%  ** Initial conditions of the rigid body for hover (heading north) **

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% initial angular velocity omega_Kb, in rad/s
IC.omega_Kb = [ 0; 0; 0 ];
% initial Euler angles, in rad
EulerAngles = [ 0; 0; 0 ];
% initial orientation in quaternions q_bg
IC.q_bg = euler2Quat( EulerAngles );
% initial velocity V_Kb, in m/s
IC.V_Kb = [ 0; 0; 0 ];
% initial position s_Kg, in m
IC.s_Kg = [ 0; 0; 0 ];