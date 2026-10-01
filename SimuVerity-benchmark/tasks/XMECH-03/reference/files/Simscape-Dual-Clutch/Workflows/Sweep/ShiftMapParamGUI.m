function varargout = ShiftMapParamGUI(varargin)
%SHIFTMAPPARAMGUI M-file for ShiftMapParamGUI.fig
%      SHIFTMAPPARAMGUI, by itself, creates a new SHIFTMAPPARAMGUI or raises the existing
%      singleton*.
%
%      H = SHIFTMAPPARAMGUI returns the handle to a new SHIFTMAPPARAMGUI or the handle to
%      the existing singleton*.
%
%      SHIFTMAPPARAMGUI('Property','Value',...) creates a new SHIFTMAPPARAMGUI using the
%      given property value pairs. Unrecognized properties are passed via
%      varargin to ShiftMapParamGUI_OpeningFcn.  This calling syntax produces a
%      warning when there is an existing singleton*.
%
%      SHIFTMAPPARAMGUI('CALLBACK') and SHIFTMAPPARAMGUI('CALLBACK',hObject,...) call the
%      local function named CALLBACK in SHIFTMAPPARAMGUI.M with the given input
%      arguments.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Copyright 2013-2025 MathWorks, Inc.

% Edit the above text to modify the response to help ShiftMapParamGUI

% Last Modified by GUIDE v2.5 30-Jun-2011 09:20:24

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @ShiftMapParamGUI_OpeningFcn, ...
                   'gui_OutputFcn',  @ShiftMapParamGUI_OutputFcn, ...
                   'gui_LayoutFcn',  [], ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
   gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before ShiftMapParamGUI is made visible.
function ShiftMapParamGUI_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   unrecognized PropertyName/PropertyValue pairs from the
%            command line (see VARARGIN)

% Choose default command line output for ShiftMapParamGUI
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes ShiftMapParamGUI wait for user response (see UIRESUME)
% uiwait(handles.figure1);

values = get(handles.slider,'value');
set(handles.edit,{'String'},values);
[Upshift_Speeds Downshift_Speeds Pedal_Positions] = Calc_Shift_Map_RO(values{1},values{2});
%figure(2)
Plot_Gear_Shift_Schedule(Pedal_Positions, Upshift_Speeds, Downshift_Speeds);
set(gca,'XLim',[0 120]);

% --- Outputs from this function are returned to the command line.
function varargout = ShiftMapParamGUI_OutputFcn(hObject, eventdata, handles)
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


% --- Executes on slider movement.
function slider_Callback(hObject, eventdata, handles)
% hObject    handle to slider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'Value') returns position of slider
%        get(hObject,'Min') and get(hObject,'Max') to determine range of slider
values = get(handles.slider,'value');
set(handles.edit,{'String'},values);

[Upshift_Speeds Downshift_Speeds Pedal_Positions] = Calc_Shift_Map_RO(values{1},values{2});
%figure(2)
Plot_Gear_Shift_Schedule(Pedal_Positions, Upshift_Speeds, Downshift_Speeds);
set(gca,'XLim',[0 120]);


function edit_Callback(hObject, eventdata, handles)
% hObject    handle to edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of edit as text
%        str2double(get(hObject,'String')) returns contents of edit as a double
values = str2double(get(handles.edit,'string'));
set(handles.slider,{'Value'},arrayfun(@(x) {x},values));
