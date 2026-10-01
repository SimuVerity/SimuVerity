%% Spinning Top, Contact Methods (Totem Shape)
% 
% This example models a top spinning on a flat surface.  A mask parameter
% selects whether the top is modeled with one contact point on the floor or
% two contact points on the floor.
%
% Copyright 2022-2026 The MathWorks, Inc.



%% Model

open_system('sm_spinning_top_totem')

set_param(find_system('sm_spinning_top_totem','MatchFilter',@Simulink.match.allVariants,'FindAll', 'on','type','annotation','Tag','ModelFeatures'),'Interpreter','off')

%% Body of Top and Contact Proxies
%

open_system('sm_spinning_top_totem/Top','force')

%% Simulation Results from Simscape Logging
%%
%
% The plot below shows the speed of the top as it spins.  Due to damping
% and an initial angle of the top, eventually the top tips over and the
% wider radius strikes the floor.  The rotational speed of the top slows
% down rapidly until it rolls around, touching the floor in two spots - the
% point at the bottom of the top and the wider radius.
%

set_param([bdroot '/Top'],'popup_contact','Two Points')
sim(bdroot)
sm_spinning_top_totem_plot1speed;

%%

%clear all
close all
bdclose all
