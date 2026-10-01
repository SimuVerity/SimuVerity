function [file] = getFileFromPath(file_path)
% GETFILEFROMPATH returns the file part from a full path to a file.
%
% Inputs:
%   file_path   full path to a file
%
% Outputs:
%   file        filename with extension
%
% See also:
%   FILEPARTS

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
%
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************


[~, file_name, file_ext] = fileparts(file_path);
file = [file_name file_ext];
    
end
