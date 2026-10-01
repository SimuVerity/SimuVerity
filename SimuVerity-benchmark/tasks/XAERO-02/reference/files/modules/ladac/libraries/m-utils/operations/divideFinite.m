function C = divideFinite( A, B ) %#codegen
% divideFinite compute ./ and assure a finite output
%   This function wraps ./ but assures that no Inf or NaN is returned.
%   This is important for use in Simulink to avoid errors in special cases.
%   It is assured that every element be has an absolute value of at least
%   eps.
% 
% Syntax:
%   C = divideFinite( A, B )
% 
% Inputs:
%   A           numerator (NxM array)
%   B           denominator (NxM array)
% 
% Outputs:
%   C           quotient (NxM array)
% 
% See also:
%   eps, rdivide, asinReal, sqrtReal
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if numel(B)>1
    B(abs(B)<eps) = eps;
else
    if abs(B)<eps
        B(:) = eps;
    end
end
C = A ./ B;

end