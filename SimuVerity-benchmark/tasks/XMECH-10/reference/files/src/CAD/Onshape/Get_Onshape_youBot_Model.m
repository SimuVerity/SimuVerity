% Example MATLAB script to convert Onshape CAD assembly to a
% Simscape Multibody model
%
% Running this script will
% 1. Export an example CAD assembly from Onshape
%    Note: requires Onshape account
% 2. Automatically construct a Simscape Multibody model
% 3. Adjust a couple default settings
% 4. Run the simulation
% 5. Add actuation
% 6. Run the simulation

% Copyright 2016-2025 The MathWorks, Inc.

% Add current directory to path
%addpath(pwd)

%% Create and move to folder for files
cd('OnshapeyouBot')

%% 1. Export CAD assembly from Onshape
% Requires Onshape account
OnshapeyouBot_url = 'https://cad.onshape.com/documents/58888ce7a4f89a0fbe428251/w/83f95055aff518f4d909b00b/e/0a8992b268b7a97a9bc90027';
if ~verLessThan('matlab', '9.2')
    multibody_xml_file = smexportonshape('https://cad.onshape.com/documents/58888ce7a4f89a0fbe428251/w/83f95055aff518f4d909b00b/e/0a8992b268b7a97a9bc90027');
elseif verLessThan('matlab', '9.1')
    errordlg('Export from Onshape is not supported in this release','Export Not Supported');
else
    if (exist('smexportonshape_16b','file'))
        multibody_xml_file = smexportonshape_16b('https://cad.onshape.com/documents/58888ce7a4f89a0fbe428251/w/83f95055aff518f4d909b00b/e/0a8992b268b7a97a9bc90027');
    else
        errordlg('Please visit the MATLAB Central File Exchange to download the function that will enable you to export from Onshape to Simscape Multibody.','Function not present');
        return
    end
end
%% 2. Automatically construct Simscape Multibody model
mdl_h = smimport(multibody_xml_file);
modelname = get_param(mdl_h,'Name');

%% 3. Adjust default settings (gravity, logging, etc.)
% Enable Simscape Logging
set_param(modelname,'SimscapeLogType','All');

% 4. Run simulation
%sim(modelname);

%% 5. Add actuation
jnt_h = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,'RegExp','on','ReferenceBlock','sm_lib/Joints/.*');
for i=1:length(jnt_h)
    set_param(jnt_h{i},'TorqueActuationMode','ComputedTorque','MotionActuationMode','InputMotion');
end

add_block('simulink/Sources/Sine Wave',[modelname '/Sine Wave deg'],...
    'Position',[135 1480 165 1510],...
    'Amplitude','35',...
    'Frequency','2*pi*0.5/10');

add_block('simulink/Sources/Sine Wave',[modelname '/Sine Wave mm'],...
    'Position',[135 1550 165 1580],...
    'Amplitude','35',...
    'Frequency','2*pi*0.5/10');

if ~verLessThan('matlab', '9.2')
add_block('nesl_utility/Simulink-PS Converter',[modelname '/Simulink-PS Converter deg'],...
    'Position',[240 1480 270 1510],...
    'Unit','deg',...
    'FilteringAndDerivatives','filter',...
    'SimscapeFilterOrder','2');
else
add_block('nesl_utility/Simulink-PS Converter',[modelname '/Simulink-PS Converter deg'],...
    'Position',[240 1480 270 1510],...
    'Unit','deg',...
    'InputFiltering','on',...
    'SimscapeFilterOrder','2');
end

add_line(modelname,'Sine Wave deg/1','Simulink-PS Converter deg/1')

if ~verLessThan('matlab', '9.2')
add_block('nesl_utility/Simulink-PS Converter',[modelname '/Simulink-PS Converter mm'],...
    'Position',[240 1550 270 1580],...
    'Unit','mm',...
    'FilteringAndDerivatives','filter',...
    'SimscapeFilterOrder','2');
else
add_block('nesl_utility/Simulink-PS Converter',[modelname '/Simulink-PS Converter mm'],...
    'Position',[240 1550 270 1580],...
    'Unit','mm',...
    'InputFiltering','on',...
    'SimscapeFilterOrder','2');
end

add_line(modelname,'Sine Wave mm/1','Simulink-PS Converter mm/1','autorouting','on')

for i=1:length(jnt_h)
    blkname = get_param(jnt_h{i},'Name');
    if strfind(get_param(jnt_h{i},'ReferenceBlock'),'Revolute')
        add_line(modelname,'Simulink-PS Converter deg/RConn1',[blkname '/Lconn2'],'autorouting','on')
    elseif strfind(get_param(jnt_h{i},'ReferenceBlock'),'Prismatic')
        add_line(modelname,'Simulink-PS Converter mm/RConn1',[blkname '/Lconn2'],'autorouting','on')
    end
end

%% 6. Run simulation
sim(modelname);


