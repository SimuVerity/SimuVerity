%  ** fuselage aerodynamics parameters (Funray) **

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% yawing moment coefficient slope, 1/rad
dCn_dbeta = -0.25;
% lift curve slope, 1/rad
dCL_dalpha0 = 0.15;
% maximum lateral force coefficient, -
C_Qmax = 0.45;
% lateral force slope, 1/rad
dCQ_dbeta0 = -0.2;
% pitching moment coefficient slope, 1/rad
dCm_dalpha = 0.15;
% maximum lift coefficient, -
C_Lmax = 0.3;
% maximum drag coefficient (alpha=45deg), -
C_Dmax = 0.7;
% minimum drag coefficient (alpha=0), -
C_Dmin = 0.07;