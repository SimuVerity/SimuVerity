function y = acosReal( y ) %#codegen
% acosReal compute the arccos and assure a real output
%   This function wraps acos but assures that no complex number is returned.
%   This is important for use in Simulink to avoid errors in special cases.
%   If the input is less than -1, the output will be 0.
%   If the input is greater than 1, the output will be pi.
% 
% Syntax:
%   y = acosReal( y )
% 
% Inputs:
%   y           input of the acos function (NxM array), dimensionless
% 
% Outputs:
%   y           output of the acos function (NxM array), in rad
% 
% See also:
%   asinReal, sqrtReal
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if numel(y) > 1
    y(y>1)  = 1;
    y(y<-1) = -1;
else
    y = max(-1,min(1,y));
end
y = acos(y);

end