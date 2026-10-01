function [ lengthArray ] = scellArrayDimLngth( dimensionMatrix )
%UNTITLED Summary of this function goes here
%   Detailed explanation goes here

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    numArrays = scellArrNumArrays( dimensionMatrix );
    lengthArray = zeros(1, numArrays );
    for i = 1:numArrays
        dimSize = dimensionMatrix(i,:);
        lengthArray(i) = prod(dimSize);
    end
    
end
