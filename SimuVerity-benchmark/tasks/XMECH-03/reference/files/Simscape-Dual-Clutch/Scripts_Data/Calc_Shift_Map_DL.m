function [upshift_spd, downshift_spd, pedal_pos] = Calc_Shift_Map_DL(deltas, pedal_pos)
% CALCULATE SHIFT MAP, DELTA
% CALCULATES ENTIRE SHIFT MAP BASED ON DELTAS BETWEEN GEARS AND ALONG PEDAL POSITION
% Copyright 2011-2025 The MathWorks, Inc.

% CONSTANTS
updowndiff = 3;  % MINIMUM SEPARATION BETWEEN UPSHIFT AND DOWNSHIFT

mappts = zeros(size(deltas));

% FIRST ROW OF DELTAS SEPARATES SHIFT LINES
mappts(1,1) = deltas(1,1);
for j=2:size(deltas,2)
    mappts(1,j)=mappts(1,j-1)+deltas(1,j);
end

% SECOND TO FINAL ROW OF DELTAS SEPARATE
% SHIFT POINTS AS PEDAL POSITION VARIES
for j=1:size(deltas,2)
    for i = 2:size(deltas,1)
        mappts(i,j) = mappts(i-1,j)+deltas(i,j);
    end
end

% CREATE UPSHIFT AND DOWNSHIFT TABLES
% SEPARATED BY updowndiff
upshift_spd = mappts + (updowndiff/2);
downshift_spd = mappts - (updowndiff/2);


