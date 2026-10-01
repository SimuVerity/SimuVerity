function [ dimT ] = scellDimT( dim, varargin ) %#codegen
%scellDimT   Transposes/permutes the given supercell array dimension matrix
%   This function re-orders the given supercell array dimension matrix so
%   that it is compatible to the transposed/permuted arrays inside the
%   supercell array.
%
% Syntax: 
%   [ dimT ] = scellDimT( scellArr.dim )
%   [ dimT ] = scellDimT( scellArr.dim, dimOrder )
%
% Inputs:
%    dim        Supercell array dim field that is a NxM matrix.
%    dimOrder   1xN array specifying the permutation order (see permute).
%
% Outputs:
%    dimT       Supercell array dim matrix with re-ordered columns.
%
% Examples:
%   dim = [ 1, 2; 3, 4 ];
%  	[ dimT ] = scellDimT( dim );
%       Re-orders the columns of the dimension matrix if all arrays inside
%       the supercell array are 2-D.
%   dim = [ 1, 2, 3; 4, 5, 6 ];
%   [ dimT ] = scellDimT( dim, [2,1,3] );
%       Re-orders the columns of the dimension matrix if any array dimension
%       inside the supercell array is greater than 2 according to the
%       specified dimension order.
%
% See also:  permute, scellArrT, initScellArr

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    % Check sanity and get permutation
    dimOrder = scellArrCheckT( dim, varargin );
    
    dimT = dim;
    numArrays = scellArrNumArrays(dim);
    for i=1:numArrays
        dimT(i,:) = dim(i,dimOrder);
    end
end

