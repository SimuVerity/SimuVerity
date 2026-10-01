function evidence=f90_xfluid02_extract_evidence(modelPath,outDir)
%F90_XFLUID02_EXTRACT_EVIDENCE Run triplex-pump scenarios; do not score.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
taskRoot=fileparts(mfilename('fullpath'));
projectRoot=fileparts(fileparts(fileparts(fileparts(taskRoot))));
addpath(fullfile(projectRoot,'scripts','xp9'),'-begin');addpath(taskRoot,'-begin');
dependency=fullfile(taskRoot,'f90_xfluid02_measurement.m');
assert(strcmpi(xp9_file_presence_file(dependency), ...
    "present"), ...
    'F90_XFLUID02_MEASUREMENT_DEPENDENCY_BINDING');
runScenario=@(varargin)f90_xfluid02_measurement_compatibility("run_scenario",varargin{:});
staticAudit=@(varargin)f90_xfluid02_measurement_compatibility("static_audit",varargin{:});
nominalValues=@(varargin)f90_xfluid02_measurement_compatibility("nominal_values",varargin{:});
emptyRow=@(varargin)f90_xfluid02_measurement_compatibility("empty_row",varargin{:});
def=f90_xfluid02_definition;
isReference = lower(strtrim(string(getenv("SIMUVERITY_EVALUATION_SUBJECT")))) == "reference";
facts=struct('platform_valid',false,'score_inputs_valid',false, ...
    'diagnostics_valid',false,'gate_reasons',strings(0,1), ...
    'static_audit',struct,'scenario_rows',struct([]), ...
    'scenario_values',{{}},'runs',struct([]));
oldDir=pwd;dirCleanup=onCleanup(@() cd(oldDir)); %#ok<NASGU>
project=[];
try
    sourceRoot=fullfile(string(getenv('SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE')), ...
        'Simscape-Triplex-Pump');
    if isReference
        cd(sourceRoot);project=openProject(fullfile(sourceRoot,'Triplex_Pump.prj'));
        projectCleanup=onCleanup(@() local_close_project(project)); %#ok<NASGU>
    else
        cd(fileparts(modelPath));
    end
    load_system(modelPath);[~,model]=fileparts(modelPath);
    modelCleanup=onCleanup(@() local_close(model)); %#ok<NASGU>
    local_assign_values(model,nominalValues(def),isReference);
    set_param(model,'SimulationCommand','update');audit=staticAudit(model);
    ids=["nominal",string({def.scenarios.id})];values=cell(1,numel(ids));
    values{1}=nominalValues(def);
    for index=1:numel(def.scenarios),values{index+1}=def.scenarios(index).values;end
    rows=repmat(emptyRow(),numel(ids),1);
    runRows=repmat(struct('id',"",'stage',"not_run",'valid',false,'error',""),numel(ids),1);
    for index=1:numel(ids)
        runRows(index).id=ids(index);
        try
            rows(index)=runScenario(model,ids(index),values{index},def,isReference);
            runRows(index).stage="simulated";runRows(index).valid=rows(index).valid;
        catch ME
            runRows(index).stage="failed";runRows(index).error=string(ME.message);
        end
    end
    valid=all([rows.valid]);reasons=strings(0,1);
    if ~valid,reasons="One or more required scenarios are invalid";end
    facts.platform_valid=true;facts.score_inputs_valid=valid;
    facts.diagnostics_valid=true;facts.gate_reasons=reasons;
    facts.static_audit=audit;facts.scenario_rows=rows;
    facts.scenario_values=values;facts.runs=runRows;
catch ME
    facts.gate_reasons="Evaluator/platform failure: "+string(ME.message);
    facts.error_identifier=string(ME.identifier);facts.error_message=string(ME.message);
end
evidence=formal90_write_evidence("F90-XFLUID-02",modelPath,outDir, ...
    def.groups.weights,facts,dependency);
end
function local_assign_values(model,values,assignModelWorkspace)
fields=fieldnames(values);workspace=get_param(model,'ModelWorkspace');
for index=1:numel(fields)
    name=fields{index};assignin('base',name,values.(name));
    if assignModelWorkspace,assignin(workspace,name,values.(name));end
end
end
function local_close(model),try,if bdIsLoaded(model),close_system(model,0);end,catch,end,end
function local_close_project(project),try,if ~isempty(project),close(project);end,catch,end,end
