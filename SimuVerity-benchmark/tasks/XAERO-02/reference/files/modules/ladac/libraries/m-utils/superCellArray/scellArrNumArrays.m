function numArrays = scellArrNumArrays( dimensionMatrix )
% scellArrNumArrays returns the number of arrays inside the
%   supercell array.
% 
% Inputs:
%   dimensionMatrix         the dimension matrix of a supercell array
% 
% Outputs:
%   numArrays               the number of arrays inside the supercell array
% 
% See also:  initScellArr, cell2scellArr, scellArrMaxDim
% 
% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

numArrays = size(dimensionMatrix, 1);

end