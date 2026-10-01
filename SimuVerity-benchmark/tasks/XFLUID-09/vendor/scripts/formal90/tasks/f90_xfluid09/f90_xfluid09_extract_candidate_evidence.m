function evidence=f90_xfluid09_extract_candidate_evidence(modelPath,outDir)
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
subject=lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT"))));
if strlength(subject)==0, subject="candidate"; end
assert(any(subject==["candidate","reference"]), ...
    "SimuVerity:F90:XFLUID09:EvaluationSubject", ...
    "SIMUVERITY_EVALUATION_SUBJECT must be candidate or reference.");
evidence=f90_xfluid09_extract_reference_evidence(modelPath,outDir,subject);
end
