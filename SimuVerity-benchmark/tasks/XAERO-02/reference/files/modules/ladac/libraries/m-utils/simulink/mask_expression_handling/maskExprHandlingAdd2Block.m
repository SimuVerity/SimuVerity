function maskExprHandlingAdd2Block(blk)
% MASKEXPRHANDLINGADD2BLOCK adds mask expression handling to block.
% 
%   This function adds a the 'mask expression handling' routine to the
%   mask of the given block. Mask expression handling is only needed for
%   code export with tunable parameters of datatype single in combination
%   with expressions in mask parameter fields (See also [1]).
%   For further information please have a look at the README [2].
% 
% Inputs:
%   blk         Handle or path to a Simulink block that has a mask
% 
% Outputs:
%   -
% 
% See also:
%   MASKEXPRHANDLING
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
% 'maskExprHandling.m'

group_box.prompt = 'Code Generation Settings';
group_box.name = 'CodeGenerationSettings';

config_par.prompt = 'Mask expression handling';
config_par.name = 'mask_expr_handling_config';
config_par.type_opts = {'default', 'passthrough (tunable)'};

readme.prompt = 'README';
readme.name = 'Readme';
readme.url = 'https://github.com/iff-gsc/m-Utils/tree/main/simulink/mask_expression_handling/README.md';

init_fcn.name = 'maskExprHandling';
init_fcn.args = {'gcbh', config_par.name};



%% ToDo:
% - This tool does not check, if a subblock with mask, but without any mask
%   parameters uses parameters of the blk mask (top level mask) in it's
%   subblocks. If that is the case and the subblock with mask is a library
%   block, it must be self modifiable!
%   At the moment, subblocks with a mask but without mask parameters are
%   not further processed.
% - Add 'override' option, that overrides everything without asking
% - Add 'remove' option, thate removes 'Mask Expression Handling'
    
    
    
%% Input checks and model loading
if isnumeric(blk)
    if ishandle(blk)
        blk_h = blk;
        blk_p = getfullname(blk);
    else
        error('Input is not a valid handle!')
    end
elseif ischar(blk) || isStringScalar(blk)
    blk_p = blk;
    blk_h = getSimulinkBlockHandle(blk, true);
    if blk_h == -1
        error('''%s'' could not be loaded!', blk)
    end
    if ~strcmp(blk, gcb)
        hilite_system(blk)
    end
else
    error('Wrong input! Please input a Simulink block path or handle')
end

blk_root_h = bdroot(blk_h);
blk_root_p = bdroot(blk_p);
blk_root_islib = bdIsLibrary(blk_root_p);
blk_root_isdirty = bdIsDirty(blk_root_p);

% Remove \n (newline) from the paths
blk_p = regexprep(blk_p, '\n', ' ');
blk_root_p = regexprep(blk_root_p, '\n', ' ');



%% Block checks

% check if block has a mask
blk_msk = get_param(blk_h, 'MaskObject');    % faster than 'blk_msk = Simulink.Mask.get(blk_h);'
if isempty(blk_msk)
    blk_link = getLink2Block(blk_p);
    error('''%s'' has no Mask!', blk_link);
end


% check if mask has parameters
msk_parameters = blk_msk.Parameters;
if isempty(msk_parameters)
    blk_link = getLink2Block(blk_p);
    error('''%s'' has a Mask, but no MaskParameters. It makes no sense to add expression handling to a Mask without parameters.', blk_link);
end


% check the blocks library state
blk_link_status = get_param(blk_h, 'LinkStatus');
blk_libinfo = getBlockLibinfo(blk_h);
[parent_libs, ~] = getBlockLibAnalysis(blk_h);

% ToDo: Check if unresolved is possible or not!

if any(strcmp(blk_link_status, {'resolved', 'unresolved'}))
    blk_link = getLink2Block(blk_p);
    lib_link = getLink2Block(blk_libinfo.ReferenceBlock);
    
    error('''%s'' is a link to a library block!\nPlease work directly on the library block ''%s'' or disable the link to the library.', blk_link, lib_link);
    
elseif any(strcmp(blk_link_status, {'inactive'}))
    blk_link = getLink2Block(blk_p);
    lib_link = getLink2Block(blk_libinfo.ReferenceBlock);
    
    warning('''%s'' is a disabled link to a library block!\nPlease work directly on the library block ''%s'' if you want to make changes to the library.', blk_link, lib_link);
    if ~getUserConfirmationn()
        return
    end
    
elseif strcmp(blk_link_status, 'implicit')
    blk_link = getLink2Block(blk_p);
    parent_link = getLink2Block(parent_libs(1).Block);
    parent_lib_link = getLink2Block(parent_libs(1).ReferenceBlock);
    
    error('''%s'' is part of a library block!\nPlease work directly in the library ''%s'' or disable the link to the library for ''%s''.', blk_link, parent_lib_link, parent_link);        
end
    
    
% check if block is part of a block with a disabled link to a library
% (this could be unwanted)
if ~isempty(parent_libs)
    blk_link = getLink2Block(blk_p);
    disabled_parent_link = getLink2Block(parent_libs(1).Block);
    
    warning('''%s'' is member of a block with disabled library link ''%s''', blk_link, disabled_parent_link)
    if ~getUserConfirmationn()
        return
    end
end




%% Prepare to add mask expression handling
fprintf('\n<strong>Adding mask expression handling to:</strong>\n''%s'' (hereinafter referred to as ''base block'')\n', getLink2Block(blk_p));

% Block diagram checks
if blk_root_islib
    blk_root_spec = 'library';
else
    blk_root_spec = 'model';
end

fprintf('\nWorking on the %s ''%s''\n', blk_root_spec, getLink2bdroot(blk_root_p));

if blk_root_isdirty
    prompt = sprintf('\n%s already has unsaved changes. Do you really want to continue?', [upper(blk_root_spec(1)), blk_root_spec(2:end)]);
    if ~getUserConfirmation(prompt)
        return
    end
end

if blk_root_islib
    if strcmp(get_param(blk_root_p, 'Lock'), 'on')
        fprintf(' - Library is locked\n - Unlocking library\n')
        set_param(blk_root_p, 'Lock', 'off');
    end
end



%% Add mask expression handling to mask
fprintf('\n');
is_change = false;


% Add configuration dialog
group = blk_msk.getDialogControl(group_box.name);

is_override = false;
if ~isempty(group)
    prompt = 'Mask already contains the required group box container. Do you want to override?';
    is_override = getUserConfirmation(prompt);
    
    if is_override
        % delete existing group box and all children
        maskRemoveAllNestedDialogElements(blk_msk, group);
        statement = ' - Overriding group box container and all child elements\n';
    end
else
    statement = ' - Adding group box container and parameters to mask\n';
end

if isempty(group) || is_override
    is_change = true;
    fprintf(statement);
    
    % add group box (this is the parent element)
    group = blk_msk.addDialogControl('Name', group_box.name, ...
                                     'Type', 'group', ...
                                     'Prompt', group_box.prompt, ...
                                     'AlignPrompts', 'off');
    
    % add description
    group.addDialogControl('Name', [init_fcn.name 'Text'], ...
                           'Prompt', config_par.prompt, ...
                           'Type', 'text', ...
                           'WordWrap', 'off', ...
                           'Row', 'new', ...
                           'HorizontalStretch', 'off');

    % add hyperlink to readme
    web_callback = sprintf('web(''%s'',''-browser'')', readme.url);
    group.addDialogControl('Name', [init_fcn.name readme.name], ...
                           'Prompt', readme.prompt, ...
                           'Type', 'hyperlink', ...
                           'Callback', web_callback, ...
                           'Tooltip', readme.url, ...
                           'Row', 'current', ...
                           'HorizontalStretch', 'off');
    
    % add configuration parameter
    blk_msk.addParameter('Name', config_par.name, ...
                         'Prompt', '', ...
                         'Type', 'popup', ...
                         'TypeOptions', config_par.type_opts, ...
                         'Value', config_par.type_opts{1}, ...
                         'Evaluate', 'off', ...    % Evaluate has a different meaning for mask parameters of type popup. This defines, if the value is a number or a string.
                         'Tunable', 'on', ...      % We need tunable to be on, because otherwise 'Mask Expression Handling' settings can not be changed without breaking the library link when this block is part of a library block.
                         'Visible', 'on', ...
                         'Container', group_box.name);
    par = blk_msk.getParameter(config_par.name);
    dia_cntrl = par.DialogControl;
    dia_cntrl.PromptLocation = 'left';
    dia_cntrl.HorizontalStretch = 'on';
    
else
    fprintf(' - Doing nothing!\n');
end


% Add initialization code
fprintf('\n');
init_code = get_param(blk_h, 'MaskInitialization');    % faster than 'init_code = blk_msk.Initialization'

% check if function call exists
init_fcn_call = regexp(init_code, ['(' init_fcn.name ')\(([^;]*)\);'], 'tokens');

if numel(init_fcn_call) > 1
    error('Multiple function calls to ''%s(<args>)'' found in initialization section. Please fix manually!', init_fcn.name');
end

if ~isempty(init_fcn_call)
    % check function arguments
    init_fcn_args = regexp(init_fcn_call{1}{2}, '[\w()]*', 'match');
    
    if any(~strcmp(init_fcn_args(:), init_fcn.args(:)))
        fprintf('Mask already contains the required function call, but has wrong function arguments. We must override!\n');
        is_override = true;
    else
        prompt = sprintf('Mask already contains the required function call. Do you want to override?');
        is_override = getUserConfirmation(prompt);
    end

    if is_override
        % delete existing function call
        init_code = regexprep(init_code, [init_fcn.name '\([^;]*\);'], '');
        statement = ' - Overriding function call in mask initialization section\n';
    end
else
    statement = ' - Adding function call to mask initialization section\n';
end

if isempty(init_fcn_call) || is_override
    is_change = true;
    fprintf(statement);
    
    args = strjoin(init_fcn.args, ', ');
    init_fcn.call = sprintf('%s(%s)', init_fcn.name, args);
    if isempty(init_code)
        init_code = [init_fcn.call ';'];
    else
        init_code = sprintf('%s\n\n%s;', init_code, init_fcn.call);
    end
    set_param(blk_h, 'MaskInitialization', init_code);
else
    fprintf(' - Doing nothing!\n');
end



% Make mask self modifiable if block is part of a library
if blk_root_islib
    msk_self_mod = get_param(blk_h, 'MaskSelfModifiable');
    if strcmp(msk_self_mod, 'off')
        is_change = true;
        fprintf(' - Allow mask to modify its content\n');
        set_param(blk_h, 'MaskSelfModifiable', 'on');
    else
        fprintf(' - Mask is already allowed to modify its content. Doing nothing!\n');
    end
end

if is_change
    fprintf('\nPlease make sure to manually save ''%s'' if you want to make the changes permanent!\n', getLink2bdroot(blk_root_p));
end




% Check whether the block contains other masked subblocks that access
% mask parameters of the block
f_opts = Simulink.FindOptions;
f_opts.FollowLinks = true;
f_opts.LookUnderMasks = 'functional';
f_opts.IncludeCommented = false;

subblks_h = Simulink.findBlocks(blk_h, 'Mask', 'on', f_opts);

% Proceed if there are subblocks
if ~isempty(subblks_h)
    
    msk_pars = get_param(blk_h, 'MaskNames');
    msk_pars_type = get_param(blk_h, 'MaskStyles');
    
    % Only consider mask parameters of type 'edit'
    msk_pars = msk_pars(startsWith(msk_pars_type, 'edit'));
    
    % Find blocks using parameters
    idxs_bool = false(size(subblks_h));
    for idx = 1:numel(msk_pars)
        [~, using_par] = findBlocksUsingPar(subblks_h, msk_pars{idx});
        idxs_bool(using_par) = true;
    end
    subblks_to_change_h = subblks_h(idxs_bool);
    
    % Get full path to subblocks
    subblks_p = arrayfun(@(a) getfullnameWithoutLinebreak(a), subblks_h, 'UniformOutput', false);
    
    % Remove blk_p part of paths to generate shorter names
    subblks_p_short = cellfun(@(a) strrep(a, [blk_p '/'], ''), subblks_p, 'UniformOutput', false);
    
    % Print list of subblocks
    to_change = cell(size(subblks_p));
    to_change(~idxs_bool) = {char.empty};
    to_change(idxs_bool) = {'x'};
    
    data = [subblks_p_short, to_change];
    
    data_postprocessing = cell(size(data, 2));
    data_postprocessing{1} = @(a) getLink2Block([blk_p '/' a], ['/' a]);
    data_postprocessing{2} = @(a) bold(a);
    
    fprintf('\nBase block contains the following masked subblocks:\n\n');
    printData({}, data, ...
                'indent', 2,...
                'column_spacing', 2, ...
                'data_postprocessing', data_postprocessing);
    
    
    % Proceed if there are subblocks that should be changed
    if ~isempty(subblks_to_change_h)
    
        % Ask the user if the subblocks with masks should be processed
        fprintf(['\nof which the ones highlighted with an <strong>x</strong> use parameters of the base blocks mask.\n', ...
                    'It is recommended to add mask expression handling at least to the highlighted masked subblocks.\n', ...
                    'This tool supports doing this automatically. It automatically follows the library links if\n', ...
                    'the subblocks are library blocks!\n']);
        
        prompt = sprintf('\nShould mask expression handling also be added to the highlighted blocks?');
        if getUserConfirmation(prompt)
            
            % Check if subblock is a library
            subblks_lib_p = cell(size(subblks_to_change_h));
            idxs_bool = false(size(subblks_to_change_h));
            for idx = 1:numel(subblks_to_change_h)
                subblk_libinfo = getBlockLibinfo(subblks_to_change_h(idx));
                if  ~isempty(subblk_libinfo)
                    idxs_bool(idx) = true;
                    subblks_lib_p(idx) = {subblk_libinfo.ReferenceBlock};
                end
            end
            
            % Separate library subblocks from normal subblocks
            subblks_to_change_h = subblks_to_change_h(~idxs_bool);
            sublibs_to_change_p = subblks_lib_p(idxs_bool);

            % Eliminate duplicates
            sublibs_to_change_p = unique(sublibs_to_change_p);
            
            % Add mask expression handling to all normal subblocks
            for idx = 1:numel(subblks_to_change_h)
                maskExprHandlingAdd2Block(subblks_to_change_h(idx));
            end
            
            % Add mask expression handling to all library subblocks
            for idx = 1:numel(sublibs_to_change_p)
                maskExprHandlingAdd2Block(sublibs_to_change_p{idx});
            end

        end
    end
end

end








%% LOCAL FUNCTIONS
function [parents_libdata, children_libdata] = getBlockLibAnalysis(blk)
% GETBLOCKLIBANALYSIS returns libdata for parent and children blocks of blk
% 
% Inputs:
%   blk                 Handle or path to a Simulink block
% 
% Outputs:
%   parents_libdata     Return structure array of libinfo() for all parent
%                       blocks of blk that have a library status. Parent blocks
%                       without a library link are not included.
%   children_libdata    Return structure array of libinfo() for all children
%                       blocks of blk that have a library status. Children
%                       blocks without a library link are not included.
% 
% See also:
%   LIBINFO 

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************


    % Check if blk is path or handle
    if isnumeric(blk)
        blk_is_handle = true;
    else
        blk_is_handle = false;
    end
    
    
    blk_root = bdroot(blk);
    blk_libinfo = libinfo(blk);
    
    
    % Children libs
    if blk_is_handle
        children_libdata = blk_libinfo(~(blk == [blk_libinfo.Block]));
    else
        children_libdata = blk_libinfo(~(strcmp(blk, {blk_libinfo.Block})));
    end
    
    
    % Parent libs
    temp = fieldnames(blk_libinfo)';
    temp{2,1} = {};
    parents_libdata = struct(temp{:});
    
    % ToDo: this could be changed, so that we only get the libinfo for the
    % whole model (blk_root) once and after that select all results which
    % lay on the path of blk. Special care must be taken for Handle vs Path
    % format.
    while true
        parent = get_param(blk, 'Parent');
        
        if blk_is_handle
            parent = getSimulinkBlockHandle(parent);
            if parent == -1
                break;
            end
        else
            if isempty(parent) || strcmp(blk_root, parent)
                break;
            end
        end
        
        parent_link_status = get_param(parent, 'LinkStatus');
        
        if any(strcmp(parent_link_status, {'resolved', 'unresolved', 'inactive'}))
            parent_libinfo = libinfo(parent); 
            if isempty(parent_libinfo)
                error('This should not happen!')
            end
            parents_libdata = [parents_libdata, parent_libinfo(1)];
        end
        
        blk = parent;
    end
end



function blk_libdata = getBlockLibinfo(blk)
% GETBLOCKLIBINFO returns libdata only for blk and not for additional subblocks.
% 
%   The libinfo() function returns libdata for blk and all subblocks that
%   have a library link. This function returns libdata only for blk. If blk
%   has no library link, the return value is an empty structure.
% 
%   Attention:
%   The field 'Block' of blk_libdata is either the handle or the name to the
%   block. This depends on the state of the input, which can be given as a
%   handle or as a path.
%
% Inputs:
%   blk             Handle or path to a Simulink block
%
% Outputs:
%   blk_libdata     Return structure of libinfo()
% 
% See also:
%   LIBINFO

% Disclaimer:
%   SPDX-License-Identifier: GPL-3.0-only
% 
%   Copyright (C) 2024 Jonas Withelm
%   Copyright (C) 2024 TU Braunschweig, Institute of Flight Guidance
% *************************************************************************


    % Check if blk is path or handle
    if isnumeric(blk)
        blk_is_handle = true;
    else
        blk_is_handle = false;
    end
    
    blk_libdata = libinfo(blk);
    
    if blk_is_handle
        blk_libdata = blk_libdata((blk == [blk_libdata.Block]));
    else
        blk_libdata = blk_libdata((strcmp(blk, {blk_libdata.Block})));
    end
end
