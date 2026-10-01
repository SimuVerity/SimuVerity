function ssc_hydraulic_lift_setdefault(mdl)
% Copyright 2012-2025 The MathWorks, Inc.
set_param([mdl '/Valve'],'OverrideUsingVariant','Custom');
set_param([mdl '/Actuator'],'OverrideUsingVariant','Custom');
set_param([mdl '/Servo and Controller'],'OverrideUsingVariant','Custom');
set_param([mdl '/Load'],'OverrideUsingVariant','Scissor');
set_param([mdl '/Controller'],'OverrideUsingVariant','Circuit');
ssc_hydraulic_lift_setsolver(bdroot,'desktop')
ssc_hydraulic_lift_sethardstop('adjusted');

