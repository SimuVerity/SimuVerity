function y = sqrtReal( y ) %#codegen
% sqrtReal compute the square root and avoid complex numbers
%   This function wraps sqrt but assures that no complex number is returned.
%   This is important for use in Simulink to avoid errors in special cases.
%   If the input is negative, the output will be zero.
% 
% Syntax:
%   y = sqrtReal( y )
% 
% Inputs:
%   y           input of the sqrt function (NxM array)
% 
% Outputs:
%   y           output of the sqrt function (NxM array)
% 
% See also:
%   acosReal, asinReal
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if numel(y) > 1
    y(y<0)  = 0;
else
    y = max(0,y);
end
y = sqrt(y);

end