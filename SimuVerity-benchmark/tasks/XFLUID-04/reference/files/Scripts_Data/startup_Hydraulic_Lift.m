function startup_Hydraulic_Lift
% Copyright 2012-2025 The MathWorks, Inc.

curr_proj = simulinkproject;
cd(curr_proj.RootFolder);

% FOR CUSTOM ORIFICES
cd('Libraries');
if((exist('+Custom')==7) && ~exist('Custom_lib'))
    disp('Building Custom Simscape Library...');
    ssc_build Custom
    disp('Finished Building Library.');
end
cd(curr_proj.RootFolder);

evalin('base','Scissor_Lift_Model_PARAM');

open_start_content = 1;

% If running in a parallel pool
% do not open model or demo script
if(~isempty(ver('parallel')))
    if(~isempty(getCurrentTask()))
        open_start_content = 0;
    end
end

if(open_start_content)
    ssc_hydraulic_lift_sethardstop('adjusted');
    ssc_hydraulic_lift
    web('ssc_hydraulic_lift_Demo_Script.html');
end