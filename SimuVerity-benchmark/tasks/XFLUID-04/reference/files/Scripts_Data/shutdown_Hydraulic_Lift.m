function shutdown_Hydraulic_Lift
% Copyright 2012-2025 The MathWorks, Inc.

curr_proj = simulinkproject;
cd(curr_proj.RootFolder);

% FOR CUSTOM ORIFICES
cd('Libraries');
if(exist('+Custom','dir') && exist('Custom_lib.slx','file'))
    bdclose('Custom_lib')
    ssc_clean Custom
end
cd(curr_proj.RootFolder);

% If parameter sweep plot still open, close it
try close(h4_ssc_hydraulic_lift_pct),end
clear h4_ssc_hydraulic_lift_pct