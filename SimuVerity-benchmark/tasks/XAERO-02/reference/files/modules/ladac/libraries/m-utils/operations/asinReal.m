function y = asinReal( y ) %#codegen
% asinReal compute the arcsin and assure a real output
%   This function wraps asin but assures that no complex number is returned.
%   This is important for use in Simulink to avoid errors in special cases.
%   If the input is less than -1, the output will be -pi/2.
%   If the input is greater than 1, the output will be pi/2.
% 
% Syntax:
%   y = asinReal( y )
% 
% Inputs:
%   y           input of the asin function (NxM array), dimensionless
% 
% Outputs:
%   y           output of the asin function (NxM array), in rad
% 
% See also:
%   acosReal, sqrtReal
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if numel(y)>1
    y(y>1)  = 1;
    y(y<-1) = -1;
else
    y = max(-1,min(1,y));
end
y = asin(y);

end