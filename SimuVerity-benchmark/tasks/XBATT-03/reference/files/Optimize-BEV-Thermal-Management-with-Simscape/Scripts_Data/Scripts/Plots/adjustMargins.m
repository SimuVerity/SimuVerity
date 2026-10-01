function adjustMargins(leftMarginCm, bottomMarginCm, rightMarginCm, topMarginCm)
%% Description: 
% This function is used to adjust the margins of a pictures to the desired
% values given in cm. The inputs represents the desired size in centimiters
% of left, bottom, right and top margin

%-----------------
% Copyright 2022-2025 The MathWorks, Inc.
%-----------------

%% Implementation
% Convert cm to normalized figure units
figureHandle   = gcf; % Get current figure handle
set(figureHandle, 'Units', 'centimeters');
figPos = get(figureHandle, 'Position'); % [left, bottom, width, height] in cm

% Calculate normalized margins
leftMarginNormalized   = leftMarginCm   / figPos(3);
bottomMarginNormalized = bottomMarginCm / figPos(4);
rightMarginNormalized  = rightMarginCm  / figPos(3);
topMarginNormalized    = topMarginCm    / figPos(4);

% Calculate new axes position from the margins
newAxesPos = [leftMarginNormalized, ...
              bottomMarginNormalized, ...
              1 - leftMarginNormalized - rightMarginNormalized, ...
              1 - bottomMarginNormalized - topMarginNormalized];

% Adjust the axes to the newly calculated position
set(gca, 'Position', newAxesPos);

end
