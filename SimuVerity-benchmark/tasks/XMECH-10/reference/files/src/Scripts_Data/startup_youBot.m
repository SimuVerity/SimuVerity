% Copyright 2016-2025 The MathWorks(TM), Inc.

%curr_proj = simulinkproject;
%YBT_HomeDir = curr_proj;

YBT_HomeDir = pwd;

if(exist('Libraries')==7)
    cd Libraries
    if((exist('+MyMath')==7) && ~exist('MyMath_lib'))
        ssc_build MyMath
    end
    if(exist('Pace')==7)
        cd Pace
        if((exist('sfun_time.c')) && ~exist('sfun_time.mexw64'))
            mex sfun_time.c
        end
    end
    cd(YBT_HomeDir)
end

youBot_PARAM
web('youBot_Arm_Demo_Script.html');
youBot_Arm
