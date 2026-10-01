% Copyright 2016-2024 The MathWorks(TM), Inc.

%% Change to project root folder
curr_proj = simulinkproject;
cd(curr_proj.RootFolder)

%% Publish examples
model_name_list = {...
    'sm_contact_ball.slx'
    'sm_disk_floor_custom_friction.slx'
    'sm_disk_cyl_on_floor.slx'
    'sm_membrane_ball.slx'
    'sm_ptcld_cyl_on_ramp.slx'
    'sm_point_cloud_steering_wheel.slx'
    'sm_spinning_top_totem.slx'
    'sm_tippe_top.slx'
    'sm_ratchet_pawl.slx'
    'sm_tracked_vehicle_belt.slx'
    'Gripper_2Belts.slx'
    'ball_on_conveyor.slx'
    };

bdclose all

for i=1:length(model_name_list)
    cd(fileparts(which(model_name_list{i})))
    cd('Overview');
    publish_allCodeForHTML
end

cd(fileparts(which('Multibody_Contact_Examples_Demo_Script.m')))
sscRepublishDemoScript('Multibody_Contact_Examples_Demo_Script.m');

function publish_allCodeForHTML
filelist_m=dir('*.m');

filenames_m = {filelist_m.name};

warning('off','Simulink:Engine:MdlFileShadowedByFile');

for i=1:length(filenames_m)
    if ~(strcmp(filenames_m{i},'publish_all_html.m'))
        publish(filenames_m{i},'showCode',false)
    end
end
end