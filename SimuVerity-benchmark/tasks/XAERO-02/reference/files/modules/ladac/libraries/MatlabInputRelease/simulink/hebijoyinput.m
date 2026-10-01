function hebijoyinput(block)
    % hebijoyinput is a HebiJoystick implementation for Simulink
    %
    %   hebijoyinput is an alternative to MathWorks's 'Joystick Input'
    %   block from 'Simulink 3D Animation' toolbox. 'hebijoyinput' is based
    %   on 'HebiJoystick'. 'Simulink 3D Animation' toolbox is not required
    %   for usage!
    %
    %   See also:
    %     HebiJoystick (https://github.com/HebiRobotics/MatlabInput)
    %     Level-2 MATLAB S-Function (msfuntmpl)

    % SPDX-License-Identifier: Apache-2.0
    %
    % Copyright (C) 2023 Jonas Withelm
    % Copyright (C) 2023 TU Braunschweig, Institute of Flight Guidance
    
    setup(block);
    
%endfunction
    
    
function setup(block)
    
    %% Register number of dialog parameters
    block.NumDialogPrms = 3;  % joyid
    block.DialogPrmsTunable = {'Nontunable','Nontunable','Nontunable'}; % not tunable during simulation
    
    %% Setup joystick
    joyid = block.DialogPrm(1).Data;
    forcefeed = block.DialogPrm(3).Data;
    
    % initialize joystick
    no_joystick = false;
    try
        joy = HebiJoystick(joyid);
    catch ME
        if strcmp(ME.ExceptionObject.getMessage, 'Joystick is not connected.')
            no_joystick = true;
            warning('No joystick with ID %i connected! Running ''HebiJoystick Input'' with dummy outputs!', joyid);
        else
            rethrow(ME);
        end
    end
    
    % no joystick handling
    if no_joystick
        % fake capabilities of joystick
        caps.Axes = 1;
        caps.Buttons = 1;
        caps.Forces = 0;
    else    
        % read capabilities of joystick
        caps = joy.caps();
        
        % store persistent data
        set_param(block.BlockHandle,'UserData',joy);
    end
    
    
    %% Register number of output ports
    block.NumOutputPorts = 2;
    
    %% Register number of input ports
    if forcefeed && (caps.Forces > 0)
        block.NumInputPorts = 1;
    else
        block.NumInputPorts = 0;
    end
    
    %% Set the output port properties
    block.OutputPort(1).DimensionsMode = 'Fixed';
    block.OutputPort(1).SamplingMode = 'sample';
    block.OutputPort(1).Dimensions = caps.Axes;
    block.OutputPort(1).DatatypeID = 0; % double
    block.OutputPort(1).Complexity = 'Real';
    
    block.OutputPort(2).DimensionsMode = 'Fixed';
    block.OutputPort(2).SamplingMode = 'sample';
    block.OutputPort(2).Dimensions = caps.Buttons;
    block.OutputPort(2).DatatypeID = 0; % double
    block.OutputPort(2).Complexity = 'Real';
    
    if forcefeed && (caps.Forces > 0)
        block.InputPort(1).DimensionsMode = 'Fixed';
        block.InputPort(1).SamplingMode = 'sample';
        block.InputPort(1).Dimensions = caps.Forces;
        block.InputPort(1).DatatypeID = 0; % double
        block.InputPort(1).Complexity = 'Real';
        block.InputPort(1).DirectFeedthrough = false;
    end
    
    %% Set up the continuous states
    block.NumContStates = 0;
    
    %% Set block sample time
    block.SampleTimes = [1/50 0];  % Discrete sample time (50 Hz)
    
    %% Set the block simStateCompliance to default (i.e., same as a built-in block)
    block.SimStateCompliance = 'DefaultSimState';
    
    %% Register methods
    if ~no_joystick
        block.RegBlockMethod('Outputs',     @Outputs);
        block.RegBlockMethod('Terminate',   @Terminate);
    end
    
%endfunction

    
function Outputs(block)

    joy = get_param(block.BlockHandle,'UserData');
    
    caps = joy.caps();

    % read force feedback from block input and send to joystick
    forcefeed = block.DialogPrm(3).Data;
    if forcefeed && (caps.Forces > 0)
        for idx=1:caps.Forces
            joy.force(idx, block.InputPort(idx).Data);
        end
    end
    
    % read axes and buttons from joystick and write to block outputs
    [axes, buttons, ~] = joy.read();
    
    block.OutputPort(1).Data = axes;
    block.OutputPort(2).Data = buttons;
    
%endfunction
    
    
function Terminate(block)

    joy = get_param(block.BlockHandle,'UserData');

    joy.close();
    
%endfunction
