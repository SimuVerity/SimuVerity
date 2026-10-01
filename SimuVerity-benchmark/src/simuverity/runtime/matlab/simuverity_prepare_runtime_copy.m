function receipt = simuverity_prepare_runtime_copy(runtimeCandidatePath, sealedCandidatePath, receiptPath)
%SIMUVERITY_PREPARE_RUNTIME_COPY Apply only logging-size overrides.
% The sealed candidate is verified but never opened for update or saved.
arguments
    runtimeCandidatePath (1,:) char
    sealedCandidatePath (1,:) char
    receiptPath (1,:) char
end

sealedBytes = localReadBytes(sealedCandidatePath);
runtimeBytesBefore = localReadBytes(runtimeCandidatePath);
assert(isequal(runtimeBytesBefore, sealedBytes), ...
    'SimuVerity:RuntimeOverride:InitialIdentity', ...
    'Evaluator runtime candidate is not an exact sealed copy.');
[~, model] = fileparts(runtimeCandidatePath);
load_system(runtimeCandidatePath);
cleanup = onCleanup(@() localClose(model)); %#ok<NASGU>
rows = struct('block_path', {}, 'parameter', {}, 'before', {}, 'after', {});

try
    before = string(get_param(model, 'LimitDataPoints'));
    if ~strcmpi(before, 'off')
        set_param(model, 'LimitDataPoints', 'off');
        rows(end+1) = struct('block_path', string(model), ...
            'parameter', 'LimitDataPoints', 'before', before, 'after', 'off'); %#ok<AGROW>
    end
catch exception
    if ~contains(string(exception.identifier), 'ParamUnknown')
        rethrow(exception);
    end
end

blocks = string(find_system(model, 'LookUnderMasks', 'all', ...
    'FollowLinks', 'on', 'BlockType', 'ToWorkspace'));
for index = 1:numel(blocks)
    before = string(get_param(blocks(index), 'MaxDataPoints'));
    if ~strcmpi(before, 'inf')
        set_param(blocks(index), 'MaxDataPoints', 'inf');
        rows(end+1) = struct('block_path', blocks(index), ...
            'parameter', 'MaxDataPoints', 'before', before, 'after', 'inf'); %#ok<AGROW>
    end
end

if ~isempty(rows)
    save_system(model, runtimeCandidatePath);
end
sealedAfter = localReadBytes(sealedCandidatePath);
assert(isequal(sealedAfter, sealedBytes), ...
    'SimuVerity:RuntimeOverride:SealedMutation', ...
    'Runtime preparation modified the sealed candidate.');
receipt = struct( ...
    'schema', 'simuverity.runtime-output-override.v1', ...
    'runtime_copy_only', true, ...
    'sealed_original_modified', false, ...
    'sealed_candidate_unchanged', true, ...
    'runtime_copy_prepared', true, ...
    'parameter_allowlist_only', true, ...
    'parameter_overrides', rows);
localWriteJson(receiptPath, receipt);
end

function localClose(model)
if bdIsLoaded(model), close_system(model, 0); end
end

function bytes = localReadBytes(pathValue)
fid = fopen(pathValue, 'rb');
assert(fid >= 0, 'SimuVerity:RuntimeOverride:FileOpen', ...
    'Cannot read candidate: %s', pathValue);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, Inf, '*uint8');
end

function localWriteJson(pathValue, value)
temporary = string(pathValue) + '.tmp';
fid = fopen(temporary, 'w', 'n', 'UTF-8');
assert(fid >= 0, 'SimuVerity:RuntimeOverride:ReceiptWrite', ...
    'Cannot write runtime override receipt.');
try
    fwrite(fid, jsonencode(value, PrettyPrint=true), 'char');
    fclose(fid);
catch exception
    fclose(fid);
    rethrow(exception);
end
movefile(temporary, pathValue, 'f');
end
