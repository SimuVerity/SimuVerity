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
function Heart_GUI(mdl,modelName,filename,savepath)

close all
%% GUI
global ConfigGUI
% initialization
ConfigGUI.path_plot=[];
ConfigGUI.cells=[];
ConfigGUI.Node_pos=[];
ConfigGUI.t=0;
%% Link to the model
ConfigGUI.modelName=modelName;
ConfigGUI.mdl = mdl;
ConfigGUI.savepath=savepath;
load_system(ConfigGUI.mdl);
open_system(ConfigGUI.mdl);
%% Save some of the models original info that this UI may change (and needs to change back again when the simulation stops)
ConfigGUI.originalStopTime = get_param(ConfigGUI.modelName,'Stoptime');
ConfigGUI.originalMode =  get_param(ConfigGUI.modelName,'SimulationMode');
ConfigGUI.simtime=2000;
%% Get the display
pos = get(0, 'screensize'); %get the screensize
W=pos(3);
H=pos(4);
x0=50;
y0=50;
WIDTH=W-50-x0;
HEIGHT=H-100-y0;
%[left bottom width height],the most outer frame
ConfigGUI.Handle=figure('Units', 'Pixels', 'Position', [x0 y0 WIDTH HEIGHT],...
    'Resize','off','Name','UoA CIEDs Closed-loop Validation Platform V1.0','NumberTitle','Off',...
    'WindowButtonDownFcn',@button_down,'Tag','GUI');
% Cardiac conduction system topology axes
ConfigGUI.TOP_axe=subplot(6,2,[1,3,5,7,9,11],'Parent',ConfigGUI.Handle,...
    'Unit','normalized','OuterPosition',[0 0 1*HEIGHT/WIDTH 1],...
    'Xlim',[40 180],'Ylim',[20 160],...
    'NextPlot','add','Box','on');
axis(ConfigGUI.TOP_axe,'manual');
xlabel(ConfigGUI.TOP_axe,'x');
ylabel(ConfigGUI.TOP_axe,'y');
title(ConfigGUI.TOP_axe,'Cardiac Conduction System');
grid(ConfigGUI.TOP_axe,'on');
colormap(ConfigGUI.TOP_axe,hot);
% Place the Nodes and Probes
ConfigGUI.node_pos=scatter(ConfigGUI.TOP_axe,[],[],100,'filled','LineWidth',2,'Marker','o','CData',[0 0 0]); % black
ConfigGUI.probe_pos=scatter(ConfigGUI.TOP_axe,[],[],'LineWidth',1.5,'Marker','d','CData',[0 0 0]);
% Place the Wavefronts
ConfigGUI.wave_posdi=scatter(ConfigGUI.TOP_axe,[],[],50,'LineWidth',1.5,'Marker','v','CData',[1 0 0]);
ConfigGUI.wave_posdj=scatter(ConfigGUI.TOP_axe,[],[],50,'LineWidth',1.5,'Marker','d','CData',[1 0 0]);
ConfigGUI.wave_posri=scatter(ConfigGUI.TOP_axe,[],[],50,'LineWidth',1.5,'Marker','v','CData',[0 0 1]);
ConfigGUI.wave_posrj=scatter(ConfigGUI.TOP_axe,[],[],50,'LineWidth',1.5,'Marker','d','CData',[0 0 1]);
% EGM and events display axes
ConfigGUI.AEGM=subplot(6,2,2,'Parent',ConfigGUI.Handle,'NextPlot','add','Box','on');
ylabel(ConfigGUI.AEGM,'AEGM');
p = get(ConfigGUI.AEGM,'position');
p(3)=p(3)*1.2;
%set(ConfigGUI.AEGM,'Ylim',[-7 7]);
ConfigGUI.VEGM=subplot(6,2,4,'Parent',ConfigGUI.Handle,'NextPlot','add','Box','on');
ylabel(ConfigGUI.VEGM,'VEGM');
p = get(ConfigGUI.VEGM,'position');
p(3)=p(3)*1.2;
%set(ConfigGUI.VEGM,'Ylim',[-20 20]);
ConfigGUI.GET=subplot(6,2,6,'Parent',ConfigGUI.Handle,'NextPlot','add','Box','on');
ylabel(ConfigGUI.GET,'Aget/Vget');
p = get(ConfigGUI.GET,'position');
p(3)=p(3)*1.2;
%set(ConfigGUI.GET,'Ylim',[-1.5 1.5]);
ConfigGUI.P=subplot(6,2,8,'Parent',ConfigGUI.Handle,'NextPlot','add','Box','on');
ylabel(ConfigGUI.P,'AP/VP');
p = get(ConfigGUI.P,'position');
p(3)=p(3)*1.2;
%set(ConfigGUI.P,'Ylim',[-1.5 1.5]);
ConfigGUI.S=subplot(6,2,10,'Parent',ConfigGUI.Handle,'NextPlot','add','Box','on');
ylabel(ConfigGUI.S,'AS/VS');
p = get(ConfigGUI.S,'position');
p(3)=p(3)*1.2;
%set(ConfigGUI.S,'Ylim',[-1.5 1.5]);
ConfigGUI.R=subplot(6,2,12,'Parent',ConfigGUI.Handle,'NextPlot','add','Box','on');
ylabel(ConfigGUI.R,'AR/VR');
xlabel(ConfigGUI.R,'Time (ms)');
p = get(ConfigGUI.R,'position');
p(3)=p(3)*1.2;
%set(ConfigGUI.R,'Ylim',[-1.5 1.5]);

grid(ConfigGUI.AEGM,'on');
grid(ConfigGUI.VEGM,'on');
grid(ConfigGUI.GET,'on');
grid(ConfigGUI.P,'on');
grid(ConfigGUI.S,'on');
grid(ConfigGUI.R,'on');
% Draw initial lines of the EGM and events
ConfigGUI.aegm=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.AEGM,'MaximumNumPoints',4000);
ConfigGUI.vegm=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.VEGM,'MaximumNumPoints',4000);
ConfigGUI.aget=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.GET,'MaximumNumPoints',4000);
ConfigGUI.vget=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.GET,'MaximumNumPoints',1000);
ConfigGUI.ap=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.P,'MaximumNumPoints',4000);
ConfigGUI.vp=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.P,'MaximumNumPoints',4000);
ConfigGUI.as=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.S,'MaximumNumPoints',4000);
ConfigGUI.vs=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.S,'MaximumNumPoints',4000);
ConfigGUI.ar=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.R,'MaximumNumPoints',4000);
ConfigGUI.vr=animatedline('LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.R,'MaximumNumPoints',4000);
% Current position
ConfigGUI.setp=scatter(ConfigGUI.TOP_axe,[],[],'LineWidth',1.5,'Marker','o','CData',[1 0 0]);
ConfigGUI.getp = uicontrol('Parent',ConfigGUI.Handle,...
    'Style','text',...
    'Units','normalized',...
    'Position',[0.15 0.96 0.1 0.03],...
    'BackgroundColor',[1 1 1],...
    'String','(x,y)',...
    'HorizontalAlignment','left',...
    'HandleVisibility','callback',...
    'Tag','getp');
% Create a panel for operations
ConfigGUI.hop = uipanel('Parent',ConfigGUI.Handle,...
    'Units','normalized',...
    'Position',[0.01 0.4 0.04 0.15],...
    'Title','Operations',...
    'BackgroundColor',get(ConfigGUI.Handle,'Color'),...
    'HandleVisibility','callback',...
    'Tag','tunePanel');
strings = {'Start','Pause','Stop','2000'};
positions = [0.6 0.4 0.2 0];
tags = {'startpb','pausepb','stoppb','simtime'};
callbacks = {@localStartPressed, @localPausePressed, @localStopPressed,@localSetTime};
enabled ={'on','off','off','on'};
style={'pushbutton','pushbutton','pushbutton','edit'};
for idx = 1:length(strings)
    uicontrol('Parent',ConfigGUI.hop,...
        'Style',style{idx},...
        'Units','normalized',...
        'Position',[0.05 positions(idx) 0.9 0.2],...
        'BackgroundColor',get(ConfigGUI.Handle,'Color'),...
        'String',strings{idx},...
        'Enable',enabled{idx},...
        'Callback',callbacks{idx},...
        'HandleVisibility','callback',...
        'Tag',tags{idx});
end
% Create a panel for playback
ConfigGUI.hplay = uipanel('Parent',ConfigGUI.Handle,...
    'Units','normalized',...
    'Position',[0.01 0.1 0.04 0.15],...
    'Title','Playback',...
    'BackgroundColor',get(ConfigGUI.Handle,'Color'),...
    'HandleVisibility','callback',...
    'Tag','tunePanel');
strings = {'Load','Start','Pause','0','2000'};
positions = [0.8 0.6 0.4 0.2 0];
style={'pushbutton','pushbutton','pushbutton','edit','edit'};
tags = {'loadpb','playstart','playpause','playst','played'};
callbacks = {@localLoadplay,@localPlaystart,@localPlaypause, @localStartset, @localEndset};
enabled ={'on','off','off','on','on'};
for idx = 1:length(strings)
    uicontrol('Parent',ConfigGUI.hplay,...
        'Style',style{idx},...
        'Units','normalized',...
        'Position',[0.05 positions(idx) 0.9 0.2],...
        'BackgroundColor',get(ConfigGUI.Handle,'Color'),...
        'String',strings{idx},...
        'Enable',enabled{idx},...
        'Callback',callbacks{idx},...
        'HandleVisibility','callback',...
        'Tag',tags{idx});
end
%Load the default model
load_model(filename);
% Specify the number of output of each node and path
ConfigGUI.EachNode=5;  % Number of outputs of each node
ConfigGUI.EachPath=8;  % Number of outputs of each path
% Store ConfigGUI to Userdata and communicate with the Simulink model
set_param(sprintf('%s/S-Function',ConfigGUI.modelName),'UserData',ConfigGUI);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Function for Load model
function load_model(modelcfg)
global ConfigGUI
%[fname,fpath] = uigetfile('*.mat', 'Load VHM Model');
dim=load(modelcfg);
[ConfigGUI.NumNodes,~]=size(dim.Node); % Number of nodes
[ConfigGUI.NumPaths,~]=size(dim.Path); % Number of paths
ConfigGUI.Node_pos=dim.Node_pos;
% Display the nodes and probes; Store the node and probe positions
if ~isempty(ConfigGUI.Node_pos)
    colormap(ConfigGUI.TOP_axe,hot);
    c=zeros(size(ConfigGUI.Node_pos,1),3);
    set(ConfigGUI.node_pos,'XData',ConfigGUI.Node_pos(:,1),'YData',ConfigGUI.Node_pos(:,2),'CData',c);
    for n=1:length(ConfigGUI.Node_pos(:,1))
        text(ConfigGUI.TOP_axe,ConfigGUI.Node_pos(n,1),ConfigGUI.Node_pos(n,2)+2,int2str(n),'Color','blue','FontSize',12);
    end
else
    error('The node position is empty.');
    exit;
end
if ~isempty(dim.Probe_pos)
    set(ConfigGUI.probe_pos,'XData',dim.Probe_pos(:,1),'YData',dim.Probe_pos(:,2));
else
    error('The Probe position is empty.');
    exit;
end
% Draw the paths
for n=1:size(dim.Path,1)
    ConfigGUI.path_plot(n)=line([dim.Node_pos(dim.Path(n,1),1),dim.Node_pos(dim.Path(n,2),1)],[dim.Node_pos(dim.Path(n,1),2),dim.Node_pos(dim.Path(n,2),2)],'LineWidth',1.5,'Color',[0 0 0],'Parent',ConfigGUI.TOP_axe);
end
% Reset wavefronts to (0,0)
x0=zeros(1,size(dim.Path,1));
y0=x0;
set(ConfigGUI.wave_posdi,'XData',x0,'YData',y0);
set(ConfigGUI.wave_posdj,'XData',x0,'YData',y0);
set(ConfigGUI.wave_posri,'XData',x0,'YData',y0);
set(ConfigGUI.wave_posrj,'XData',x0,'YData',y0);
% Reset
set(ConfigGUI.setp,'XData',0,'YData',0);
LineHandles={ConfigGUI.aegm,ConfigGUI.vegm, ConfigGUI.aget,ConfigGUI.vget,ConfigGUI.ap,ConfigGUI.vp,ConfigGUI.as,ConfigGUI.vs,ConfigGUI.ar,ConfigGUI.vr};
for i=1:10
    thisLineHandle = LineHandles{i};
    clearpoints(thisLineHandle);
end
hold on;
set_param(sprintf('%s/S-Function',ConfigGUI.modelName),'UserData',ConfigGUI);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for Start button
function localStartPressed(hObject,eventdata) %#ok
global ConfigGUI
% toggle the buttons
% Turn off the Start button
h = findobj(ConfigGUI.hop,'Tag','startpb');
set(h,'Enable','off');
% Turn on the Pause button
h = findobj(ConfigGUI.hop,'Tag','pausepb');
set(h,'Enable','on');
% Turn on the Stop button
h = findobj(ConfigGUI.hop,'Tag','stoppb');
set(h,'Enable','on');
% Set up the simulation time
localSetTime(ConfigGUI.simtime);
% Perform a different operation
% set the stop time
set_param(ConfigGUI.modelName,'StopTime',ConfigGUI.simtime);
% set the simulation mode to Accelerator
set_param(ConfigGUI.modelName,'SimulationMode','accelerator');
% Initialize the figure
LineHandles={ConfigGUI.aegm,ConfigGUI.vegm,ConfigGUI.aget,ConfigGUI.vget,ConfigGUI.ap,ConfigGUI.vp,ConfigGUI.as,ConfigGUI.vs,ConfigGUI.ar,ConfigGUI.vr};
for i=1:10
    thisLineHandle = LineHandles{i};
    clearpoints(thisLineHandle);
end
c=zeros(size(ConfigGUI.Node_pos,1),3);
set(ConfigGUI.node_pos,'XData',ConfigGUI.Node_pos(:,1),'YData',ConfigGUI.Node_pos(:,2),'CData',c);
set(ConfigGUI.wave_posdi,'XData',0,'YData',0);
set(ConfigGUI.wave_posdj,'XData',0,'YData',0);
set(ConfigGUI.wave_posri,'XData',0,'YData',0);
set(ConfigGUI.wave_posrj,'XData',0,'YData',0);
drawnow update;
% Run the model
set_param(ConfigGUI.modelName,'SimulationCommand','start');
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for Pause button
function localPausePressed(hObject,eventdata) %#ok
global ConfigGUI
% Get the simulation status and perform a different operation
switch get_param(ConfigGUI.modelName,'SimulationStatus')
    % If paused, continue
    case 'paused'
        set_param(ConfigGUI.modelName,'SimulationCommand','continue');
        h = findobj(ConfigGUI.hop,'Tag','pausepb');
        set(h,'String','Pause');
        % If running, pause
    case 'running'
        set_param(ConfigGUI.modelName,'SimulationCommand','pause');
        h = findobj(ConfigGUI.hop,'Tag','pausepb');
        set(h,'String','Continue');
    otherwise
        % shouldn't be able to get in here
        errordlg('Selection Error',...
            'Neither pause nor continue was attempted.', 'modal');
end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for Stop button
function localStopPressed(hObject,eventdata)
global ConfigGUI
% toggle the buttons
% Turn on the Start button
h = findobj(ConfigGUI.hop,'Tag','startpb');
set(h,'Enable','on');
% Turn off the Pause button
h = findobj(ConfigGUI.hop,'Tag','pausepb');
set(h,'String','Pause','Enable','off');
% Turn off the Stop button
h = findobj(ConfigGUI.hop,'Tag','stoppb');
set(h,'Enable','off');
% Perform a different operation
% stop the model
set_param(ConfigGUI.modelName,'SimulationCommand','stop');
% set model properties back to their original values
set_param(ConfigGUI.modelName,'Stoptime',ConfigGUI.originalStopTime);
set_param(ConfigGUI.modelName,'SimulationMode',ConfigGUI.originalMode);
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for simulation time edit box
function localSetTime(hObject,eventdata) %#ok
global ConfigGUI
% Check that a valid value has been entered
h = findobj(ConfigGUI.hop,'Tag','simtime');
str = get(h,'String');
newValue = str2double(str);
% Do the change if it's valid
if ~isnan(newValue)
    % store the new value
    ConfigGUI.simtime = str;
else
    % throw up an error dialog
    estr = sprintf('%s is an invalid time value.',str);
    errordlg(estr,'Time setup Error','modal');
end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for start time edit box
function localStartset(hObject,eventdata) %#ok

end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for start time edit box
function localEndset(hObject,eventdata) %#ok

end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for Load button
function localLoadplay(hObject,eventdata)%#ok
global ConfigGUI
% Initialize the figure
LineHandles={ConfigGUI.aegm,ConfigGUI.vegm, ConfigGUI.aget,ConfigGUI.vget,ConfigGUI.ap,ConfigGUI.vp,ConfigGUI.as,ConfigGUI.vs,ConfigGUI.ar,ConfigGUI.vr};
for i=1:10
    thisLineHandle = LineHandles{i};
    clearpoints(thisLineHandle);
end
c=zeros(size(ConfigGUI.Node_pos,1),3);
colormap(ConfigGUI.TOP_axe,hot);
set(ConfigGUI.node_pos,'XData',ConfigGUI.Node_pos(:,1),'YData',ConfigGUI.Node_pos(:,2),'CData',c);
set(ConfigGUI.wave_posdi,'XData',0,'YData',0);
set(ConfigGUI.wave_posdj,'XData',0,'YData',0);
set(ConfigGUI.wave_posri,'XData',0,'YData',0);
set(ConfigGUI.wave_posrj,'XData',0,'YData',0);
drawnow update;
h = findobj(ConfigGUI.hplay,'Tag','loadpb');
switch get(h,'String')
    case 'Load'
        set(h,'String','Stop');
        [fname,fpath] = uigetfile('*.mat', 'Load VHM Model');
        dim=load([fpath fname]);
        ConfigGUI.cells=dim.cells;
        h = findobj(ConfigGUI.hplay,'Tag','playstart');
        set(h,'Enable','on'); % Ready to start
        h = findobj(ConfigGUI.hplay,'Tag','playst');
        set(h,'Enable','on');
        
    case 'Stop'
        set(h,'String','Load');
        h1 = findobj(ConfigGUI.hplay,'Tag','playst');
        set(h1,'Enable','off','String','0');
        h = findobj(ConfigGUI.hplay,'Tag','playstart');
        set(h,'String','Start','Enable','on');
        h = findobj(ConfigGUI.hplay,'Tag','playpause');
        if strcmp(get(h,'Enable'),'off')
            set(h1,'Enable','on','String','0');
        else
            set(h,'Enable','off');
        end
end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function localPlaystart(hObject,eventdata)%#ok
global ConfigGUI

h = findobj(ConfigGUI.hplay,'Tag','loadpb');
set(h,'String','Stop');
h2 = findobj(ConfigGUI.hplay,'Tag','playpause');
set(h2,'Enable','on');
h = findobj(ConfigGUI.hplay,'Tag','playstart');
set(h,'Enable','off');

h1 = findobj(ConfigGUI.hplay,'Tag','played');
str = get(h1,'String');
end_time = find(abs(ConfigGUI.cells(1,:)-str2double(str)) < eps);

h1 = findobj(ConfigGUI.hplay,'Tag','playst');
set(h1,'Enable','on');

if strcmp(get(h,'String'),'Start')
    % Initialize the figure when playback starts.
    LineHandles={ConfigGUI.aegm,ConfigGUI.vegm,ConfigGUI.aget,ConfigGUI.vget,ConfigGUI.ap,ConfigGUI.vp,ConfigGUI.as,ConfigGUI.vs,ConfigGUI.ar,ConfigGUI.vr};
    for i=1:10
        thisLineHandle = LineHandles{i};
        clearpoints(thisLineHandle);
    end
    c=zeros(size(ConfigGUI.Node_pos,1),3);
    set(ConfigGUI.node_pos,'XData',ConfigGUI.Node_pos(:,1),'YData',ConfigGUI.Node_pos(:,2),'CData',c);
    set(ConfigGUI.wave_posdi,'XData',0,'YData',0);
    set(ConfigGUI.wave_posdj,'XData',0,'YData',0);
    set(ConfigGUI.wave_posri,'XData',0,'YData',0);
    set(ConfigGUI.wave_posrj,'XData',0,'YData',0);
    drawnow update;
end
while (1)
    pause(0.05);
    wait = get(h1,'Enable');
    if strcmp(wait,'on')
        str = get(h1,'String');
        start_time =find(abs(ConfigGUI.cells(1,:)-str2double(str)) < eps);
        
        if start_time<end_time
            playback(start_time); % Update display
            start_time=start_time+1;
            str=int2str(start_time);
            set(h1,'String',str); % Update time
        else
            set(h1,'Enable','on');
            set(h,'String','Start','Enable','on');
            set(h2,'Enable','off');
            h = findobj(ConfigGUI.hplay,'Tag','loadpb');
            set(h,'String','Load');
            break;
        end
    else
        set(h1,'Enable','on');
        set(h,'Enable','on');
        break;
    end
end
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function localPlaypause(hObject,eventdata)%#ok
global ConfigGUI
h = findobj(ConfigGUI.hplay,'Tag','playpause');
h1 = findobj(ConfigGUI.hplay,'Tag','playst');
set(h1,'Enable','off');
set(h,'Enable','off');
h = findobj(ConfigGUI.hplay,'Tag','playstart');
set(h,'Enable','on','String','Continue');
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function playback(n)
global ConfigGUI
Config=ConfigGUI;
t=Config.cells(1,n);
u=Config.cells(2:end,n);
% Update node status
% Update the color of nodes according to the value of v;
ed=(ConfigGUI.NumNodes-1)*ConfigGUI.EachNode;
%Config.node_pos=scatter(Config.TOP_axe,u(4:EachNode:ed+4),u(5:EachNode:ed+5),70,u(2:EachNode:ed+2),'filled','LineWidth',2,'Marker','o');
c=u(2:ConfigGUI.EachNode:ed+2);
set(Config.node_pos,'XData',Config.Node_pos(:,1),'YData',Config.Node_pos(:,2),'CData',c);
% Update wavefront
st=ConfigGUI.NumNodes*ConfigGUI.EachNode;
ed=(ConfigGUI.NumPaths-1)*ConfigGUI.EachPath+ConfigGUI.NumNodes*ConfigGUI.EachNode;
xd1=u(st+1:ConfigGUI.EachPath:ed+1);
yd1=u(st+2:ConfigGUI.EachPath:ed+2);
xd2=u(st+3:ConfigGUI.EachPath:ed+3);
yd2=u(st+4:ConfigGUI.EachPath:ed+4);
xr1=u(st+5:ConfigGUI.EachPath:ed+5);
yr1=u(st+6:ConfigGUI.EachPath:ed+6);
xr2=u(st+7:ConfigGUI.EachPath:ed+7);
yr2=u(st+8:ConfigGUI.EachPath:ed+8);
set(Config.wave_posdi,'XData',xd1,'YData',yd1);
set(Config.wave_posdj,'XData',xd2,'YData',yd2);
set(Config.wave_posri,'XData',xr1,'YData',yr1);
set(Config.wave_posrj,'XData',xr2,'YData',yr2);
drawnow limitrate;
% Update egms
st=ConfigGUI.NumPaths*ConfigGUI.EachPath+ConfigGUI.NumNodes*ConfigGUI.EachNode;
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
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Callback Function for click
function button_down(hObject,eventdata) %#ok
global ConfigGUI
cursorPoint = get(ConfigGUI.TOP_axe, 'CurrentPoint');
curX = cursorPoint(1,1);
curY = cursorPoint(1,2);
xLimits = get(ConfigGUI.TOP_axe, 'xlim');
yLimits = get(ConfigGUI.TOP_axe, 'ylim');
if (curX > min(xLimits) && curX < max(xLimits) && curY > min(yLimits) && curY < max(yLimits))
    set(ConfigGUI.getp,'String',sprintf('(%.2f,%.2f)',curX,curY));
    set(ConfigGUI.setp,'XData',curX,'YData',curY);
    drawnow update;
    
else
    set(ConfigGUI.getp,'String',sprintf('(Outside)'));
end

end

