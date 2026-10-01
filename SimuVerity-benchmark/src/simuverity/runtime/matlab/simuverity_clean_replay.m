function receipt = simuverity_clean_replay(candidatePath, taskId, publicNamesPath, providerRoot, phasePath, receiptPath, stopTime, referenceSetupPath, referenceSetupEntrypoint, officialScenariosPath, referenceSetupPhase)
%SIMUVERITY_CLEAN_REPLAY Fresh-process candidate closure gate.
% Only public scenario inputs are assigned. The sealed model is never saved.

arguments
    candidatePath (1,:) char
    taskId (1,:) char
    publicNamesPath (1,:) char
    providerRoot (1,:) char
    phasePath (1,:) char
    receiptPath (1,:) char
    stopTime (1,1) double = 0
    referenceSetupPath (1,:) char = ''
    referenceSetupEntrypoint (1,:) char = ''
    officialScenariosPath (1,:) char = ''
    referenceSetupPhase (1,:) char = ''
end

startedAt = char(datetime('now','TimeZone','UTC','Format', ...
    'yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''));
phase = 'startup';
model = '';
referenceSetupUsed = false;
writePhase(phasePath, phase);
cleanup = onCleanup(@() closeLoaded(model)); %#ok<NASGU>
try
    publicNamesDocument = jsondecode(fileread(publicNamesPath));
    assert(isfield(publicNamesDocument, 'task_id') && ...
        string(publicNamesDocument.task_id) == string(taskId) && ...
        isfield(publicNamesDocument, 'public_input_names'), ...
        'SimuVerity:CleanReplay:PublicInputContract', ...
        'Clean replay public-input contract is invalid.');
    publicNames = string(publicNamesDocument.public_input_names(:));
    addpath(providerRoot, '-begin');
    nominalValues = simuverity_public_nominal_inputs( ...
        string(taskId), publicNames);
    assert(isstruct(nominalValues) && isscalar(nominalValues) && ...
        isequal(sort(string(fieldnames(nominalValues))), ...
            sort(publicNames)), ...
        'SimuVerity:CleanReplay:NominalProviderMembership', ...
        'Nominal provider did not return exactly the declared public inputs.');
    for publicIndex = 1:numel(publicNames)
        publicName = char(publicNames(publicIndex));
        assignin('base', publicName, nominalValues.(publicName));
    end

    if ~isempty(referenceSetupPath)
        assert(~isempty(referenceSetupEntrypoint) && ...
            ~isempty(officialScenariosPath) && ...
            any(strcmp(referenceSetupPhase, ...
                {'before_load','after_load_before_update'})), ...
            'SimuVerity:ReferenceSetup:Contract', ...
            'Reference setup binding is incomplete or has an invalid phase.');
    end

    % The optional hook is evaluator-owned and is supplied only while
    % validating an exact reference. Candidate/generation clean replay uses
    % the original seven arguments and never enters either setup branch.
    if strcmp(referenceSetupPhase, 'before_load')
        phase = 'reference_setup_before_load';
        writePhase(phasePath, phase);
        localRunReferenceSetup(referenceSetupPath, ...
            referenceSetupEntrypoint, taskId, officialScenariosPath, ...
            referenceSetupPhase, '');
        referenceSetupUsed = true;
    end

    submissionRoot = fileparts(candidatePath);
    addpath(genpath(submissionRoot), '-begin');
    [~, model] = fileparts(candidatePath);

    phase = 'load';
    writePhase(phasePath, phase);
    load_system(candidatePath);

    if strcmp(referenceSetupPhase, 'after_load_before_update')
        phase = 'reference_setup_after_load_before_update';
        writePhase(phasePath, phase);
        localRunReferenceSetup(referenceSetupPath, ...
            referenceSetupEntrypoint, taskId, officialScenariosPath, ...
            referenceSetupPhase, model);
        referenceSetupUsed = true;
    end

    % Function-style compile is unsupported when a source example persists
    % accelerator mode. Closure validation always uses normal mode in
    % memory and never saves the sealed model.
    set_param(model, 'SimulationMode', 'normal');

    if isfinite(stopTime) && stopTime > 0
        set_param(model, 'StopTime', num2str(stopTime, 17));
    end

    phase = 'update';
    writePhase(phasePath, phase);
    set_param(model, 'SimulationCommand', 'update');

    phase = 'compile';
    writePhase(phasePath, phase);
    feval(model, [], [], [], 'compile');
    feval(model, [], [], [], 'term');

    phase = 'simulate';
    writePhase(phasePath, phase);
    sim(model, 'ReturnWorkspaceOutputs', 'on');

    % Reference setup may open an official MATLAB project.  Close the loaded
    % model first because project shutdown can otherwise terminate MATLAB
    % after a successful helper receipt has already been written.
    if referenceSetupUsed
        closeLoaded(model);
        model = '';
        localCloseReferenceProject();
    end

    phase = 'complete';
    writePhase(phasePath, phase);
    receipt = struct( ...
        'schema', 'simuverity.candidate-clean-replay.v1', ...
        'status', 'CANDIDATE_CLOSURE_PASSED', ...
        'load_passed', true, ...
        'update_passed', true, ...
        'compile_passed', true, ...
        'nominal_simulation_passed', true, ...
        'task_id', taskId, ...
        'public_input_names', publicNames, ...
        'nominal_provider', 'simuverity_public_nominal_inputs', ...
        'reference_setup_used', referenceSetupUsed, ...
        'reference_setup_entrypoint', referenceSetupEntrypoint, ...
        'reference_setup_phase', referenceSetupPhase, ...
        'sealed_candidate_modified', false, ...
        'started_at', startedAt, ...
        'ended_at', char(datetime('now','TimeZone','UTC','Format', ...
            'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''')));
    writeJson(receiptPath, receipt);
catch exception
    % A before-load reference setup may have opened an official project.
    % Clean it on the failure path as well as the success path; otherwise a
    % completed failure receipt can leave `matlab -batch` alive indefinitely.
    failure = exception;
    if referenceSetupUsed
        closeLoaded(model);
        model = '';
        try
            localCloseReferenceProject();
        catch cleanupException
            failure = addCause(cleanupException, exception);
        end
    end
    receipt = struct( ...
        'schema', 'simuverity.candidate-clean-replay.v1', ...
        'status', 'CANDIDATE_CLOSURE_FAILED', ...
        'failed_phase', phase, ...
        'error_identifier', failure.identifier, ...
        'error_message', failure.message, ...
        'reference_setup_used', referenceSetupUsed, ...
        'reference_setup_entrypoint', referenceSetupEntrypoint, ...
        'reference_setup_phase', referenceSetupPhase, ...
        'sealed_candidate_modified', false, ...
        'started_at', startedAt, ...
        'ended_at', char(datetime('now','TimeZone','UTC','Format', ...
            'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''')));
    writeJson(receiptPath, receipt);
    throw(failure);
end
end

function localRunReferenceSetup(setupPath, setupEntrypoint, taskId, ...
        officialScenariosPath, setupPhase, model)
try
    assert(isfile(setupPath) && isfile(officialScenariosPath), ...
        'SimuVerity:ReferenceSetup:Missing', ...
        'Reference setup or official scenarios file is missing.');
    setupDirectory = fileparts(setupPath);
    addpath(setupDirectory, '-begin');
    setupPathCleanup = onCleanup(@() rmpath(setupDirectory)); %#ok<NASGU>
    resolvedSetup = which(setupEntrypoint);
    assert(~isempty(resolvedSetup) && ...
        localSamePath(resolvedSetup, setupPath), ...
        'SimuVerity:ReferenceSetup:EntrypointMismatch', ...
        'Declared reference setup entrypoint does not resolve to its bound file.');
    if strcmp(setupPhase, 'before_load')
        feval(setupEntrypoint, taskId, officialScenariosPath);
    elseif strcmp(setupPhase, 'after_load_before_update')
        assert(~isempty(model) && bdIsLoaded(model), ...
            'SimuVerity:ReferenceSetup:ModelNotLoaded', ...
            'After-load reference setup requires the loaded reference model.');
        feval(setupEntrypoint, taskId, officialScenariosPath, model);
    else
        error('SimuVerity:ReferenceSetup:Contract', ...
            'Unsupported reference setup phase: %s', setupPhase);
    end
    clear setupPathCleanup
catch setupException
    if startsWith(string(setupException.identifier), ...
            "SimuVerity:ReferenceSetup:")
        rethrow(setupException);
    end
    wrapped = MException( ...
        'SimuVerity:ReferenceSetup:ExecutionFailed', ...
        'Reference %s setup failed (%s): %s', setupPhase, ...
        setupException.identifier, setupException.message);
    wrapped = addCause(wrapped, setupException);
    throw(wrapped);
end
end

function localCloseReferenceProject()
try
    p = currentProject;
    if ~isempty(p)
        close(p);
    end
catch cleanupException
    if strcmp(cleanupException.identifier, ...
            'MATLAB:project:api:NoProjectCurrentlyLoaded')
        return
    end
    wrapped = MException( ...
        'SimuVerity:ReferenceSetup:CleanupFailed', ...
        'Reference setup project cleanup failed (%s): %s', ...
        cleanupException.identifier, cleanupException.message);
    wrapped = addCause(wrapped, cleanupException);
    throw(wrapped);
end
end

function same = localSamePath(first, second)
first = strrep(char(first), '/', filesep);
second = strrep(char(second), '/', filesep);
if ispc
    same = strcmpi(first, second);
else
    same = strcmp(first, second);
end
end

function writePhase(path, phase)
writeJson(path, struct('schema','simuverity.clean-replay-phase.v1', ...
    'phase',phase,'observed_at',char(datetime('now','TimeZone','UTC', ...
    'Format','yyyy-MM-dd''T''HH:mm:ss.SSS''Z'''))));
end

function writeJson(path, value)
temporary = [path '.tmp'];
stream = fopen(temporary, 'w', 'n', 'UTF-8');
if stream < 0
    error('SimuVerity:CleanReplay:ReceiptOpenFailed', ...
        'Cannot open receipt path: %s', path);
end
try
    fwrite(stream, jsonencode(value, PrettyPrint=true), 'char');
    fclose(stream);
catch exception
    fclose(stream);
    rethrow(exception);
end
% The Python watchdog reads phase.json while MATLAB advances phases.  On
% Windows that short-lived reader can deny the atomic replacement even
% after this writer has closed its handle.  Retry only this evaluator-owned
% receipt move for a bounded interval; model execution is never retried.
lastMessage = '';
for attempt = 1:100
    [moved, lastMessage] = movefile(temporary, path, 'f');
    if moved
        return
    end
    pause(0.02);
end
error('SimuVerity:CleanReplay:ReceiptMoveFailed', ...
    'Cannot publish receipt path after bounded retry: %s (%s)', ...
    path, lastMessage);
end

function closeLoaded(model)
if ~isempty(model) && bdIsLoaded(model)
    try
        set_param(model, 'SimulationCommand', 'stop');
    catch
    end
    close_system(model, 0);
end
end
