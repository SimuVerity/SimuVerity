function url_link = getLink2URL(url, link_text)
% GETLINK2URL returns a link to an URL.
% 
%   This functions returns a link to an URL which, when clicked, opens the
%   URL using the 'web()' function with the system browser.
% 
% Inputs:
%   url         URL
%   link_text   Displayed name of the link (optional)
% 
% Outputs:
%   url_link    Link to the URL
% 
% See also:
%   WEB
%   https://mathworks.com/help/matlab/matlab_prog/create-hyperlinks-that-run-functions.html

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

if nargin == 2
    url_link = sprintf('<a href = "matlab:web(''%s'',''-browser'')">%s</a>', url, link_text);
else
    url_link = sprintf('<a href = "matlab:web(''%1$s'',''-browser'')">%1$s</a>', url);
end

end
