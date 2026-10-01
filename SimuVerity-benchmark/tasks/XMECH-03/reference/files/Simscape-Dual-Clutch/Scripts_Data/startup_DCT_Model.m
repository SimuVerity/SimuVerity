% Startup script for project Dual_Clutch_Trans.prj
% Copyright 2011-2025 The MathWorks, Inc.

DCT_Model_HomeDir = pwd;
DCT_Model_PARAM
MBC_Engine_Calibrations

open_start_content = 1;

% If running in a parallel pool
% do not open model or demo script
if(~isempty(ver('parallel')))
    if(~isempty(getCurrentTask()))
        open_start_content = 0;
    end
end

if(open_start_content)
    web('DCT_Model_Demo_Script.html')
    Dual_Clutch_Trans
end









