function dimOrder = scellArrCheckT( dim, dimOrderIn )
% scellArrCheckT simplifies the permutation order argument in case a
%   supercell array is transposed/permuted.

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    maxDim = scellArrMaxDim(dim);
    % If the array is 2-D, the transpose is unique. In case of higher
    % dimensions, a permutation order must be specified.
    if maxDim > 2
        if ~isempty(dimOrderIn)
            dimOrder = dimOrderIn{1};
        else
            error('Specify permutation order of dimensions.')
        end
    else
        dimOrder = [2,1];
    end
    
end