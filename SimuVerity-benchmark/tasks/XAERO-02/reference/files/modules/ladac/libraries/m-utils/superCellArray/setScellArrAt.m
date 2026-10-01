function [ superCellArray ] = setScellArrAt( superCellArray, idx, array) %#codegen
%setScellArrAt   assignes an array to the cell of an ScellArray depending
%   on the specified index.
%   An supercell array is a special struct containing two variables: data and
%   dimension. It features the same functionality as a cell array. As cell
%   arrays are not supported for code generation, supercell arrays provide an
%   alternative for cell arrays. The syntax is very similar to the syntax
%   of cell arrays.
%
% Syntax:  [ ScellArray ] = setScellArrAt( ScellArray, index, array )
%
%   The equivalent syntax of a cell array is
% Syntax:  CellArray{ index } = array
%
% Inputs:
%    superCellArray         The supercell in which one cell is supposed to be
%                           assigned. An arbitrary supercell array. Note that supercell
%                           arrays are special structs containing a variable
%                           called data and a variable called dim.
%    idx                    An index which has to be a positive integer and
%                           should not exceed the scell array dimension.  It
%                           indicates the column of the equivalent cell array
%                           which is supposed to be assigned.
%    array                  An array which can either be a N-D matrix, a vector or a
%                           scalar depending on the content of the ScellArray.
%                           This array is supposed to be assigned to the cell of
%                           the supercell array.
%
% Outputs:
%    superCellArray         The new supercell array in which one cell was
%                           assigned.
%
% See also:  cell2scellArr,  getScellArrAt,  scellArrT,  scellDimT

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    if isequal(idx, 1)
        lngth  = prod(superCellArray.dim(1,:));
%         for i = 1:lngth
%             superCellArray.data(i) = array(i);
%         end
        superCellArray.data(1:lngth) = array(:);
    else
        % Get the number of elements for the given matrix
%         lngth = scellArrayDimLngth(superCellArray.dim);
        lngth = prod(superCellArray.dim,2)';
        idxBegin = sum( lngth(1:idx-1) ) + 1;
        idxEnd = idxBegin + lngth(idx) - 1;
        superCellArray.data(idxBegin:idxEnd) = array;
    end
end

