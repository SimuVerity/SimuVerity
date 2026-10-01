function c = crossFast(a,b)
% crossFast faster implementation of cross function
%   This function only works for 3xN array inputs but is much faster
%   compared to cross.
% 
% Syntax:
%   c = crossFast( a, b )
% 
% Inputs:
%   a               first vectors (3xN array)
%   b               second vectors (3xN array)
% 
% Outputs:
%   c               product of inputs (3xN array)
% 
% See also:
%   cross

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************
    
len = max(size(a,2),size(b,2));
c = zeros(3,len);
% Calculate cross product
c(3,:) = a(1,:).*b(2,:)-a(2,:).*b(1,:);
c(1,:) = a(2,:).*b(3,:)-a(3,:).*b(2,:);
c(2,:) = a(3,:).*b(1,:)-a(1,:).*b(3,:);
    
end
