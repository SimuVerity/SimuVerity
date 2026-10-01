%  ** Funray brushless direct current motor (Pichler BOOST 40 V2) parameters **

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

% torque constant of the motor (KT=60/(2*pi*KV)), N.m/A
% with KV = 900 RPM/V
param.KT = 60/(2*pi*900);
% motor internal resistance, Ohm (estimated from TMotor MT2216 900Kv)
param.R = 0.135;