% Script for testing Dual_Clutch_Trans and publishing results
% Copyright 2012-2025 The MathWorks, Inc.

mdl_list = {...
    'Dual_Clutch_Trans',...
    };

% Loop over models with publish script
for mdl_list_i = 1:length(mdl_list)
    
    % Move to folder with publish scripts
    cd(fileparts(which(mdl_list{mdl_list_i})))
    cd('Overview')
    
    % Close main model to avoid shadowing error
    bdclose(mdl_list{mdl_list_i});
    
    % Loop over publish scripts
    filelist_m=dir('*.m');
    filenames_m = {filelist_m.name};
    warning('off','Simulink:Engine:MdlFileShadowedByFile');
    for filenames_m_i=1:length(filenames_m)
        publish(filenames_m{filenames_m_i},'showCode',false)
    end    
end

clear filelist_m filenames_m filenames_m_i 
clear mdl_list mdl_list_i

bdclose all
close all

sweepList = {...
    'DCT_Parameter_Sweep_1D',...
    'DCT_Parameter_Sweep_2D_para',...
    'DCT_Parameter_Sweep_2D_series'...
   };

for sweepList_i = 1:length(sweepList)

    % Move to folder with publish scripts
    cd(fileparts(which(sweepList{sweepList_i})))

    bdclose all
    close all

    publish(sweepList{sweepList_i},'showCode',false)
end

bdclose all
close all

optimList = {...
    'find_min_fuel_1D',...
    'find_min_fuel_2D',...
    'find_min_fuel_ps2D',...
    'find_min_fuel_psMX_series',...
    'find_min_fuel_psMX_para'};

for optimList_i = 1:4%length(optimList)

    % Move to folder with publish scripts
    cd(fileparts(which(optimList{optimList_i})))

    bdclose all
    close all

    publish(optimList{optimList_i},'showCode',false)
end
