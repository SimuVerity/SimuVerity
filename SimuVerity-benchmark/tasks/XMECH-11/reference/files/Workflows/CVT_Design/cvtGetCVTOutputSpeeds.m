function wPGOut = cvtGetCVTOutputSpeeds(wEng,wSun,Nr,x)
% This function calculates output shaft speeds and thereby speed ratios
% for each shift range and hydrostatic shaft out speed range set.
%
% Inputs
%   wEng       Speed ring gear, planetary gear 1 (engine speed)
%   wSun       Speed sun gear, planetary gear 1 
%   Nr         Number of teeth, ring gear
%   x          1x4 vector number of teeth for sun gears, all planetaries
%
% Outputs
%   wPGOut     1x4 vector of output shaft speed at end of each speed range
%

% Copyright 2023-2025 The MathWorks, Inc.

% Extract input parameters to variables
nTSun1     = x(1);
nTSun2     = x(2);
nTSun3     = x(3);
nTSun4     = x(4);

% Planetary 1
w_r1 = wEng;  % Assume a speed of 1 to get ratios
w_s1 = wSun;
w_c1 = (nTSun1*w_s1 + Nr*w_r1)/(nTSun1+Nr);

% Planetary 2
w_c2 = w_r1;
w_r2 = w_c1;
w_s2 = ((nTSun2+Nr)*w_c2 - Nr*w_r2)/nTSun2;

% Planetary 3
w_s3 = w_s2;
w_c3 = w_c1;
w_r3 = ((nTSun3+Nr)*w_c3 - nTSun3*w_s3)/Nr;

% Planetary 4 speeds depend on clutch selection (shift range selection)
% c4 is connected to output shaft
% Range 1
w_s4 = w_r3;
w_r4 = 0;
w_c4 = (nTSun4*w_s4 + Nr*w_r4)/(nTSun4+Nr);
wPGOut(1) = w_c4;

% Range 2
w_s4 = w_s3;
w_r4 = 0;
w_c4 = (nTSun4*w_s4 + Nr*w_r4)/(nTSun4+Nr);
wPGOut(2) = w_c4;

% Range 3
w_c4 = w_c3;
wPGOut(3) = w_c4;

% Range 4
w_s4 = w_s3;
w_c4 = w_s4;
wPGOut(4) = w_c4;

end