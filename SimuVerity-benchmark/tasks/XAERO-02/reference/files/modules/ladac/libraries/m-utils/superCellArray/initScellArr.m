function [ superCellArray ] = initScellArr( dimensionMatrix ) %#codegen
%INITSCELLARR   This function initializes supercell arrays
%   This function can be used to initialize a supercell array. The
%   initialization can be done with different function argument types like
%   matrices, vectors and dimension structs.
%
% Syntax:  [ superCellArray ] = initScellArr( dimension )
%
% Inputs:
%    dimension:         The function argument can be an matrix or a vector.
%                       Each row of the matrix/vector corresponds to one
%                       array inside the supercell array. The row vectors
%                       are equal to the size of the array.
%
% Outputs:
%    superCellArray:   The initialized supercell arrrays with the
%                      corresponding sizes containing zeros.
%
% Example:
%    aScellArr = initScellArr( [ 1, 2; 3, 4 ] )
%       Creates a supercell array with two matrices and the dimension 1x2
%       and 3x4.
%    bScellArr = initScellArr( [ 1; 2; 3; 4 ] )
%       Creates a supercell array with four vectors and the dimension 1x1, 2x1,
%       3x1 and 4x1, so all column vectors.
%    cScellArr = initScellArr( [ 1, 2, 3; 4, 5, 6 ] )
%       Creates a supercell array two 3-D matrix and the dimension 1x2x3 and
%       4x5x6.
%    dScellArr = initScellArr( [ 1, 2, 3, 4; 5, 6, 7, 1; 8, 9, 1, 1 ] )
%       Creates a supercell array three different dimension matrices and the
%       dimension 1x2x3x4, 5x6x7 and 8x9 
%       (a 5x6x7x1 array is treated as 5x6x7 array by Matlab).
%    eScellArr = initScellArr( dScellArr.dim )
%       Initializes a supercell array dScellArr with the same dimension as
%       cScellArr.
%
% See also:  getScellArrAt,  setScellArrAt,  scellArr2cell, cell2scellArr

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2021 Alexander Kuzolap
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    % Get the number of elements for the given matrix
    matrixSize = 0;
    numArrays = scellArrNumArrays(dimensionMatrix);
    for i = 1:numArrays
        matrixSize = matrixSize + ...
            prod(dimensionMatrix(i,:));
    end
    % assure that dimension equals at least 2 (else functions like size()
    % do not work)
    if scellArrMaxDim(dimensionMatrix) == 1
        dimensionMatrixOut = [ dimensionMatrix, ones(numArrays,1) ];
    else
        dimensionMatrixOut = dimensionMatrix;
    end

    superCellArray = struct('data', zeros(1, matrixSize),...
        'dim', dimensionMatrixOut);
end
