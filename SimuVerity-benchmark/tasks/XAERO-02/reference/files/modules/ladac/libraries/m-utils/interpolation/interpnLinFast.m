 function Vq = interpnLinFast(varargin)
% interpnLinFast is a probably faster implementation for n-dimensional
% linear interpolation compared to interpn.
% 
%   This function avoids input arguments that are created by ndgrid and
%   thus nD matrices (for x1, x2, ...). Moreover, it avoids that the input
%   arguments x1, x2, ... must have at least 2 elements. Like this, the
%   amount of input data of the interpolation function can be drastically
%   reduced.
%   Note that extrapolation is avoid (the last value in the map will be
%   chosen).
% 
%   Vq = interpnLinFast(x1,x2,x3,...,V,x1q,x2q,x3q,...) interpolates to find Vq,
%   the values of the underlying N-D function V at the query points in
%   arrays x1q,x2q,x3q,etc.  If V is N-D, interpnLinFast should be called with
%   2*N+1 arguments.  Arrays x1,x2,x3,etc. specify the points at which
%   the data V is given.  Out of range values are treated as limit values.
%   x1q,x2q,x3q,etc. must be row vectors where the length of the vectors
%   must match with the according dimension of V. 
% 
%   Vq = interpLinFast(...,extrapolate) considers if out of range values
%   for x1q,x2q,x3q,etc. should be extrapolate (true) or clipped (false).
% 
% See also: interpn

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if nargin < 3
    error('Not enough input arguments.');
elseif mod(nargin,2)==0 && ~islogical(varargin{end})
    error('An odd number of input arguments is required.')
end

if islogical(varargin{end})
    extrapolate = varargin{end};
    dim = (nargin-2)/2;
else
    extrapolate = false;
    dim = (nargin-1)/2;
end


dim_in = zeros(dim,1);
for i = 1:dim
    dim_in(i) = length(varargin{i});
end

num_q = length(varargin{dim+2});

% get indices "lower left" (ll)
idx_ll = zeros( dim, num_q );
for i = 1:dim
    [tmp,idx] = max( repmat(varargin{i},num_q,1) > repmat(varargin{dim+1+i}',1,length(varargin{i})), [], 2);
    idx(tmp==0) = dim_in(i);
    idx_ll(i,:) = idx';
    idx_ll(i,idx_ll(i,:)>1) = idx_ll(i,idx_ll(i,:)>1)-1;
end

% get indices "upper right" (ur)
idx_ur = idx_ll + 1;
% avoid repmat
dim_in_mat = repmat(dim_in,1,num_q);
exceed_max_val = idx_ur > dim_in_mat;
idx_ur(exceed_max_val) = dim_in_mat(exceed_max_val);

% get data for delta grid length and delta q length
dx = zeros(dim,num_q);
dxq = zeros(dim,num_q);
Vq = zeros(1,num_q);
x_rel = zeros(1,dim,num_q);
for i = 1:dim
    dx(i,:) = varargin{i}(idx_ur(i,:)) - varargin{i}(idx_ll(i,:));
    dxq(i,:) = varargin{dim+1+i} - varargin{i}(idx_ll(i,:));
end

% get binary array for all required vertices
is_dim_empty = dim_in==1;
dim_active = dim - sum(is_dim_empty);
num_vertex = 2^dim_active;
binArr = zeros(num_vertex,dim);
binArr(:,~is_dim_empty) = dec2bin_sim(0:num_vertex-1);



sizeV = ones(1,dim);
sizeV(1:length(size(varargin{dim+1}))) = size(varargin{dim+1});

V_sub = zeros(num_vertex,1,num_q);
V_sub(:) = varargin{dim+1}(getVsub(sizeV,idx_ll,binArr));


% http://paulbourke.net/miscellaneous/interpolation/
% (see trilinear interpolation)

% avoid devision by zero and avoid extrapolation in negative direction
if extrapolate
    logi = dx ~= 0;
else
    logi = dx ~= 0 & ~(dxq < 0);
end
x_rel(logi) = dxq(logi)./dx(logi);

% interpolate output (avoid repmat)
Vq(:) = sum( V_sub .* prod( repmat(1-binArr,1,1,num_q) + repmat(2*binArr-1,1,1,num_q) .* repmat(x_rel,num_vertex,1,1), 2 ), 1 );
% Vq(:) = sum( V_sub .* prod( (1-binArr(:,:,ones(num_q,1))) + (2*binArr(:,:,ones(num_q,1))-1) .* x_rel(ones(num_vertex,1),:,:), 2 ), 1 );


function number_2 = dec2bin_sim(dec)
% extracted from dec2bin (which unfortunately returns a char)
    n = 1;
    % make column vector
    dec = dec(:);
    [~,e]=log2(max(dec)); % How many digits do we need to represent the numbers?
    number_2=rem(floor(dec*pow2(1-max(n,e):0)),2);
end

function indices = getVsub( sizeV, idx_ll, binArr )
%#codegen

num_rows = size(idx_ll,1);
num_cols = size(idx_ll,2);

% subscripts to indices
if sizeV(1) == 1
    cum_prod = cumprod(sizeV);
else
    cum_prod = [1, cumprod(sizeV)];
end
zero_ones = [0;ones(num_rows-1,1)];
indices_ll = cum_prod(1:end-1) * (idx_ll - repmat(zero_ones,1,num_cols));

num_rows_bin = size(binArr,1);
indices_add = (cum_prod(1:end-1) * binArr')';

indices = repmat(indices_ll,num_rows_bin,1) + repmat(indices_add,1,num_cols);

end

end