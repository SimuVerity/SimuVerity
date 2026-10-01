% Shutdown script for youBot_Arm project
% Copyright 2019-2025 The MathWorks(TM), Inc.

% See if custom Simscape Language library exists
temp_MyMathloc = which('MyMath_lib.slx');

% If it exists, move to folder and ssc_clean to remove it
if(~isempty(temp_MyMathloc))
    cd(fileparts(temp_MyMathloc));
    if((exist('+MyMath','dir')) && exist('MyMath_lib.slx','file'))
        ssc_clean MyMath
    end
end
clear temp_MyMathloc
