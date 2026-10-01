function implementPortConnectivity(currSys,methodForce)
% This function enables or disables connectivity between Implement
% block and subsystems such as Scenario and Controller based on the
% dropdown option for 'Draft (horizontal) force and vertical force
% computation' parameter in the Implement masked subsystem.

% Copyright 2024 The MathWorks, Inc.

implementSystemPath = currSys;
implementBlockPath = [currSys '/Implement'];
terminatorPath = [currSys '/Terminators'];
converter1Path = [currSys '/Simulink-PS Converter'];
converter2Path = [currSys '/Simulink-PS Converter1'];
bus1Path = [currSys '/Bus Selector'];
bus2Path = [currSys '/Bus Selector1'];
converter1LineHandles = get_param(converter1Path,'LineHandles');
converter2LineHandles = get_param(converter2Path,'LineHandles');
terminatorLineHandles = get_param(terminatorPath,'LineHandles');
terminatorPortHandles = get_param(terminatorPath,'PortHandles');
bus1PortHandle = get_param(bus1Path,'PortHandles');
bus2PortHandle = get_param(bus2Path,'PortHandles');

if strcmp(methodForce.Value, 'Draft force prediction based on ASABE D497.5 standard')
    set_param(implementBlockPath,'parameterization','ForceComputation.Calculate');
    set_param(converter1Path,'commented','off');
    set_param(converter2Path,'commented','off');
    set_param(terminatorPath,'commented','on');

    if (terminatorLineHandles.Inport(1) == -1)
    else
        delete_line(implementSystemPath,bus1PortHandle.Outport(1),terminatorPortHandles.Inport(1));
    end
    if (terminatorLineHandles.Inport(2) == -1)
    else
        delete_line(implementSystemPath,bus2PortHandle.Outport(1),terminatorPortHandles.Inport(2));
    end

    if (converter1LineHandles.RConn == -1)
        add_line(implementSystemPath,'Simulink-PS Converter/RConn1','Implement/LConn1');
    end
    if (converter2LineHandles.RConn == -1)
        add_line(implementSystemPath,'Simulink-PS Converter1/RConn1','Implement/LConn2');
    end

elseif strcmp(methodForce.Value, 'Specify vectors for draft force, vertical force and velocity')
    if (converter1LineHandles.RConn == -1)
    else
        delete_line(implementSystemPath,'Simulink-PS Converter/RConn1','Implement/LConn1');
    end
    if (converter2LineHandles.RConn == -1)
    else
        delete_line(implementSystemPath,'Simulink-PS Converter1/RConn1','Implement/LConn2');
    end
    set_param(converter1Path,'commented','on');
    set_param(converter2Path,'commented','on');
    set_param(terminatorPath,'commented','off');
    if (terminatorLineHandles.Inport(1) == -1)
        add_line(implementSystemPath,bus1PortHandle.Outport(1),terminatorPortHandles.Inport(1),'autorouting','smart');
    end
    if (terminatorLineHandles.Inport(2) == -1)
        add_line(implementSystemPath,bus2PortHandle.Outport(1),terminatorPortHandles.Inport(2),'autorouting','smart');
    end
    set_param(implementBlockPath,'parameterization','ForceComputation.UserInput');
end