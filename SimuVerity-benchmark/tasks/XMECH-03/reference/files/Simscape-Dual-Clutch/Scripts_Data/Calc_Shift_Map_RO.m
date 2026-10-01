function [upshift_spd, downshift_spd, pedal_pos] = Calc_Shift_Map_RO(rampconst,mingeardiff)
% CALCULATE SHIFT MAP, RAMP - OFFSET
% CHANGE ENTIRE SHIFT MAP BASED ON TWO PARAMETERS
% Copyright 2011-2025 The MathWorks, Inc.

% CONSTANTS
updowndiff = 3;
gear1pts = [9.95 12.75 15.5 19.5]';
pedalpos = [0.1 0.4 0.5 0.9];

% GENERATE TABLE POINTS
newpts = zeros(length(gear1pts),5);
newpts(:,1) = gear1pts;

for i=2:size(newpts,2)
    newpts(:,i) = newpts(:,1)+(i-1)*mingeardiff+rampconst*(i-1)*pedalpos';
end

% CREATE UPSHIFT AND DOWNSHIFT TABLES
upshift_spd = newpts + (updowndiff/2);
downshift_spd = newpts - (updowndiff/2);
pedal_pos =  pedalpos;

