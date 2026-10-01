function [ cellArr ] = scellArr2cell( superCellArray ) %#codegen
%UNTITLED5 Summary of this function goes here
%   Detailed explanation goes here

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    % Get the number of elements for the given matrix
    lngth = scellArrayDimLngth( superCellArray.dim );
    % Split the data in subarrays containing the matrix data
    cellArr = mat2cell( superCellArray.data, 1, lngth' );
    % Also convert the dimension matrix into a cell array
    numDims = scellArrMaxDim( superCellArray.dim );
    numArrays = length(lngth);
    dimCellArr = mat2cell( reshape(superCellArray.dim',1,[]), 1, ...
        repmat(numDims,numArrays,1) );
    % Reshape each 1XN cell array to the orginally dimensions (function
    % call like, wtf?)
    cellArr = arrayfun(@(dimx, x) reshape(x{1}, dimx{:}),...
        dimCellArr, cellArr, ....
        'UniformOutput', false);
end
