% Script for testing xts_system and publishing results

% Move to folder with publish scripts
curr_proj = simulinkproject;
cd(curr_proj.RootFolder);
cd('Overview')

% Close main model to avoid shadowing error
bdclose('sm_four_bar_optim');

% Loop over publish scripts
filelist_m=dir('*.m');
filenames_m = {filelist_m.name};
warning('off','Simulink:Engine:MdlFileShadowedByFile');
for i=1:length(filenames_m)
    publish(filenames_m{i},'showCode',false)
end

clear curr_proj filelist_m

