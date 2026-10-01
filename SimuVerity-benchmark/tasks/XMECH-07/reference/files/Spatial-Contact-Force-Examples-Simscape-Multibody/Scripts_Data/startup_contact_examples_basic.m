% Startup script for project
% Copyright 2018-2026 The MathWorks, Inc.

%% Change to project root folder
curr_proj = simulinkproject;
cd(curr_proj.RootFolder)

% If running in a parallel pool
% do not open model or demo script
open_start_content = 1;
if(~isempty(ver('parallel')))
    if(~isempty(getCurrentTask()))
        open_start_content = 0;
    end
end

if(open_start_content)
    sm_contact_ball
    web('Multibody_Contact_Examples_Demo_Script.html')
end
