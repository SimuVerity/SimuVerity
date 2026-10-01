function a_x = crossSkew( a )
% crossSkew 3x3 skew-symmetric matrix to represent cross product as matrix
%   multiplication
%   The cross product matrix can replace the cross product
%       c = cross(a,b)
%   by a matrix multiplication (see [1], "Cross product" section)
%       c = a_x * b
% 
% Syntax:
%   a_x = crossSkew(a) 
% 
% Inputs:
%   a                   3d vector (3x1 array)
% 
% Outputs:
%   a_x                 3x3 skew-symmetric matrix (3x3 array)
% 
% Example:
%   a = rand(3,1);
%   b = rand(3,1);
%   c1 = cross(a,b);
%   a_x = crossSkew(a);
%   c2 = a_x*b;
%   is_diff_small = norm(c1-c2,2) < 1e-15
% 
% Literature:
%   [1] https://en.wikipedia.org/wiki/Skew-symmetric_matrix

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% *************************************************************************

a_x = [ ...
        0,      -a(3),	a(2); ...
        a(3),   0,      -a(1); ...
        -a(2),  a(1),   0 ...
    ];

end