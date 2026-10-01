function maxDim = scellArrMaxDim( dimensionMatrix )
% scellArrMaxDim returns the maximum dimension of all arrays inside the
%   supercell array.
% 
% Inputs:
%   dimensionMatrix         the dimension matrix of a supercell array
% 
% Outputs:
%   maxDim                  the highest dimension of all arrays inside of
%                           the supercell array
% 
% See also:  initScellArr, cell2scellArr, scellArrNumArrays
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

maxDim = size(dimensionMatrix, 2);

end