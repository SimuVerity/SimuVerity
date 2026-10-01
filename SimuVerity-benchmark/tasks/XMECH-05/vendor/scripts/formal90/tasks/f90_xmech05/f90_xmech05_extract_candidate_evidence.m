function evidence = f90_xmech05_extract_candidate_evidence(modelPath, outDir)
%f90_xmech05_extract_candidate_evidence Declare the source evidence as score-free.
%
% The current METRICS entrypoint already performs candidate-independent evidence
% extraction.  It predates the dispatcher marker that distinguishes raw
% evidence from MATLAB-side score decisions.  This extractor adds only that
% declaration and republishes the otherwise unchanged evidence JSON.
arguments
    modelPath (1,1) string = ""
    outDir (1,1) string = ""
end

localRequireBase( ...
    "f90_xmech05_score_model.m", ...
    "present");
evidence = f90_xmech05_score_model(modelPath, outDir);
evidence.contains_score_decisions = false;
evidence.contains_score_or_threshold_decisions = false;
if strlength(outDir) > 0
    localWriteJson(fullfile(outDir, "evidence.json"), evidence);
end
end

function localRequireBase(fileName, expectedFilePresence)
basePath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(basePath) && localFilePresence(basePath) == expectedFilePresence, ...
    "SimuVerity:F90:XMECH05:BaseBinding", ...
    "The current XMECH-05 candidate evidence entrypoint is missing or changed.");
end

function localWriteJson(pathOut, payload)
temporary = string(pathOut) + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XMECH05:Write", "Cannot write candidate evidence.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
clear cleanup
assert(movefile(temporary, pathOut, "f"), ...
    "SimuVerity:F90:XMECH05:Publish", "Cannot publish candidate evidence.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

