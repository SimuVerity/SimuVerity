function [ array, superCellArray ] = getScellArrAt( superCellArray, idx ) %#codegen
%getScellArrAt   returns the content of an supercell array for a given index.
%   A supercell array is a special struct containing two variables: data and
%   dimension. It features the same functionality as a cell array. As cell
%   arrays are not supported for code generation, supercell arrays provide an
%   alternative for cell arrays. The syntax is very similar to the syntax of
%   cell arrays.
%
% Syntax:  [ array ] = getScellArrAt( ScellArray, index )
%
%   The equivalent syntax of a cell array is
% Syntax:  [ array ] = cellArray{ index }
%
% Inputs:
%    superCellArray         An arbitrary supercell array. Note that supercell arrays
%                           are special structs containing a variable called
%                           data and a variable called dim.  The path through of
%                           the superCellArray variable is required for Matlab
%                           Code generation.
%    idx                    An index which has to be a positive integer and
%                           should not exceed the scell array dimension.
%
% Outputs:
%    array                  An array which can either be a (N-D) matrix, a vector
%                           or a scalar depending on the content of the
%                           supercell array.
%
% See also:  setScellArrAt,  cell2scellArr, scellArr2cell, scellArrT

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    if isequal(idx, 1)
        lngth  = prod(superCellArray.dim(1,:));
        arrayVec = superCellArray.data(1:lngth);
    else
        % Get the number of elements for the given matrix
%         lngth = scellArrayDimLngth(superCellArray.dim);
        lngth = prod(superCellArray.dim,2)';
        idxBegin = sum( lngth(1:idx-1) ) + 1;
        idxEnd = idxBegin + lngth(idx) - 1;
        arrayVec = superCellArray.data(idxBegin:idxEnd);
    end
    array = reshape(arrayVec, superCellArray.dim(idx,:));
end
