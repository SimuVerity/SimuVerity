% Copyright 2025 Weiwei Ai, University of Auckland.
% 
% Licensed under the Apache License, Version 2.0 (the "License");
% you may not use this file except in compliance with the License.
% You may obtain a copy of the License at
% 
%     http://www.apache.org/licenses/LICENSE-2.0
% 
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS,
% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
% See the License for the specific language governing permissions and
% limitations under the License.
%%
function [sys,x0,str,ts] = SaveTrace_sfcn(t,x,u,flag,Ts)

%%
% t, current time; x state vector; u input vector; flag Integer value that
% indicates the task to be performed by the S-function;
% sys, a generic return argument. The values returned depend on the flag value. For example, for flag = 3, sys contains the S-function outputs.
% x0, the initial state values (an empty vector if there are no states in the system). x0 is ignored, except when flag = 0.
% str, originally intended for future use. Level-1 MATLAB S-functions must set this to the empty matrix, [].
% ts, a two-column matrix containing the sample times and offsets of the block (see Specify Sample Time in Using Simulink for information on how to specify a sample times and offsets).
% For example, if you want your S-function to run at every time step (continuous sample time), set ts to [0 0]. If you want your S-function to run at the same rate as the block to which it is connected (inherited sample time), set ts to [-1 0]. If you want it to run every 0.25 seconds (discrete sample time) starting at 0.1 seconds after the simulation start time, set ts to [0.25 0.1].
switch flag
    case 0 % set up
        [sys,x0,str,ts]=mdlInitializeSizes(Ts);
    case 2 % mdlUpdate
        sys=mdlUpdate(t,x,u,Ts);
    case 3 % mdlOutputs
        sys = mdlOutputs(t,x,u);
    case 9 %end-of-simulation task
        sys=mdlTerminate(t,x,u);
    case { 1, 4} %
        sys = [0 0 0 0];
    otherwise
        error(['Unhandled flag = ',num2str(flag)]);
end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Initialization
function [sys,x0,str,ts]=mdlInitializeSizes(Ts)
% Link to GUI
Config=get_param(gcbh,'UserData');
% call simsizes for a sizes structure, fill it in and convert to a sizes array.
sizes = simsizes;
NumEgms=10;
sizes.NumContStates  = 0;
sizes.NumDiscStates  = 1;
sizes.NumOutputs     = 0;
sizes.NumInputs      = Config.NumNodes*Config.EachNode+Config.NumPaths*Config.EachPath+NumEgms;
sizes.DirFeedthrough = 0;
sizes.NumSampleTimes = 1;
% This passes the information in the sizes structure to sys, a vector that holds the information for use by the Simulink engine.
sys = simsizes(sizes);
x0  = [0];
str = [];
ts  = [Ts 0];
Config=get_param(gcbh,'UserData');
Config.cells=[];
set_param(gcbh,'UserData',Config);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Update
function sys=mdlUpdate(t,x,u,Ts)
% Link to GUI
Config=get_param(gcbh,'UserData');
sys=x;
temp=[t;u];
Config.cells=horzcat(Config.cells,temp);
% Update node status
% Update the color of nodes according to the value of v;
ed=(Config.NumNodes-1)*Config.EachNode;
%Config.node_pos=scatter(Config.TOP_axe,u(4:EachNode:ed+4),u(5:EachNode:ed+5),70,u(2:EachNode:ed+2),'filled','LineWidth',2,'Marker','o');
c=u(2:Config.EachNode:ed+2);
set(Config.node_pos,'XData',Config.Node_pos(:,1),'YData',Config.Node_pos(:,2),'CData',c);
% Update wavefront
st=Config.NumNodes*Config.EachNode;
ed=(Config.NumPaths-1)*Config.EachPath+Config.NumNodes*Config.EachNode;
xd1=u(st+1:Config.EachPath:ed+1);
yd1=u(st+2:Config.EachPath:ed+2);
xd2=u(st+3:Config.EachPath:ed+3);
yd2=u(st+4:Config.EachPath:ed+4);
xr1=u(st+5:Config.EachPath:ed+5);
yr1=u(st+6:Config.EachPath:ed+6);
xr2=u(st+7:Config.EachPath:ed+7);
yr2=u(st+8:Config.EachPath:ed+8);
set(Config.wave_posdi,'XData',xd1,'YData',yd1);
set(Config.wave_posdj,'XData',xd2,'YData',yd2);
set(Config.wave_posri,'XData',xr1,'YData',yr1);
set(Config.wave_posrj,'XData',xr2,'YData',yr2);
drawnow limitrate;
% Update egms
st=Config.NumPaths*Config.EachPath+Config.NumNodes*Config.EachNode;
% Get the handle to the line that currently needs updating
LineHandles={Config.aegm,Config.vegm};
LineAxes={Config.AEGM,Config.VEGM};
for i=1:2
    thisLineHandle = LineHandles{i};
    % Get the simulation time and the block data
    sTime = t;
    data = u(st+i);
    newXLim = [max(0,sTime-2000) max(2000,sTime)];
    set(LineAxes{i},'Xlim',newXLim);
    addpoints(thisLineHandle,sTime,data);
    drawnow update;
end
% Update events
st=st+2;
% Get the handle to the line that currently needs updating
LineHandles={Config.aget,Config.vget,Config.ap,Config.vp,Config.as,Config.vs,Config.ar,Config.vr};
LineAxes={Config.GET,Config.P,Config.S,Config.R};
for i=1:4
    thisLineHandle = LineHandles{i*2-1};
    % Get the simulation time and the block data
    sTime = t;
    data1 = u(st+i*2-1);
    data2=-u(st+i*2);
    newXLim = [max(0,sTime-2000) max(2000,sTime)];
    set(LineAxes{i},'Xlim',newXLim);
    addpoints(thisLineHandle,sTime,data1);
    thisLineHandle = LineHandles{i*2};
    addpoints(thisLineHandle,sTime,data2);
    drawnow update;
end
set_param(gcbh,'UserData',Config);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Outputs

function sys = mdlOutputs(t,x,u)
% No outputs
sys = [];
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function sys=mdlTerminate(t,x,u);
sys = [];
% Link to GUI
Config=get_param(gcbh,'UserData');
filename=Config.savepath;
cells=Config.cells;
save (filename,'cells');
end

