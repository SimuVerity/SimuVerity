function bendPts = generateBendPts(startPts,endPts,radiusBend,directionBend,nPts)
% This function generates points along a curved bend between two points.
% This function computes a set of points defining a circular bend that 
% smoothly connects the specified start and end points using a given bend 
% radius and bend direction.
%
%   Inputs:
%       startPts       - Starting point of the bend, specified as a
%                        1-by-2 vector [x y].
%       endPts         - Ending point of the bend, specified as a
%                        1-by-2 vector [x y].
%       radiusBend     - Radius of curvature of the bend. Must be a
%                        positive scalar.
%       directionBend  - Direction of the bend curvature:
%                        'CW'  for clockwise rotation
%                        'CCW' for counterclockwise rotation
%
%   Optional inputs:
%       nPts           - Number of points used to discretize the bend.
%                        Must be an integer. (Default: 10)
%
%   Output:
%       bendPts        - nPts-by-2 array of [x y] coordinates representing
%                        the discretized bend geometry.
%

% Copyright 2025 - 2026 The MathWorks, Inc.

    arguments
        startPts (1,2) double
        endPts (1,2) double
        radiusBend (1,1) double {mustBePositive}
        directionBend (1,:) char {mustBeMember(directionBend, {'CW','CCW'})}
        nPts (1,1) {mustBeInteger} = 10;
    end

    % Compute chord properties
    chordVec = endPts - startPts;
    chordLen = norm(chordVec);
    midPt = (startPts + endPts) / 2;

    % Check feasibility
    if radiusBend < 0.99*0.5*chordLen
        error('Radius too small for given points.');
    end

    % Perpendicular direction
    perpDir = [-chordVec(2), chordVec(1)] / chordLen;

    % Arc center
    if radiusBend^2 - (chordLen/2)^2 > 0
        h = sqrt(radiusBend^2 - (chordLen/2)^2);
    else
        h = 0;
    end
    if strcmp(directionBend, 'CW')
        center = midPt - h * perpDir;
    else
        center = midPt + h * perpDir;
    end

    % Angles
    thetaStart = atan2(startPts(2)-center(2), startPts(1)-center(1));
    thetaEnd = atan2(endPts(2)-center(2), endPts(1)-center(1));

    % Adjust for direction
    if strcmp(directionBend, 'CW')
        if thetaEnd > thetaStart
            thetaEnd = thetaEnd - 2*pi;
        end
    else
        if thetaEnd < thetaStart
            thetaEnd = thetaEnd + 2*pi;
        end
    end

    % Generate arc points
    theta = linspace(thetaStart, thetaEnd, nPts);
    bendPts = [center(1) + radiusBend*cos(theta)', center(2) + radiusBend*sin(theta)'];
end