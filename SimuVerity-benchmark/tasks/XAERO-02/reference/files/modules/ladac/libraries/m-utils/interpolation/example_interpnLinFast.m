
% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

x1 = 1:10;
x2 = 1:10;
x3 = 1:10;
x4 = 1:10;
V = rand(10,10,10,10);
x1q = rand(1,30)*3;
x2q = rand(1,30)*3;
x3q = rand(1,30)*3;
x4q = rand(1,30)*3;

[X1,X2,X3,X4] = ndgrid( x1,x2,x3,x4 );

tic;
for kk = 1:1000
    Vq = interpn(X1,X2,X3,X4,V,x1q,x2q,x3q,x4q);
%     Vq = interpnLinFast(x1,x2,x3,x4,V,x1q,x2q,x3q,x4q);
end
toc;