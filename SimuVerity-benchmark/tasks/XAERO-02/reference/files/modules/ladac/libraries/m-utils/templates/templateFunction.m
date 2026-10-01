function c = templateFunction( a, b )
% TEMPLATEFUNCTION product of a number and an array
%   Some additional explanation.
% 
% Syntax:
%   c = TEMPLATEFUNCTION( a ) multiplies a with itself
%   c = TEMPLATEFUNCTION( a, b ) multiplied a and b
% 
% Inputs:
%   a               first number (scalar), dimensionless
%   b               first number (NxM array), dimensionless
% 
% Outputs:
%   c               product of inputs (NxM array), dimensionless
% 
% Example(s): (optional)
%   a = 1;
%   b = 2;
%   c = TEMPLATEFUNCTION(a,b)
% 
% See also:
%   OTHERFUNCTION, ANOTHERFUNCTION
% 
% Literature: (optional)
%   [1] Schlichting, H., & Truckenbrodt, E. (2001). Aerodynamik des
%       Flugzeuges. Zweiter Band: Aerodynamik des Tragfluegels (Teil II),
%       des Rumpfes, der Fluegel-Rumpf-Anordnung und der Leitwerke. 3.
%       Auflage. Springer-Verlag Berlin Heidelberg.

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2019-2022 First Author
%   Copyright (C) 2022 Second Author
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if nargin < 2
    c = a * a;
else
    c = a * b;
end
    
end