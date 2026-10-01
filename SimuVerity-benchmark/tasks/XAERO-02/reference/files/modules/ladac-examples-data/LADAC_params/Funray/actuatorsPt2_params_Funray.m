%  ** second order actuator parameters (Funray with KST DS215MG HV V8) **

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% natural frequency, rad/s
param.naturalFrequency = 200;
% damping ratio, 1
param.dampingRatio = 0.866;
% maximum deflection, rad
param.deflectionMax = deg2rad(25);
% minimum deflection, rad
param.deflectionMin = deg2rad(-25);
% maximum deflection rate, rad/2
param.deflectionRateMax = deg2rad(60/0.08);
% transport delay, s
param.delay = 0.0075;