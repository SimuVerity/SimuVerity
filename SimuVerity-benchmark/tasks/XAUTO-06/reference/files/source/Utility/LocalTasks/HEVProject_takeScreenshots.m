%% Take screenshots of models

% Taking screenshot with `screenshotSimulink` uses `print` function.
% `print` is not supported in `-nodisplay` option for MATLAB.
% `-nodisplay` option is used in CI.
% Thus, running this in CI causes failure in CI process.

% Copyright 2023 The MathWorks ,Inc.

%%

open_system("PowerSplitHEV_system_model")

% Update model for a screenshot.
set_param("PowerSplitHEV_system_model", SimulationCommand = "update")

screenshotSimulink( ...
  SimulinkModelName = "PowerSplitHEV_system_model", ...
  SaveFolder = currentProject().RootFolder + "/Utility", ...
  OutputImageWidth_px = 700 );

img = imread(currentProject().RootFolder + "/Utility/image_PowerSplitHEV_system_model.png");

imshow(img)
