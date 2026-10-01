function coordMatrix = grid2Coordinates( varargin ) %#codegen
% grid2Coordinates computes a matrix of all permutation of given vectors.
%   This can be interpreted as concentrated matrix of all points of vectors
%   of gridded maps.
% 
% Inputs:
%   varargin            This should be at least one vector of arbitrary
%                       length but usually there are multiple vectors which
%                       can have different lengths.
% 
% Outputs:
%   coordMatrix         This is the matrix that contains all permutations
%                       of the elements inside the input vectors.
%                       If the inputs are three vectors with m, n, p
%                       elements, the dimension of the coordMatrix is m*n*p
%                       times 3.
% 
% Example:
%   vector1 = [1;2;3;4];
%   vector2 = [4;5;6];
%   coordMatrix = grid2Coordinates( vector1, vector2 )
%   map_data = rand(4,3);
%   [X,Y] = ndgrid( vector1, vector2 );
%   surf( X, Y, map_data )
%   hold on
%   plot3( coordMatrix(:,1), coordMatrix(:,2), map_data(:), 'o' )
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

numVars = length(varargin);
dimVector = zeros(1,numVars);
for i = 1:numVars
    dimVector(i) = length(varargin{i});
end
numDataPoints = prod(dimVector);
coordMatrix = zeros( numDataPoints, numVars );

dimVectorExt = [1,dimVector];
for i = 1:numVars
    numRep1 = prod(dimVectorExt(1:i));
    numRep2 = prod(dimVector(i+1:end));
    coordMatrix(:,i) = repmat( repelem(varargin{i}(:), numRep1, 1 ), numRep2, 1 );
end

end