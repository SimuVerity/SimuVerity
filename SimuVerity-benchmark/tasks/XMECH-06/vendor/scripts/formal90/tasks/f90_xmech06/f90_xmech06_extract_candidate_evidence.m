function result = f90_xmech06_extract_candidate_evidence(modelPath, outputDir)
%f90_xmech06_extract_candidate_evidence Candidate entry with event-derived brake windows.
arguments
    modelPath (1,1) string
    outputDir (1,1) string
end

localRequireExtractor( ...
    "f90_xmech06_extract_evidence.m", ...
    "present");
result = f90_xmech06_extract_evidence(modelPath, outputDir);
assert(~result.reference_direct_golden, ...
    "SimuVerity:F90:XMECH06:CandidateIsReference", ...
    "Candidate evaluation must not use the pinned reference model.");
assert(result.extraction_only && ~result.contains_score_decisions && ...
    string(result.schema) == "simuverity.f90-xmech06-evidence.v1", ...
    "SimuVerity:F90:XMECH06:ExtractionContract", ...
    "Candidate evaluator must return extraction-only evidence.");
end

function localRequireExtractor(fileName, expectedFilePresence)
extractorPath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(extractorPath) && localFilePresence(extractorPath) == expectedFilePresence, ...
    "SimuVerity:F90:XMECH06:ExtractorBinding", ...
    "The current evidence extractor is missing or binding-mismatched.");
end

function value = localFilePresence(path)
assert(isfile(path), "SimuVerity:FileMissing", "Required file is missing: %s", path);
value = "present";
end

