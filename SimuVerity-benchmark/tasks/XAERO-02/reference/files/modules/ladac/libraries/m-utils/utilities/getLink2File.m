function file_link = getLink2File(file, link_text)
% GETLINK2FILE returns a link to a file.
% 
%   This functions returns a link to a file which, when clicked, opens the
%   URL using the 'open()' function.
% 
% Inputs:
%   file        file
%   link_text   Displayed name of the link (optional)
% 
% Outputs:
%   file_link   Link to the file
% 
% See also:
%   OPEN
%   https://mathworks.com/help/matlab/matlab_prog/create-hyperlinks-that-run-functions.html

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if ~exist(file, 'file')
    err_msg = sprintf('''%s'' is either not a file or can not be found!', file);
    error('MATLAB:getLink2File:inputError', '\n%s', err_msg);
end

if nargin == 1
    link_text = getFileFromPath(file);
end

file_link = sprintf('<a href = "matlab:open(''%s'')">%s</a>', file, link_text);

end
    