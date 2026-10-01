function [ superCellArray ] = scellArrT( superCellArray, varargin ) %#codegen
%scellArrT   Transposes/permutes the given supercell array
%   This function transposes/permutes all arrays inside the supercell
%   array. In case any array inside the supercell has a dimension greater
%   than 2, the transpose is not unique and a permutation order must be
%   specified.
%
% Syntax:
%   [ superCellArray ] = scellArrT( superCellArray )
% 	[ superCellArray ] = scellArrT( superCellArray, dimOrder )
%
% Inputs:
% 	superCellArray      Supercell array that should be transposed.
% 	dimOrder            1xN vector, where N is the dimension of the array
%                       with the highest dimension inside the supercell
%                       array (see permute).
%
% Outputs:
%    superCellArray     Supercell array , where every array is
%                       transposed/permuted.
%
% Examples:
%   cellArray = { rand(1,2), rand(2,1) };
%   myScellArray = cell2scellArr( cellArray );
%  	myScellArrayT = scellArrT( myScellArray )
%       Transposes all arrays inside of the supercell array if there are
%       only 2-D arrays.
% 
%   cellArray = { rand(1,2,3), rand(3,2,1) };
%   myScellArray = cell2scellArr( cellArray );
%   myScellArrayT = scellArrT( myScellArray, [2,3,1] )
%       Permutes all arrays inside of the supercell array depending on the
%       specified dimension order.
%
% See also:  permute, scellArrMaxDim, scellDimT, initScellArr

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************
    
    % Check sanity and get permutation order
    dimOrder = scellArrCheckT( superCellArray.dim, varargin );

    % Get the transposed dimensions
    dimT = scellDimT( superCellArray.dim, dimOrder );
    
    numArrays = scellArrNumArrays(superCellArray.dim);
    for i=1:numArrays
        % Get array
        arrayAtCell = getScellArrAt( superCellArray, i );
        % Transpose/permute array
        arrayAtCellT = permute( arrayAtCell, dimOrder );
        % Set the current transposed dimension
        superCellArray.dim(i,:) = dimT(i,:);
        % Save the transposed array back to the supercell array
        superCellArray = setScellArrAt( superCellArray, i, arrayAtCellT );
    end

end

