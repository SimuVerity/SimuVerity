function maskRemoveAllNestedDialogElements(mask, dialog_element, is_recursion)
% MASKREMOVEALLNESTEDDIALOGELEMENTS Recursively removes all children /
% members of a given mask container (e. g. Group box, Tab, etc.).
% 
% Inputs:
%   mask            Object of type 'Simulink.Mask' class ([1])
%   dialog_element  Object and subobjects of type 'Simulink.dialog'.
%                   Have a look at 'Further Information'
% 
% Outputs:
%   -
%
% Literature:
%   [1] https://www.mathworks.com/help/simulink/slref/simulink.mask-class.html

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************



% Further Information:
% 'Simulink.dialog.<type> -> <type>: Group, Panel, etc.
%   -> Can contain 'DialogControls' that contain children of this element

% 'Simulink.dialog.parameter.<type>' -> <type>: Edit, Popup, etc.
%   -> Is a mask parameter



if nargin < 3
    is_recursion = false;
    
    % Partial backup of mask parameters configuration is needed,
    % because Simulink deletes some configurations for the
    % remaining parameters when a single parameter is deleted
    % (for whatever unkown reason...)
    
    % Parameters DialogControl members must be backuped if they exist
    
    mask_parameters = mask.Parameters;
    
    pars_config_backup = struct;
    for idx = 1:numel(mask_parameters)
        dia_cntrl = mask_parameters(idx).DialogControl;
        par_name = dia_cntrl.Name;
        
        fnames = fieldnames(dia_cntrl);
        
        for idx2 = 1:numel(fnames)
            dia_cntrl_par = fnames{idx2};
            
            if ~strcmp(dia_cntrl_par, 'Name')
                pars_config_backup.(par_name).(dia_cntrl_par) = dia_cntrl.(dia_cntrl_par);
            end
        end
    end 
end


in_type = class(dialog_element);

if regexp(in_type, 'Simulink\.dialog\.\w*$', 'once')
    % 'in' is a dialog element that could contain children
    
    % Check if this dialog element has children (check if it has the
    % member 'DialogControls')
    has_children = true;
    try
        dialog_controls = dialog_element.DialogControls;
    catch
        has_children = false;
    end
    
    
    if has_children
        sz = numel(dialog_controls);
        
        % We have a shitty problem here: It can happen, that
        % dialog_element.DialogControls changes size directly after
        % deleting a parameter below this level. In such a case, the
        % variable 'dialog_controls' is not valid anymore and contains only
        % deleted handles. So first we can not use the variable
        % 'dialog_controls' to iterate through (instead
        % dialog_element.DialogControls) must be used and second we need to
        % check if idx must be increased or not. Therefore we compare the
        % initial size of dialog_element.DialogControls (sz) with the new
        % size after each iteration.

        for idx = 1:numel(dialog_controls)
            if (sz - numel(dialog_element.DialogControls)) > 0
                idx = idx - (sz - numel(dialog_element.DialogControls));
            end
            maskRemoveAllNestedDialogElements(mask, dialog_element.DialogControls(idx), true);
        end
    end

    if ~mask.removeDialogControl(dialog_element.Name) && ~is_recursion
        % It can happen, that an empty dialog control element below the
        % top level dialog control element can not be deleted (unknown reason).
        % This is probably no problem, because it seems
        % that the top level element can be deleted anyways and also
        % deletes all below dialog elements
        error('Could not remove top level dialog control element ''%s''.', dialog_element.Name);
    end

elseif regexp(in_type, 'Simulink\.dialog\.parameter\.\w*$', 'once')
    % 'in' is a parameter, this is a nesting end. Delete parameter.
    
    if ~mask.removeParameter(dialog_element.Name)
        error('Could not remove mask parameter ''%s''.', dialog_element.Name)
    end
    
else
    error('Input for ''dialog_element'' is of type ''%s'', that is not supported.', in_type);
end



% Restore lost configuration of remaining mask parameters
if nargin < 3
    mask_parameters = mask.Parameters;
    
    for idx = 1:numel(mask_parameters)
        dia_cntrl = mask_parameters(idx).DialogControl;
        par_name = dia_cntrl.Name;
        
        fnames = fieldnames(pars_config_backup.(par_name));
        
        for idx2 = 1:numel(fnames)
            dia_cntrl_par = fnames{idx2};
            
            dia_cntrl.(dia_cntrl_par) = pars_config_backup.(par_name).(dia_cntrl_par);
        end
    end 
end

end
