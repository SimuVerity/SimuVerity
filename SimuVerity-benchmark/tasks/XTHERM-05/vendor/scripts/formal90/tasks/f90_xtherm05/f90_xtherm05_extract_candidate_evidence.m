function evidence = f90_xtherm05_extract_candidate_evidence(modelPath,outDir)
%f90_xtherm05_extract_candidate_evidence Runtime-first candidate evidence.
% METRICS asserted a name/topology audit before any official simulation.  SCORING_CORE keeps
% the same scenarios and measurement helpers, but records that audit as
% score evidence instead of using it as a pre-simulation qualification gate.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
taskRoot=fileparts(mfilename("fullpath"));
repoRoot=taskRoot;for k=1:4,repoRoot=fileparts(repoRoot);end
taskPackageRoot=fileparts(repoRoot);
addpath(fullfile(repoRoot,"scripts","formal90"),"-begin");
addpath(fullfile(repoRoot,"scripts","xp9"),"-begin");addpath(taskRoot,"-begin");
dependency=fullfile(taskRoot,"f90_xtherm05_measurement.m");
assert(strcmpi(xp9_file_presence_file(dependency), ...
    "present"), ...
    "SimuVerity:F90:XTHERM05:MeasurementDependencyBinding");

runScenario=@(varargin)f90_xtherm05_measurement_compatibility("run_scenario",varargin{:});
staticAudit=@(varargin)f90_xtherm05_measurement_compatibility("static_audit",varargin{:});
nominalValues=@(varargin)f90_xtherm05_measurement_compatibility("nominal_values",varargin{:});
emptyRow=@(varargin)f90_xtherm05_measurement_compatibility("empty_row",varargin{:});
flowPairFn=@(varargin)f90_xtherm05_measurement_compatibility("paired_flow_metrics",varargin{:});
currentPairFn=@(varargin)f90_xtherm05_measurement_compatibility("paired_current_metrics",varargin{:});
def=f90_xtherm05_definition;
facts=struct("platform_valid",false,"score_inputs_valid",false, ...
    "diagnostics_valid",false,"gate_reasons",strings(0,1), ...
    "static_audit",struct,"scenario_rows",struct([]), ...
    "paired_flow",struct,"paired_current",struct, ...
    "extraction_only",true,"contains_score_decisions",false);
oldDir=pwd;dirCleanup=onCleanup(@()cd(oldDir)); %#ok<NASGU>
try
    sourceRoot=fullfile(taskPackageRoot,"reference","files", ...
        "Battery-Cooling-Plate-Simscape");
    cd(sourceRoot);project=openProject(fullfile(sourceRoot,"BatteryCoolingPlateSimscape.prj")); %#ok<NASGU>
    nominal=nominalValues(def);names=fieldnames(nominal);
    for index=1:numel(names),assignin("base",names{index},nominal.(names{index}));end
    load_system(modelPath);[~,model]=fileparts(modelPath);
    set_param(model,"SimulationCommand","update");audit=staticAudit(model,def);

    ids=["nominal",string({def.scenarios.id})];values=cell(numel(ids),1);
    values{1}=nominal;
    for index=1:numel(def.scenarios),values{index+1}=def.scenarios(index).values;end
    rows=repmat(emptyRow(),numel(ids),1);reasons=strings(0,1);
    for index=1:numel(ids)
        try,rows(index)=runScenario(model,ids(index),values{index},def);
        catch ME
            rows(index).id=ids(index);rows(index).error=string(ME.message);
            reasons(end+1)=ids(index)+":"+string(ME.identifier); %#ok<AGROW>
        end
    end
    valid=all([rows.valid]);
    if ~valid,reasons=["required scenario or output contract failed";reasons];end
    low=find(ids=="flow_pair_low",1);high=find(ids=="flow_pair_high",1);
    up=find(ids=="current_pair_up",1);control=find(ids=="current_pair_control",1);
    down=find(ids=="current_pair_down",1);
    facts.platform_valid=true;facts.score_inputs_valid=valid;
    facts.diagnostics_valid=valid;facts.gate_reasons=reasons;
    facts.static_audit=audit;facts.scenario_rows=rows;
    if valid
        facts.paired_flow=flowPairFn(rows(low),rows(high));
        facts.paired_current=currentPairFn(rows(up),rows(control),rows(down));
    end
catch ME
    facts.gate_reasons="Evaluator/platform failure: "+string(ME.message);
    facts.error_identifier=string(ME.identifier);facts.error_message=string(ME.message);
    facts.error_report=string(getReport(ME,"extended","hyperlinks","off"));
end
evidence=formal90_write_evidence("F90-XTHERM-05",modelPath,outDir, ...
    def.groups.weights,facts,dependency);
evidence.extraction_only=true;evidence.contains_score_decisions=false;
localWrite(fullfile(outDir,"evidence.json"),evidence);
end

function localWrite(path,value)
fid=fopen(path,"w","n","UTF-8");assert(fid>=0,"SimuVerity:F90:XTHERM05:EvidenceWrite");
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,"PrettyPrint",true),"char");
end
