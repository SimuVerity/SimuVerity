function evidence = f90_xmech02_extract_candidate_evidence(modelPath, outDir)
%f90_xmech02_extract_candidate_evidence Source extraction-only compatibility entrypoint.
%
% The Python scorer is run only by the central post-lock offline adapter.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

localRequireExtractor( ...
    "f90_xmech02_extract_evidence.m", ...
    "present");
evidence = f90_xmech02_extract_evidence(modelPath, outDir);
evidencePath = fullfile(outDir, "evidence.json");
assert(isfile(evidencePath), "SimuVerity:F90:XMECH02:EvidenceMissing", ...
    "Evidence extraction did not produce evidence.json.");
assert(isfield(evidence, "extraction_only") && ...
    logical(evidence.extraction_only), ...
    "SimuVerity:F90:XMECH02:ExtractionContract", ...
    "Candidate evaluator must return extraction-only evidence.");
fprintf("F90_XMECH02_EVIDENCE_ONLY output=%s\n", evidencePath);
end

function localRequireExtractor(fileName, expectedFilePresence)
extractorPath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(extractorPath) && localFilePresence(extractorPath) == expectedFilePresence, ...
    "SimuVerity:F90:XMECH02:ExtractorBinding", ...
    "The extraction engine is missing or binding-mismatched.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

