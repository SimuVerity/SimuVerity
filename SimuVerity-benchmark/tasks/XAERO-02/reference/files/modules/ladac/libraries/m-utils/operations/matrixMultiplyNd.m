function Z = matrixMultiplyNd(X,Y) %#codegen
% matrixMultiplyNd performs a multiplication of two N-D matrices (the
%   dimension of both matrices does not need to be equal).
%   The matrix multiplication is performed such that Z_ijlmn =
%   X_ijk * Y_klmn (Einstein notation).
%   All elements of the matrix are multiplied. This happens like a 2-D
%   matrix multiplication: Z_ac = X_ab * Y_bc, where a = i*j and c = l*m*n.
% 
% Inputs:
%   X               N-D matrix 
%   Y               M-D matrix (where the size of the first dimension must
%                   be equal to the size of the last dimension of X)
% 
% Outputs:
%   Z               (N+M-2)-D matrix
% 
% Example:
%   X = rand(2,3,4);
%   Y = rand(4,5,6,7);
%   Z = matrixMultiplyNd(X,Y);
%   size(Z) % this will be [2,3,5,6,7]
%   % now check if Einstein notation is fulfilled with one test sample:
%   i = 2; j = 1; l = 4; m = 6; n = 5;
%   Z(i,j,l,m,n) == sum( squeeze(X(i,j,:)) .* squeeze(Y(:,l,m,n)) ) % true
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

    % all matrix sizes
    sizeX = size(X);
    sizeY = size(Y);
    sizeZ = [ sizeX(1:end-1), sizeY(2:end) ];

    % reshaped dimensions for 2-D matrices
    X_2D_dim1 = prod(sizeX(1:end-1));
    X_2D_dim2 = sizeX(end);
    Y_2D_dim1 = sizeY(1);
    Y_2D_dim2 = prod(sizeY(2:end));

    % reshape X and Y to 2-D matrices
    X_reshape_2D = reshape( X, X_2D_dim1, X_2D_dim2 );
    Y_reshape_2D = reshape( Y, Y_2D_dim1, Y_2D_dim2 );

    % compute 2-D (reshaped) Z matrix
    Z_reshape_2D = X_reshape_2D * Y_reshape_2D;
    
    % reshape Z back to the target size
    Z = reshape( Z_reshape_2D, sizeZ );

end