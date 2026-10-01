function reachTime = checkTempReq(tempVector,tempLim,varargin)
%% Description: 
% This helper function checks how long it takes for the given temperature
% vector to reach the field provided in the vector tempLim. The input can be 
% in K or °C but they both have to use the same units. 
% By default if the temperature is not reached, the value is set to NaN

%% Inputs:
% tempVector: [nx2 double]: Representing [time, temperature] of any component
% tempLim:    [1x2 double]: Representing [Tmin, Tmax]. Must use the same unit as tempVector
% DispMsg:    [1x1 char  ]: Optional, the message to display if the temperature range is not reached

%% Output
% reachTime: [1x1 double]: Time it takes to reach the target range

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

% Parse input arguments
p = inputParser;

% Add the optional inputs
addOptional(p,'DispMsg', 'The target temperature range is NOT reached');

% Use the parse object and create the optional variables
parse(p, varargin{:});

% Create the optional input variables
DispMsg = p.Results.DispMsg;

% Find the first point where the temperature is within the range
idTemp = find(tempVector(:,2)<tempLim(2) & tempVector(:,2)>tempLim(1),1);

% If the temperature range is not reached set the output to NaN
if isempty(idTemp)
    reachTime = NaN;
    disp(DispMsg);

else
    reachTime = tempVector(idTemp,1);
end

end