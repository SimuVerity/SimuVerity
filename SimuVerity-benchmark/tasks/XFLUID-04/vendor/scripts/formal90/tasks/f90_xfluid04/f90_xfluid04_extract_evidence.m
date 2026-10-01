function evidence=f90_xfluid04_extract_evidence(modelPath,outDir)
%F90_XFLUID04_EXTRACT_EVIDENCE Scenario/static/paired facts only.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
taskRoot=fileparts(mfilename('fullpath'));
projectRoot=fileparts(fileparts(fileparts(fileparts(taskRoot))));
addpath(fullfile(projectRoot,'scripts','formal90'),'-begin');
addpath(fullfile(projectRoot,'scripts','xp9'),'-begin');addpath(taskRoot,'-begin');
dependency=fullfile(taskRoot,'f90_xfluid04_measurement.m');
assert(strcmpi(xp9_file_presence_file(dependency), ...
    "present"), ...
    'F90_XFLUID04_MEASUREMENT_DEPENDENCY_BINDING');
runScenario=local_handle('run_scenario');staticAudit=local_handle('static_audit');
nominalValues=local_handle('nominal_values');emptyRow=local_handle('empty_row');
pairedFn=local_handle('paired_causality');def=f90_xfluid04_definition;
facts=struct('platform_valid',false,'score_inputs_valid',false, ...
    'diagnostics_valid',false,'gate_reasons',strings(0,1), ...
    'static_audit',struct,'scenario_rows',struct([]), ...
    'paired_causality',struct);
oldDir=pwd;dirCleanup=onCleanup(@() cd(oldDir)); %#ok<NASGU>
project=[];
try
    sourceRoot=string(getenv('SIMUVERITY_RUNTIME_SUBMISSION_BUNDLE'));
    cd(sourceRoot);project=openProject(fullfile(sourceRoot,'Hydraulic_Lift.prj'));
    projectCleanup=onCleanup(@() local_close_project(project)); %#ok<NASGU>
    Scissor_Lift_Model_PARAM;load_system(modelPath);[~,model]=fileparts(modelPath);
    modelCleanup=onCleanup(@() local_close(model)); %#ok<NASGU>
    set_param(model,'SimulationCommand','update');audit=staticAudit(model,def);
    assert(audit.core_path_qualified,'SimuVerity:F90:XFLUID04:STATIC_CORE_INVALID');
    ids=["nominal",string({def.scenarios.id})];values=cell(numel(ids),1);
    values{1}=nominalValues(def);
    for index=1:numel(def.scenarios),values{index+1}=def.scenarios(index).values;end
    rows=repmat(emptyRow(),numel(ids),1);reasons=strings(0,1);
    for index=1:numel(ids)
        try,rows(index)=runScenario(model,ids(index),values{index},def);
        catch ME,rows(index).id=ids(index);rows(index).error=string(ME.message);
            reasons(end+1)=ids(index)+":"+string(ME.identifier); %#ok<AGROW>
        end
    end
    valid=all([rows.valid]);
    if ~valid,reasons=["required scenario or output contract failed";reasons];end
    drop=find(ids=="pressure_drop_pair",1);control=find(ids=="pressure_control_pair",1);
    facts.platform_valid=true;facts.score_inputs_valid=valid;
    facts.diagnostics_valid=valid;facts.gate_reasons=reasons;
    facts.static_audit=audit;facts.scenario_rows=rows;
    if valid,facts.paired_causality=pairedFn(rows(drop),rows(control));end
catch ME
    facts.gate_reasons="Evaluator/platform failure: "+string(ME.message);
    facts.error_identifier=string(ME.identifier);facts.error_message=string(ME.message);
end
evidence=formal90_write_evidence("F90-XFLUID-04",modelPath,outDir, ...
    def.groups.weights,facts,dependency);
end
function h=local_handle(name),h=@(varargin)f90_xfluid04_measurement_compatibility(name,varargin{:});end
function local_close(model),try,if bdIsLoaded(model),close_system(model,0);end,catch,end,end
function local_close_project(project),try,if ~isempty(project),close(project);end,catch,end,end
