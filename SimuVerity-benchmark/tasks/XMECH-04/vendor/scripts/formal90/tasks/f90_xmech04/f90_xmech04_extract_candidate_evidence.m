function evidence=f90_xmech04_extract_candidate_evidence(specPath,modelPath,outDir,opts)
%f90_xmech04_extract_candidate_evidence Candidate extraction with structural evidence.
arguments
    specPath (1,1) string
    modelPath (1,1) string
    outDir (1,1) string
    opts.SaveWaveforms (1,1) logical = true
end
evidence=formal90_extract_xp9_evidence(specPath,modelPath,outDir, ...
    "f90_xmech04_build_evidence","F90-XMECH-04", ...
    SaveWaveforms=opts.SaveWaveforms);
audit=f90_xmech04_static_audit(modelPath);
evidence.facts.structure_graph=audit.port_graph;
evidence.facts.structure_audit=rmfield(audit,'port_graph');
local_write(evidence,fullfile(outDir,'evidence.json'));
end

function local_write(value,path)
fid=fopen(path,'w','n','UTF-8');assert(fid>=0,'Cannot open %s',path);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),'char');
end
