function obj = cvtObjFunGearRatios4SpdsSwash(x, tgtVSpdRanges, nHSPumpMotor, ...
    wEng, wHSIn, vWhl2CVTOut, Nr, tgtMaxSwash)
% Objective function for determining gear ratios to achieve speed ranges
% for continuously variable transmission (CVT).
%
%  x                     1x5 vector of gear parameters to be tuned
%     x(1)    Gear ratio (Hydrostatic Output Speed/Planetary 1 Sun Gear Speed)
%     x(2-5)  Number of teeth sun gears planetary 1-4
%
%  tgtVSpdRanges         Target speed ranges for transmission (km/h)
%  nHSPumpMotor          Ratio (Hydrostatic Pump Displacement/
%                               Hydrostatic Motor Displacement)
%  wEng                  Engine speed (rpm)
%  wHSIn                 Pump Nominal Speed (rpm)
%  vWhl2CVTOut           Ratio (Speed CVT Output Shaft (rpm)/
%                               Vehicle Speed (km/h)
%  Nr                    Number of teeth, planetary ring gear (all)
%  tgtMaxSwash           Target max displacement ratio of pump swash plate (0-1)

% Copyright 2023-2025 The MathWorks, Inc.

% Correct number of teeth for 3 planets
x = [x(1) 3*x(2:5)];

% Get ratio wSun-to-wCVT_Out when engine is not spinning  
wPGOut_e0s1    = cvtGetCVTOutputSpeeds(0,1,Nr,x(2:5));

% Use ratio to calculate slope of swash control line
swasCtrlSlopes = wPGOut_e0s1*nHSPumpMotor*(1/x(1))*wHSIn/wEng;

% Convert desired vehicle speed ranges to ratio wEng-to-CVT_Out
ratio_spdRwEngCVTOut = tgtVSpdRanges*vWhl2CVTOut/wEng;

% Get ratio wEng-to-wCVT_Out when swash is 0
% Use to obtain midpoint of each speed segment
ratio_wEng2CVTOutSw0 = cvtGetCVTOutputSpeeds(1,0,Nr,x(2:5));

% Find points of intersection
% Extend from midpoint to target speed along slope
% Find point where speed range segment lines intersect
swas0 = -ratio_wEng2CVTOutSw0(1)/swasCtrlSlopes(1);
cvtr0 = ratio_wEng2CVTOutSw0(1)+swasCtrlSlopes(1)*swas0;
for i = 1:(length(ratio_wEng2CVTOutSw0)-1)
    swas(i) = (ratio_wEng2CVTOutSw0(i+1)-ratio_wEng2CVTOutSw0(i))/...
        (swasCtrlSlopes(i)-swasCtrlSlopes(i+1));
    cvtr(i) = ratio_wEng2CVTOutSw0(i)+swasCtrlSlopes(i)*swas(i);
end
swas5 = (ratio_spdRwEngCVTOut(end)-ratio_wEng2CVTOutSw0(end))/swasCtrlSlopes(end);
cvtr5 = ratio_wEng2CVTOutSw0(end)+swas5*swasCtrlSlopes(end);

% Assemble points forming line into matrix
swasPts = [swas0 swas swas5];
cvtrPts = [cvtr0 cvtr cvtr5];

% Calculate objective function
% Minimize error from target speeds AND target displacement ratio
%obj = sum(sqrt(ratio_spdRwEngCVTOut-cvtrPts).^2)+sum(sqrt((abs(swasPts)-ones(size(swasPts))*tgtMaxSwash).^2));
swasMultiplier = ones(size(swasPts));
swasMultiplier(1:2:end) = -swasMultiplier(1:2:end);
swasPtsTargets = swasMultiplier*tgtMaxSwash;

obj = sum((ratio_spdRwEngCVTOut-cvtrPts).^2) + sum((swasPts-swasPtsTargets).^2);

end