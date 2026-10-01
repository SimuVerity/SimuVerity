function id = struct2slbus( s, varargin )
% struct2slbus create simulink bus object(s) from struct
%   THIS FUNCTION WILL PROBABLY BE REPLACED BY STRUCT2BUS IN THE FUTURE.
%   PLEASE USE STRUCT2BUS INSTEAD OF THIS FUNCTION.   
% 
% Syntax:
%   id = struct2slbus( s )
%   id = struct2slbus( s, bus_name )
% 
% Inputs:
%   s           A struct which is meant to be used as a Simulink bus signal
%   bus_name    Optional: Desired name of the corresponding bus object
%               (chars). The chars 'Bus' will be appended to the specified
%               bus_name. If no bus_name was specified, the bus object will
%               be named as the struct s but with the appendix 'Bus'.
% 
% Outputs:
%   id          The number which was appendended to the desired bus_name 
%               (numbers as chars). An id is appended in case the was
%               already a variable of the same name. If no id was appended,
%               the id is empty.
%   
% See also: struct2bus

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
%
%   Copyright (C) 2020-2022 Yannic Beyer
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if isempty(varargin)
    bus_name = [inputname(1),'Bus'];
else
    bus_name = [varargin{1},'Bus'];
end

id = struct2bus( s, bus_name );

end
