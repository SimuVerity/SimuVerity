% wrapper script for clc and clear for LADAC unit tests
%   c = open_model( modelname ) opens the model 'modelname'. If the
%   script finds the variable 'TEST_LADAC' in the base workspace, it
%   skips that line to prevent deleting variables used for unit tests.
% 
% Syntax:
%   clc_clear;
% 
% See also:
%   open_model, existInBaseWorkspace, validateModelBuild
% 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2020-2022 Fabian Guecker
%   Copyright (C) 2022 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if(~existInBaseWorkspace('TEST_LADAC'))
    clear; clc;
end