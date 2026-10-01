function blkStruct = slblocks
    % This function specifies that the library 'matlabinput_lib'
    % should appear in the Library Browser with the 
    % name 'MatlabInput'

    Browser.Library = 'matlabinput_lib';
    % 'matlabinput_lib' is the name of the library

    Browser.Name = 'MatlabInput';
    % 'MatlabInput' is the library name that appears
    % in the Library Browser

    blkStruct.Browser = Browser;