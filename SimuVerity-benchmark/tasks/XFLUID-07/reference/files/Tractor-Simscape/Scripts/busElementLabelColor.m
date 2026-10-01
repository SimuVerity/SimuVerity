function busElementLabelColor(colorInput,depthLevel)
% This function turns off or on the element label foreground color
% based on user provided input. You can provide colorInput as 'black'
% or 'white' to set the bus element label color.
% You can set depthLevel to 1 to hide bus element label.

% Copyright 2024 The MathWorks, Inc.

searchDepth = Simulink.FindOptions('SearchDepth',depthLevel); % Setting search depth
blockHandle = Simulink.findBlocks(gcs,'BlockType', 'Outport',searchDepth); 
                                           % Finding handle to the bus element

inx = size(blockHandle);

% Setting bus element color
for ind = 1:inx(1)
set_param(blockHandle(ind),'ForegroundColor', colorInput)
end