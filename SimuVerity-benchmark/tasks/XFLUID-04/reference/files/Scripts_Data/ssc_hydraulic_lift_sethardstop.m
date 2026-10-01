function ssc_hydraulic_lift_sethardstop(paramset)
% Copyright 2012-2025 The MathWorks, Inc.

if strcmpi(paramset,'initial')
    evalin('base','actuator_hs_k = 1e9;')
    evalin('base','actuator_hs_b = 0.15;')
else
    evalin('base','actuator_hs_k = 1e6;')
    evalin('base','actuator_hs_b = 1500;')
end
