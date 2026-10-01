% Copyright 2012-2025 The MathWorks, Inc.
% Select Variants
set_param([bdroot '/Load'],'OverrideUsingVariant','Scissor');
set_param([bdroot '/Actuator'],'OverrideUsingVariant','Standard');
set_param([bdroot '/Valve'],'OverrideUsingVariant','Standard');
set_param([bdroot '/Servo and Controller'],'OverrideUsingVariant','Standard');
set_param([bdroot '/Controller'],'OverrideUsingVariant','Circuit');

% Set parameters
ssc_hydraulic_lift_sethardstop('adjusted');
