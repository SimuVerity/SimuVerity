% Script to run (instead of edit) CVT design app
% and ensure only one copy of the UI is opened.

% Copyright 2019-2025 The MathWorks, Inc.

if(exist('CVT_Calculate_Swash_Control_app_uifigure','var'))
    if(~isempty(CVT_Calculate_Swash_Control_app_uifigure))
        if(length(CVT_Calculate_Swash_Control_app_uifigure.findprop('PowerSplitCVTDesign'))==1)
            % Figure is already open, bring it to the front
            figure(CVT_Calculate_Swash_Control_app_uifigure.PowerSplitCVTDesign);
        else
            % Open UI again and store figure handle
            CVT_Calculate_Swash_Control_app_uifigure = CVT_Calculate_Swash_Control_app;
        end
    else
        % Open UI again and store figure handle
        CVT_Calculate_Swash_Control_app_uifigure = CVT_Calculate_Swash_Control_app;
    end
else
    % Open UI again and store figure handle
    CVT_Calculate_Swash_Control_app_uifigure = CVT_Calculate_Swash_Control_app;
end
