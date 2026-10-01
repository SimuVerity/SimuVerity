function [] = maskExprHandling(blk_h, config)
% MASKEXPRHANDLING handles expressions in mask parameter fields of blk_h.
% 
%   This function should be called from the 'Initialize commands' section
%   of a mask. It provides a workaround for the restriction of Simulink
%   regarding code export with tunable parameters of datatype single in
%   combination with expressions in mask parameter fields (See also [1]).
%   For further information please have a look at the README [2].
% 
% Inputs:
%   blk_h       Handle to the block with a mask that is calling this
%               function in his mask 'Initialize commands'
%   config      Configuration parameter that must be added to the
%               mask of the calling block (see [2])
% 
% Outputs:
%   -
% 
% See also:
%   MASKEXPRHANDLINGADD2BLOCK
% 
% Literature:
%   [1] https://www.mathworks.com/help/rtw/ug/limitations-for-block-parameter-tunability-in-the-generated-code.html
%   [2] https://github.com/iff-gsc/m-Utils/tree/main/simulink/mask_expression_handling/README.md

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************



%% Config
% The following configuration must match the configuration in
% 'maskExprHandlingAdd2Block.m'

group_box.name = 'CodeGenerationSettings';

config_par.name = 'mask_expr_handling_config';    
config_par.type_opts = {'default', 'passthrough (tunable)'};

init_fcn.name = 'maskExprHandling';    % hardcoded function name, must be changed if function name changes!
% init_fcn.name = mfilename;
init_fcn.args = {'gcbh', config_par.name};



% Exclude some blocks to get faster processing

% Single parameter excludes
%  - Not sure if 'Reshape' and 'Selector' never use configuration parameters!
excludes.BlockType = {'BusCreator', 'BusSelector', 'Inport', 'Outport', 'Terminator', 'Mux', 'Demux', 'Sum', 'Reshape', 'Selector'};

% Combined parameter excludes
combination_excludes = {{'BlockType', 'SubSystem'; ...
                         'Mask', 'off'}};



%% ToDo (things that can be improved or reviewed in the future):
% - At the moment there is no check, if a block which should be changed
%   is part of a library functional mask (a mask without dialog
%   parameters which is a library block). The library functional mask
%   above such a block must be self modifieable and this could be checked
%   in the future and provided with its own error message. For the reason
%   that I believe a library functional mask is not very usefull at all,
%   this is not implementet yet...
%
% - Also try callback function implementation and memory block as
%   alternative method to this?!
%
% - Add a check if we have a scalar variable or an multidimensional
%   variable. If the mask parameter is multidimensional, this method can
%   probably not be used!
%
% - Use getfullnameWithoutLinebreak and getLink2Block functions?
%   Does it have an performance impact?



%% Check if mask expression handling is fully implemented in this mask
checkMask(blk_h, group_box, config_par, init_fcn)


% Select only mask parameters that contain expressions with variables
msk = get_param(blk_h, 'MaskObject');    % faster than 'msk = Simulink.Mask.get(blk_h);'
msk_parameters = msk.Parameters;

idxs_bool = false(size(msk_parameters));
for idx = 1:numel(msk_parameters)
    msk_par = msk_parameters(idx);
    
    if  strcmp(msk_par.Type, 'edit') && ...
        ~strcmp(msk_par.Tunable, 'off') && ...
        strcmp(msk_par.Evaluate, 'on')
        if isExprWithVar(msk_par.Value)
            idxs_bool(idx) = true;
        end
    end        
end

msk_pars = {msk_parameters(idxs_bool).Name};
msk_pars_vals = {msk_parameters(idxs_bool).Value};



% Find all subblocks
f_opts = Simulink.FindOptions;
f_opts.FollowLinks = true;
f_opts.LookUnderMasks = 'functional';
f_opts.IncludeCommented = false;

subblks_h = Simulink.findBlocks(blk_h, f_opts);


% Filter found subblocks based on excludes

% excludes
exclude_pars = fieldnames(excludes);
idxs_bool = true(size(subblks_h));
for blk_idx = 1:numel(subblks_h)
    subblk_h = subblks_h(blk_idx);
    
    for excl_idx = 1:numel(exclude_pars)
        excl_par = exclude_pars{excl_idx};
        val = get_param(subblk_h, excl_par);
        
        if any(strcmp(val, excludes.(excl_par)))
            idxs_bool(blk_idx) = false;
            break;
        end
    end
end
subblks_h = subblks_h(idxs_bool);

% combination excludes
idxs_bool = true(size(subblks_h));
for blk_idx = 1:numel(subblks_h)
    subblk_h = subblks_h(blk_idx);
    
    for excl_idx = 1:numel(combination_excludes)
        comb_exclude = combination_excludes{excl_idx};
        
        matches = false(size(comb_exclude, 1), 1);
        for cmb_idx = 1:size(comb_exclude,1)
            val = get_param(subblk_h, comb_exclude{cmb_idx, 1});
            matches(cmb_idx) = strcmp(comb_exclude{cmb_idx, 2}, val);
        end
        
        if all(matches)
            idxs_bool(blk_idx) = false;
            break;
        end
    end
end
subblks_h = subblks_h(idxs_bool);



% config_val = get_param(blk_h, config_par.name); % We use the input argument here...
config_val = config;    % 'Evaluate' of this popup parameter must be off, otherwise a number is returned!
switch config_val
    
    % default
    case config_par.type_opts{1}
        
        for idx = 1:numel(msk_pars)
            param = msk_pars{idx};
            param_val = ['(' msk_pars_vals{idx} ')'];
            
            result_ireg = findBlocksUsingPar(subblks_h, param_val, param);
            
            for idx2 = 1:numel(result_ireg)
                subblk_h = result_ireg(idx2).blk_h;
                matches = result_ireg(idx2).matches;
                
                % handle mask
                if strcmp(get_param(subblk_h, 'Mask'), 'on')
                    
                    % it must be checked whether the mask has
                    % mask expression handling implemented
                    checkMask(subblk_h, group_box, config_par, init_fcn);
                    
                    % set mask of subblock to 'default' (but only if it is not already on default)
                    subblk_h_config_val = get_param(subblk_h, config_par.name);
                    if ~strcmp(subblk_h_config_val, config_par.type_opts{1})
                        set_param(subblk_h, config_par.name, config_par.type_opts{1});
                    end
                end
                
                % replace all found block parameters with new values
                for idx3 = 1:numel(matches)
                    set_param(subblk_h, matches(idx3).blk_par, matches(idx3).blk_par_rep);
                end
            end
            
            if ~isempty(result_ireg)
                enableMaskPars(blk_h, {param});
            end
        end
        
    % tunable (passthrough)
    case config_par.type_opts{2}
        
        for idx = 1:numel(msk_pars)
            param = msk_pars{idx};
            param_val = ['(' msk_pars_vals{idx} ')'];
            
            result_reg = findBlocksUsingPar(subblks_h, param, param_val);
            
            for idx2 = 1:numel(result_reg)
                subblk_h = result_reg(idx2).blk_h;
                matches = result_reg(idx2).matches;
                
                % handle mask
                if strcmp(get_param(subblk_h, 'Mask'), 'on')
                    
                    % it must be checked whether the mask has
                    % mask expression handling implemented
                    checkMask(subblk_h, group_box, config_par, init_fcn);
                    
                    % set mask of subblock to 'default' (but only if it is not already on default)
                    subblk_h_config_val = get_param(subblk_h, config_par.name);
                    if ~strcmp(subblk_h_config_val, config_par.type_opts{1})
                        set_param(subblk_h, config_par.name, config_par.type_opts{1});
                    end
                    
                    % replace all found block parameters with new values
                    for idx3 = 1:numel(matches)
                        set_param(subblk_h, matches(idx3).blk_par, matches(idx3).blk_par_rep);
                    end
                    
                    % set mask of subblock back to 'tunable'
                    set_param(subblk_h, config_par.name, config_par.type_opts{2});
                    
                % handle any other block
                else
                    % replace all found block parameters with new values
                    for idx3 = 1:numel(matches)
                        set_param(subblk_h, matches(idx3).blk_par, matches(idx3).blk_par_rep);
                    end
                end
            end
            
            if ~isempty(result_reg)
                disableMaskPars(blk_h, {param});
            end
        end
    otherwise
        error('This should not happen and is a bug!')
end

end








%% LOCAL FUNCTIONS
function enableMaskPars(blk, msk_pars)
    mask_names = get_param(blk, 'MaskNames');
    mask_enables = get_param(blk, 'MaskEnables');
    
    for idx = 1:numel(msk_pars)
        idxs = strcmp(mask_names, msk_pars{idx});
        mask_enables{idxs} = 'on';
    end
    
    set_param(blk, 'MaskEnables', mask_enables);
end



function disableMaskPars(blk, msk_pars)
    mask_names = get_param(blk, 'MaskNames');
    mask_enables = get_param(blk, 'MaskEnables');
    
    for idx = 1:numel(msk_pars)
        idxs = strcmp(mask_names, msk_pars{idx});
        mask_enables{idxs} = 'off';
    end
    
    set_param(blk, 'MaskEnables', mask_enables);
end



function checkMask(blk, group_box, config_par, init_fcn)
% Checks:
% - has blk a mask?
% - does group box container 'group_box.name' exist?
% - does mask parameter config_par.name exist?
%   - does parameter config_par.name contain the options config_par.type_opts?
% - do mask 'Initialize commands' contain a function call to init_fcn.name with the correct arguments?
% - is library block self modifiable?

    blk_p = getfullname(blk);
    
    msg_error = char.empty;
    
    msk = get_param(blk, 'MaskObject');    % faster than 'msk = Simulink.Mask.get(blk);'
    
    if isempty(msk)
        msg = ' - Block has no mask\n';
        msg_error = [msg_error, msg];
        
    else
        group_box_msk = msk.getDialogControl(group_box.name);
        config_par_msk = msk.getParameter(config_par.name);
        
        % check mask dialog control
        if isempty(group_box_msk)
            msg = sprintf(' - Mask group box container ''%s'' not implemented\n', group_box.name);
            msg_error = [msg_error, msg];
        end
        
        % check mask parameters
        msg_error = checkMaskParameter(config_par, config_par_msk, msg_error);
        
        % check mask initialization
        if nargin==4
            init_code = msk.Initialization;
            
            % check if function call exists
            init_fcn_call = regexp(init_code, ['(' init_fcn.name ')\(([^;]*)\);'], 'tokens');
            
            if isempty(init_fcn_call)
                msg = sprintf(' - Function call to ''%s(<args>)'' not implemented in initialization section\n', init_fcn.name);
                msg_error = [msg_error, msg];
            elseif numel(init_fcn_call) > 1
                msg = sprintf(' - Multiple function calls to ''%s(<args>)'' found in initialization section\n', init_fcn.name);
                msg_error = [msg_error, msg];
            else
                % check function arguments
                init_fcn_args = regexp(init_fcn_call{1}{2}, '[\w()]*', 'match');
                
                if any(~strcmp(init_fcn_args(:), init_fcn.args(:)))
                    msg = sprintf(' - Wrong function arguments for ''%s(<args>)'' in initialization section\n', init_fcn.name);
                    msg_error = [msg_error, msg];
                end
            end
        end
        
        % check if mask is self modifiable
        if strcmp(get_param(blk, 'StaticLinkStatus'), 'resolved')
            if strcmp(get_param(blk, 'MaskSelfModifiable'), 'off')
                msg = sprintf(' - Library block is not self modifiable');
                msg_error = [msg_error, msg];
            end
        end
        
    end
    
    
    % print error message
    if ~isempty(msg_error)
        msg_header = '<strong>Mask Expression Handling</strong> is not correctly implemented in ''%s''\n';
        
        % print detailed error message to Simulink Diagnostic Viewer
        blk_link = sprintf('<a href = "matlab:hilite_system(''%1$s'')">%1$s</a>', regexprep(blk_p, '\n', ' '));
        msg = [sprintf(msg_header, blk_link), msg_error];
        sldiagviewer.reportError(msg);
        
        % raise error
        error('Error in Mask Expressions Handling. Please check Simulink Diagnostic Viewer for further information!')
    end
end



function msg = checkMaskParameter(par, par_msk, msg)
    if isempty(par_msk)
        msg_local = sprintf(' - Mask parameter ''%s'' not implemented\n', par.name);
        msg = [msg, msg_local];
        return;
    end
    
    if ~strcmp(par_msk.Type, 'popup')
        msg_local = sprintf(' - Mask parameter ''%s'' has wrong type ''%s''\n', par.name, par_msk.Type);
        msg = [msg, msg_local];
        return;
    end
    
    if numel(par_msk.TypeOptions) ~= numel(par.type_opts) || any(~strcmp(par_msk.TypeOptions(:), par.type_opts(:)))
        msg_local = sprintf(' - Mask parameter ''%s'' has wrong type options\n', par.name);
        msg = [msg, msg_local];
    end
end
