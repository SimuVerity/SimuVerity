function clearAllBuses( )
%clearAllBuses clear all Simulink bus objects from base workspace
% 
% Syntax:
%   clearAllBuses
% 
% See also:
%   struct2bus, struct2slbus
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

info=evalin('base','whos');

num_vars = length(info);

for i=1:num_vars
    if strcmp(info(i).class,'Simulink.Bus')
        evalin('base',['clear ' info(i).name])
    end
end

end