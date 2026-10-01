function evidence = f90_xtherm09_extract_candidate_evidence(modelFile, outFile, generationRunId)
%f90_xtherm09_extract_candidate_evidence Extraction-only metadata wrapper.
% METRICS already produces score-free scenario waveforms and a static audit.  It
% omitted the two dispatcher declarations that say validity is delegated to
% the dedicated offline scorer, so otherwise complete evidence was rejected
% before EVIDENCE_COMPLETE.  This wrapper changes metadata only.
if nargin < 3, generationRunId = "manual"; end
evidence = f90_xtherm09_extract_evidence(modelFile, outFile, generationRunId);
assert(string(evidence.schema) == "simuverity.f90-xtherm09-evidence.v1", ...
    "SimuVerity:F90:XTHERM09:MetadataSchema", "Unexpected METRICS evidence schema.");
assert(string(evidence.task_id) == "F90-XTHERM-09", ...
    "SimuVerity:F90:XTHERM09:MetadataTask", "Unexpected task identity.");
evidence.extraction_only = true;
evidence.contains_score_decisions = false;
fid = fopen(outFile,"w");
assert(fid >= 0,"SimuVerity:F90:XTHERM09:EvidenceWrite", ...
    "Cannot open evidence output.");
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(evidence,PrettyPrint=true),"char");
end
