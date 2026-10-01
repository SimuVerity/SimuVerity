%% Power Split Planetary Gear
% 
% <<sm_cvt_power_split_pg_Overview.png>>
% 
% This example models a power split continuously variable transmission
% (CVT) with a single planetary gear. Two power sources turn mechanical
% shafts attached to the sun and ring gear.  The output shaft is attached
% to the carrier. The output speed of the planetary gear is affected by the
% two input speeds and the gear ratio of the planetary gear.  Any gear
% ratio can be achieved between the ring gear and the carrier (including 0)
% by varying the speed of the sun gear.
%
% (<matlab:web('Wheel_Loader_Design_Overview.html') return to Wheel Loader Design with Simscape Overview>)
%
% Copyright 2023-2025 The MathWorks, Inc.

%% Model
%
% This shows how a single planetary gear can serve as a power-split
% continuously variable transmission.
%
% <matlab:open_system('sm_cvt_power_split_pg'); Open Model>

open_system('sm_cvt_power_split_pg')
set_param(bdroot,'LibraryLinkDisplay','none')

set_param(find_system('sm_cvt_power_split_pg','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Planetary Gear 1 Subsystem
%
% The planetary gear is modeled using common gear constraints.
%
% <matlab:open_system('sm_cvt_power_split_pg');open_system('sm_cvt_power_split_pg/Planetary%20Gear%201','force'); Open Subsystem>

set_param('sm_cvt_power_split_pg/Planetary Gear 1','LinkStatus','none')
open_system('sm_cvt_power_split_pg/Planetary Gear 1','force')

%% Simulation Results: Full Speed Range Test
%%
%
% This test keeps the speed of the ring shaft constant while the speed of
% the sun gear is varied.  This is the situation for a CVT used with an
% engine that is kept running at a speed close to its maximum efficiency,
% and must always spin to power other implements, such as hydraulic pumps
% or generators that drive other implements on the vehicle.  The vehicle,
% however, may come to rest while the engine is running.  
%
% The sun gear speed is varied to show that different vehicle speeds can be
% achieved even while the engine is spinning at a near constant speed.

sim('sm_cvt_power_split_pg');
sm_cvt_power_split_pg_plot1speed(simlog_sm_cvt_power_split_pg,logsout_sm_cvt_power_split_pg,cvtPar)

%%

close all
bdclose('sm_cvt_power_split_pg');
