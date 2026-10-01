function result = f90_xmed10_extract_candidate_evidence(modelPath, outputDir)
% Candidate wrapper for the dedicated F90-XMED-10 extractor.
if nargin < 2, outputDir = ""; end
result = f90_xmed10_extract_reference_evidence(modelPath, outputDir, "candidate");
end
