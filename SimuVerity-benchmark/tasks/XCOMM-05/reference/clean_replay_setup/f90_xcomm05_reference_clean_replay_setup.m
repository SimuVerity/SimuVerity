function f90_xcomm05_reference_clean_replay_setup(taskId, officialScenariosPath, model)
%F90_XCOMM05_REFERENCE_CLEAN_REPLAY_SETUP Force normal reference replay.
arguments
    taskId (1,:) char
    officialScenariosPath (1,:) char %#ok<INUSA>
    model (1,:) char
end

assert(strcmp(taskId, 'F90-XCOMM-05'), ...
    'SimuVerity:ReferenceSetup:TaskMismatch', ...
    'Reference setup was invoked for the wrong task.');
assert(bdIsLoaded(model), ...
    'SimuVerity:ReferenceSetup:ModelNotLoaded', ...
    'XCOMM-05 reference model must be loaded before setup.');
set_param(model, 'SimulationMode', 'normal');
end
