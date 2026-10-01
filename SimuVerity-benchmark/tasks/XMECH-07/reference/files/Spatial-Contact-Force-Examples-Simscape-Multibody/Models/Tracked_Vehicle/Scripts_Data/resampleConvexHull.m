
function Q = resampleConvexHull(P, N, varargin)
%RESAMPLECONVEXHULL Resample the convex hull of a 2D point set to N evenly spaced points.
%
% Q = resampleConvexHull(P, N) takes an Mx2 array P of [x y] points and returns
% an Nx2 array Q lying on the convex hull perimeter, evenly spaced by arc length.
%
% This eliminates all interior points and enforces convexity via convhull().
%
% Name-Value options:
%   'RemoveCollinear' (logical) default true   % simplifies collinear vertices on hull
%   'Tol'             (double)  default 1e-12  % numerical tolerance
%
% Notes:
% - Handles unordered input; no need for CCW ordering—convhull returns CCW.
% - Ensures closure and robust interpolation along perimeter arc-length.
% - Returns exactly N points; the final point is not a duplicate of the first.
%
% Example:
%   P = rand(200,2)*2 - 1;          % random points
%   Q = resampleConvexHull(P, 100); % 100 evenly spaced hull points
%   figure; hold on; axis equal
%   plot(P(:,1),P(:,2),'k.');       % original cloud
%   plot(Q(:,1),Q(:,2),'ro','MarkerSize',3);
%   plot([Q(:,1);Q(1,1)],[Q(:,2);Q(1,2)],'r-'); % hull outline
%   legend('Points','Resampled hull','Location','best');
%   title('Evenly spaced points on convex hull');

% Parse inputs
p = inputParser;
addRequired(p, 'P', @(x)isnumeric(x) && size(x,2)==2 && size(x,1)>=2);
addRequired(p, 'N', @(x)isnumeric(x) && isscalar(x) && x>=2);
addParameter(p, 'RemoveCollinear', true, @(x)islogical(x));
addParameter(p, 'Tol', 1e-12, @(x)isnumeric(x) && isscalar(x) && x>0);
parse(p, P, N, varargin{:});

RemoveCollinear = p.Results.RemoveCollinear;
Tol             = p.Results.Tol;

% Handle trivial cases
M = size(P,1);
if M == 2
    % Two points: just sample the segment between them
    Q = resampleOpenPolyline([P; P(1,:)], N, Tol); % close for uniform handling
    return;
end

% Compute convex hull indices (CCW, last equals first to close)
K = convhull(P(:,1), P(:,2));    % K is a vector of indices; last repeats the first
H = P(K, :);                     % hull vertices, closed

% Optionally remove collinear vertices on the hull (helps with long flat edges)
if RemoveCollinear
    H = removeCollinearVerticesClosed(H, Tol);
    % Ensure closure after simplification
    if norm(H(1,:) - H(end,:)) > Tol
        H = [H; H(1,:)];
    end
end

% Compute cumulative arc length along the closed hull
dxy    = diff(H, 1, 1);
segLen = sqrt(sum(dxy.^2, 2));
keep   = segLen > Tol;           % drop zero-length edges
H      = H([true; keep], :);
segLen = segLen(keep);
s      = [0; cumsum(segLen)];
L      = s(end);

% Target arc-length positions: N evenly spaced points over [0, L)
s_target = linspace(0, L, N+1).';
s_target(end) = [];  % avoid duplicating the start point

% Interpolate x(s), y(s) linearly along hull
x  = H(:,1); y = H(:,2);
Qx = interp1(s, x, s_target, 'linear');
Qy = interp1(s, y, s_target, 'linear');
Q  = [Qx, Qy];

end

% ----------------- Helpers -----------------

function Q = resampleOpenPolyline(Pclosed, N, Tol)
% Resample a closed polyline Pclosed (first==last) to N evenly spaced points
dxy    = diff(Pclosed,1,1);
segLen = sqrt(sum(dxy.^2,2));
keep   = segLen > Tol;
Pclosed = Pclosed([true; keep], :);
segLen = segLen(keep);
s      = [0; cumsum(segLen)];
L      = s(end);
s_target = linspace(0, L, N+1).';
s_target(end) = [];
Qx = interp1(s, Pclosed(:,1), s_target, 'linear');
Qy = interp1(s, Pclosed(:,2), s_target, 'linear');
Q  = [Qx, Qy];
end

function P2 = removeCollinearVerticesClosed(P, Tol)
% Removes intermediate collinear vertices from a closed polyline (first==last)
M = size(P,1);
if M <= 3
    P2 = P; return;
end
keep = true(M,1);
for i = 2:M-1
    a = P(i-1,:);
    b = P(i,:);
    c = P(i+1,:);
    v1 = b - a;
    v2 = c - b;
    crossmag = abs(v1(1)*v2(2) - v1(2)*v2(1));
    if crossmag < Tol * (norm(v1) + norm(v2))
        keep(i) = false;
    end
end
P2 = P(keep, :);
% Guard: ensure we still have a valid closed polygon (>= 4 including closure)
if size(P2,1) < 4
    P2 = P;
end
end
