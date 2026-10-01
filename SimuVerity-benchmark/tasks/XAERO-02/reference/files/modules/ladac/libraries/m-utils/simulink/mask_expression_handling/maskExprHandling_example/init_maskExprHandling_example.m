% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************


% Fixed-step size
ts = 0.0025;


% Model parameterization (single!)
param.a = single(1.5);
param.b = single(2.7);


open('maskExprHandling_example');


% Model config info
model_pars_data = { ...
    'DefaultUnderspecifiedDataType'; ...
    'DataTypeOverride'; ...
    'DataTypeOverrideAppliesTo'};

fprintf('\n');
for idx = 1:numel(model_pars_data)
    val = get_param(bdroot, model_pars_data{idx});
    fprintf('%s: %s\n', model_pars_data{idx}, val);
end
fprintf('\n');
