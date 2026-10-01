% Publish all test scripts
% Copyright 2022-2025 The MathWorks, Inc.

warning('off','Simulink:Engine:MdlFileShadowedByFile');
warning('off','Simulink:Harness:WarnABoutNameShadowingOnActivation');
bdclose all

curr_proj = simulinkproject;
homedir   = curr_proj.RootFolder;

%% Publish documentation for Simulink examples
publishFolderList = {...
    ['Models'   filesep 'Vehicle'    filesep 'Overview'],...
    ['Models'   filesep 'CVT'        filesep 'Overview'],...
    ['Models'   filesep 'Driveline'  filesep 'Overview'],...
    ['Workflows' filesep 'CVT_Design' filesep 'Overview'],...
    ['Workflows' filesep 'CVT_Design' filesep 'Libraries' ...
                filesep 'Differential' filesep 'html']...
    }; 

for pf_i = 1:length(publishFolderList)
    cd([homedir filesep publishFolderList{pf_i}])
    filelist_m=dir('*.m');
    filenames_m = {filelist_m.name};
    for i=1:length(filenames_m)
        if ~(strcmp(filenames_m{i},'publish_all_html.m'))
            publish(filenames_m{i},'showCode',false)
        end
    end
end

%% Publish workflow documentation
publishFolderList_wkf = {...
    ['Workflows' filesep 'Point_Cloud_Tire' filesep 'Overview'],...
    ['Workflows' filesep 'Surface_Terrain'  filesep 'Overview']...
    }; 

for pf_i = 1:length(publishFolderList_wkf)
    cd([homedir filesep publishFolderList_wkf{pf_i}])
    filelist_m=dir('*.m');
    filenames_m = {filelist_m.name};
    for i=1:length(filenames_m)
        if ~(strcmp(filenames_m{i},'publish_all_html.m'))
            publish(filenames_m{i},'showCode',true)
        end
    end
end

%% CVT Optimization workflow with code
cd([homedir filesep 'Workflows' filesep 'CVT_Design' filesep 'Overview']);
publish('optim_cvt_power_split_design.m','showCode',true);
cd(homedir)

