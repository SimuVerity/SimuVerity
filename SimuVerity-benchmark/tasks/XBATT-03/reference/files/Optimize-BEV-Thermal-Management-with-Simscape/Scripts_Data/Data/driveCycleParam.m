function [cycle] = driveCycleParam(cycleName)
%% Description:
% This script creates a synthetic cycle representing a speed profile over
% time. The cycle has been made synthetic so that the speed does not vary
% too often over the cycle and the model simulates faster. There are three
% possible cycle implemented: 
% - Highway with Charging Stops: Long duration High speed cycle with charging stop. 
% - UDDS:                        Short city cycle, no charging
% - HWFET:                       Short highway cycle, no charging

%% Inputs:
% cycleName: [1x1 string] Contains the name of the desired cycle

%% Output: 
% cycle: [1x1 struct] Contains the speed over time profile. The 1st represents the time and the 2nd the velocity

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% 1) Set cycle based on selection
switch cycleName
    case 'Highway with Charging Stops'
        cycleTime  =  [0, 900, 4800, 5700, 5999, 6000, 7800, 7801, 8100, 9000, 12900, 13800, 14099, 14100, 15900, 15901, 16200, 17100, 21000, 21900];
        cycleSpeed =  [0, 130, 130,  0,    0,    0,    0,    0,    0,    130,  130,   0,     0,     0,     0,     0,     0,     130,   130,   0];
        mode       =  [0, 0,   0,    0,    0,    1,    1,    0,    0,    0,    0,     0,     0,     1,     1,     0,     0,     0,     0,     0];
    
    case 'UDDS'
        cycleTime  = [0, 20, 55, 110, 125, 160, 210, 300,330,345, 360,385,395,405,430,445,465,490,505,510,530,545,555,565,575,590,610,620,640,665,680,690,725, 750,765]';
        cycleSpeed = [0, 0, 48,  48,   0,   0,  80,  80,   0,  0,  56, 56,  0,  0,  0, 0,  55, 55,  0,  0, 40, 40,  0,  0, 26, 26, 45,  0,  0, 40,  0,  0, 45, 45,  0]';
        mode       = zeros(size(cycleTime));

    case 'HWFET'
        cycleTime  = [0,10,100,270,300,310,360,550, 600, 745, 765]';
        cycleSpeed = [0,0,80,80,55,55,95, 95, 80, 80, 0]';
        mode       = zeros(size(cycleTime));
end

%% 2) Assign outputs
% Store the cycle values in the output variable
cycle      = struct;
cycle.t    = [1:1:cycleTime(end)]';                 % Time in sec
cycle.v    = interp1(cycleTime,cycleSpeed,cycle.t); % Speed
cycle.mode = interp1(cycleTime,mode,cycle.t);       % Vehicle is charging:1 otherwise 0
cycle.Name = cycleName;                             % Name of the cycle
end