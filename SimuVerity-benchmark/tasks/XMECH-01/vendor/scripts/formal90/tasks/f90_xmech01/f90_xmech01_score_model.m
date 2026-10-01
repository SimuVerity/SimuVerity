function evidence=f90_xmech01_score_model(specPath,modelPath,outDir,opts)
%F90_XMECH01_SCORE_MODEL Fixed-probe extraction for the public policy.
arguments
    specPath (1,1) string
    modelPath (1,1) string
    outDir (1,1) string
    opts.SaveWaveforms (1,1) logical = true
end
evidence=formal90_extract_xp9_evidence(specPath,modelPath,outDir, ...
    "f90_xmech01_build_evidence","F90-XMECH-01", ...
    SaveWaveforms=opts.SaveWaveforms);
evidence=successor_metadata(evidence);
local_write(evidence,fullfile(outDir,'evidence.json'));
end

function evidence=successor_metadata(evidence)
extractorPath=string(mfilename('fullpath'))+".m";
evidence.task_extractor_path=extractorPath;
evidence.task_extractor_file_presence=xp9_file_presence_file(extractorPath);
evidence.evaluation_policy_id="simuverity-101-v1:p9-xmech01:scoring";
evidence.group_weights=struct( ...
    'A',.35,'Q',.10,'M',.25,'C',.10,'R',.10,'D',.10);
evidence.fixed_probe_pair_contract=struct( ...
    'loss_scenario',"traction_binding_probe", ...
    'control_scenario',"traction_binding_probe_no_loss", ...
    'selection_policy',"fixed_by_scenario_id", ...
    'missing_or_invalid_pair',"qualification_failure");
end

function local_write(value,file)
fid=fopen(file,'w','n','UTF-8');assert(fid>=0,'Cannot open %s',file);
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,'PrettyPrint',true),'char');
end
