function evidence = f90_xrobo01_extract_evidence(modelPath, outDir)
%f90_xrobo01_extract_evidence Extract dynamics and the current port graph.
% GROUP_SCORING changes only the offline
% interpretation of MATLAB JSON scalar/edge-table representations and public
% contract structure semantics.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

taskDir = fileparts(mfilename("fullpath"));
coreExtractor = fullfile(taskDir, "f90_xrobo01_extract_evidence_core.m");
assert(isfile(coreExtractor), "SimuVerity:F90:XROBO01:DependencyMissing", ...
    "The bundled SCORING_CORE extraction engine is missing.");
evidence = f90_xrobo01_extract_evidence_core(modelPath, outDir);
evidence.structure_evidence_schema = ...
    "simuverity.f90-xrobo01-public-contract-port-network.v1";
evidence.current_reextracts_same_dynamic_scenarios = true;
evidence.current_normalizes_matlab_json_shapes_offline = true;
evidence.current_score_formula_thresholds_weights_unchanged = true;
evidence.score_fields_present = false;
localWriteJsonReplace(fullfile(outDir, "evidence.json"), evidence);
end

function localWriteJsonReplace(pathValue, payload)
assert(isfile(pathValue), "SimuVerity:F90:XROBO01:EvidenceMissing");
temporary = pathValue + ".staging-" + string(java.util.UUID.randomUUID);
fid = fopen(temporary, "w", "n", "UTF-8");
assert(fid >= 0, "SimuVerity:F90:XROBO01:JsonOpen");
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid, jsonencode(payload, PrettyPrint=true), "char");
clear cleanup
assert(movefile(temporary, pathValue, "f"), ...
    "SimuVerity:F90:XROBO01:JsonPublish");
end
