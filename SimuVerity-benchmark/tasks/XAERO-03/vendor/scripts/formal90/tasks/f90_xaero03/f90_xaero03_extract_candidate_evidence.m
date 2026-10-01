function evidence = f90_xaero03_extract_candidate_evidence(modelPath, outDir)
%F90_XAERO03_EXTRACT_CANDIDATE_EVIDENCE Source extraction-only compatibility entrypoint.
arguments
    modelPath (1,1) string = ...
        fullfile(getenv("SIMUVERITY_TASK_ROOT"), "reference", "files", "XAERO03_reference.slx")
    outDir (1,1) string = ...
        tempdir
end

localRequireExtractor( ...
    "f90_xaero03_extract_evidence.m", ...
    "present");
evidence = f90_xaero03_extract_evidence(modelPath, outDir);
assert(isfield(evidence, "extraction_only") && ...
    logical(evidence.extraction_only), ...
    "SimuVerity:F90:XAERO03:ExtractionContract", ...
    "Candidate evaluator must return extraction-only evidence.");
end

function localRequireExtractor(fileName, expectedFilePresence)
extractorPath = fullfile(fileparts(mfilename("fullpath")), fileName);
assert(isfile(extractorPath) && localFilePresence(extractorPath) == expectedFilePresence, ...
    "SimuVerity:F90:XAERO03:ExtractorBinding", ...
    "The extraction engine is missing or binding-mismatched.");
end

function binding = localFilePresence(pathValue)
assert(isfile(pathValue), "SimuVerity:FileMissing", "Required file is missing: %s", pathValue);
binding = "present";
end

