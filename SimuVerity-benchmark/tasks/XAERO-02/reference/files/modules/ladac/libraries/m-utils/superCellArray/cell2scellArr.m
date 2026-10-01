function [ superCellArray ] = cell2scellArr( cellArr ) %#codegen
%cell2scellArr   converts a cell array to a supercell array.
%   An supercell array is a special struct containing two variables: data and
%   dimension. It features the same functionality as a cell array. As cell
%   arrays are not supported for code generation, supercell arrays provide an
%   alternative for cell arrays. The syntax is very similar to the syntax of
%   cell arrays.
%
% Syntax:  [ ScellArray ] = cell2scellArr( cellArray )
%
% Inputs:
%    cellArray            : An arbitrary cell array.
%
% Outputs:
%    ScellArray           : The supercell array corresponding to the given input
%                           cell array.
%
% See also:  setScellArrAt,  getScellArrAt,  scellArr2cell,  scellArrT,  scellDimT

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    % Get the size of each cell array
    cellSize = cellfun(@size, cellArr, 'uni', false);
    cellLength = length(cellSize);
    numelCellSize = cellfun(@numel, cellSize);
    maxNumelCellSize = max(numelCellSize);
    % init all dims to have 1 element
    dim = ones(cellLength, maxNumelCellSize);
    % Save the different dimensions in an array
    for i = 1:cellLength
        dim(i, 1:numelCellSize(i)) = cellSize{i};
    end
    matrixSize = sum(cellfun(@numel, cellArr) );
    % Create the superCellArray dataformat and write the dimension into the
    % struct.
    superCellArray = struct('data', zeros(1, matrixSize),...
        'dim', dim);
    % Reshape all cell arrays to a 1xN vector as cell array
    % NxM to 1xM*N as cell arrays
    cellArr = cellfun(@(x) reshape(x, [1, numel(x)]), cellArr,...
        'UniformOutput', false);
    % Cat the fun to one big array
    superCellArray.data = cat(2,cellArr{:});
end
