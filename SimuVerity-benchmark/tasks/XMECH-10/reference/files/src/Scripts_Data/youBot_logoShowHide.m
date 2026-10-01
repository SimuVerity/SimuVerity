function youBot_logoShowHide(modelname,showOrHide)

imageFileList = {...
    'youBot_Arm_Forearm_IMAGE','.jpg';...
    'youBot_Arm_Pivot_IMAGE','.jpg';...
    'youBot_Arm_System_IMAGE','.jpg';...
    'youBot_Arm_System_demoScript_IMAGE','.jpg';...
    };

subsystemList = {...
    'Pivot_Black_Inlay_1_RIGID',...
    'Forearm_Black_Inlay_1_RIGID',...
    };

for file_i=1:length(imageFileList)
    baseFileName = imageFileList{file_i,1};
    baseFileExt = imageFileList{file_i,2};
    [imgDir,~,~] = fileparts(which([baseFileName baseFileExt]));
    
    if(strcmpi(showOrHide,'show'))
        copyfile([imgDir filesep baseFileName '_withLogo' baseFileExt],[imgDir filesep baseFileName baseFileExt]);
    else
        copyfile([imgDir filesep baseFileName '_noLogo' baseFileExt],[imgDir filesep baseFileName baseFileExt]);
    end
end

for sub_i = 1:length(subsystemList)
    sub_h = find_system(modelname,'MatchFilter',@Simulink.match.allVariants,...
        'IncludeCommented','on','Name',subsystemList{sub_i});
    if(strcmpi(showOrHide,'show'))
        set_param(char(sub_h),'Commented','off');
    else
        set_param(char(sub_h),'Commented','on');
    end
end
