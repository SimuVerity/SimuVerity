function is_bdroot = bdIsRoot(model)
% BDISROOT checks if the input is a handle or a path to a loaded top-level 
%   Simulink model (model root).
% 
% Inputs:
%   model       Handle (numeric) or path (character vector). 
%               Multiple models: numeric array of handles or cell array of
%               character vectors.
% 
% Outputs:
%   is_bdroot   Boolean, indicating whether the input is a loaded top-level
%               Simulink model (true) or not (false)

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************

is_bdroot = false;
try
    bd = bdroot(model);
    if isnumeric(bd)
        is_bdroot = model == bd;
    else
        is_bdroot = strcmp(model, bd);
    end
catch
    % Model is not loaded or input is invalid for bdroot
end

end
