function youBot_Arm_webopen_file(filename)
% Copyright 2016-2025 The MathWorks, Inc.

if (exist(filename))
    web(filename)
else
    msgbox(['File ' filename ' is not on your path.  It may have been excluded to reduce the size of the folder containing all the supporting files for this example.'],'File not provided');
end

