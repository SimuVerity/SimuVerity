function simuverity_publish_diagnostic_evidence(sourcePath, targetPath)
%SIMUVERITY_PUBLISH_DIAGNOSTIC_EVIDENCE Preserve score-free failure evidence.
arguments
    sourcePath (1,1) string
    targetPath (1,1) string
end
assert(isfile(sourcePath), "SimuVerity:Extractor:DiagnosticMissing", ...
    "Extractor diagnostic evidence is missing: %s", sourcePath);
parent = string(fileparts(targetPath));
if strlength(parent) > 0 && ~isfolder(parent), mkdir(parent); end
temporary = targetPath + ".tmp-" + string(java.util.UUID.randomUUID);
assert(copyfile(sourcePath, temporary, "f"), ...
    "SimuVerity:Extractor:DiagnosticCopy", ...
    "Could not stage extractor diagnostic evidence.");
cleanup = onCleanup(@() localDelete(temporary)); %#ok<NASGU>
lastMessage = "";
for attempt = 1:100
    [moved, lastMessage] = movefile(temporary, targetPath, "f");
    if moved, return; end
    pause(0.02);
end
error("SimuVerity:Extractor:DiagnosticPublish", ...
    "Could not publish extractor diagnostic evidence: %s", lastMessage);
end

function localDelete(pathValue)
if isfile(pathValue), delete(pathValue); end
end
