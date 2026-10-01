% Copyright 2008-2013 The MathWorks, Inc.

%% Prepare Alternator

% Set up variants
AlternatorSelection = 1;
Alternator_80A_LUT  = Simulink.Variant('AlternatorSelection == 1');
Alternator_100A_LUT = Simulink.Variant('AlternatorSelection == 2');
Alternator_80A_MBC  = Simulink.Variant('AlternatorSelection == 3');
Alternator_100A_MBC = Simulink.Variant('AlternatorSelection == 4');

% Load LUT data
load AlternatorTableData.mat

