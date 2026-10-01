function evidence = f90_xcomm07_extract_candidate_evidence(modelPath, outputDir)
%F90_XCOMM07_EXTRACT_CANDIDATE_EVIDENCE_CORE_CORE Declare score-free extraction.
%
% The candidate-independent extractor already emits complete task evidence
% and contains no scoring decisions.  This extractor only publishes the
% extraction_only marker required by the current dispatcher.
evidence = f90_xcomm07_extract_candidate_evidence_core(modelPath, outputDir);
evidence.extraction_only = true;
localWriteJson(fullfile(outputDir, "evidence.json"), evidence);
end

function localWriteJson(pathOut, payload)
temporary = string(pathOut) + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XCOMM07:Write", "Cannot write candidate evidence.");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
clear cleanup
assert(movefile(temporary, pathOut, "f"), ...
    "SimuVerity:F90:XCOMM07:Publish", "Cannot publish candidate evidence.");
end
