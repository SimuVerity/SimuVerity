function modelName = checkModel(modelName)
%% Description:
% This function checks if the model with name modelName is already loaded,
% otherwise it loads it. The function also checks if the model has unsaved
% changes to see if it should reset the model workspace to its original
% value

%% Input:
% modelName: [1x1 char]: Name of the model

%-----------------
% Copyright 2023-2025 The MathWorks, Inc.
%-----------------

% Check if model is loaded
if(~bdIsLoaded(modelName))
    open_system(modelName); 
end

% Check if model has unsaved changes. If this is the case, turn off Fast Restart and reload the model workspace
if bdIsDirty(modelName)

    % Reset model workspace to default values
    set_param(modelName, 'FastRestart', 'off');
    modelWS = get_param(modelName, 'modelworkspace'); 
    modelWS.reload;

end

% Set model to fast restart 
set_param(modelName, 'FastRestart', 'on');

end


