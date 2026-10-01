function evidence=f90_xauto02_extract_evidence(modelPath,outDir)
%F90_XAUTO02_EXTRACT_EVIDENCE Physical facts only; no utilities or score.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end
taskRoot=fileparts(mfilename('fullpath'));
projectRoot=fileparts(fileparts(fileparts(fileparts(taskRoot))));
restoredefaultpath;
closureHelperRoot=string(getenv('SIMUVERITY_CANDIDATE_CLOSURE_HELPER_ROOT'));
if strlength(closureHelperRoot)>0
    assert(isfolder(closureHelperRoot),'F90_XAUTO02_CANDIDATE_CLOSURE_HELPER_MISSING');
    addpath(closureHelperRoot,'-begin');
    simuverity_reload_candidate_dependencies();
end
addpath(taskRoot,'-begin');
addpath(fullfile(projectRoot,'scripts','formal90'),'-begin');
addpath(fullfile(projectRoot,'scripts','unified','public_output'),'-begin');
addpath(fullfile(projectRoot,'scripts','xp9'),'-end');
dependency=fullfile(taskRoot,'f90_xauto02_measurement.m');
assert(strcmpi(xp9_file_presence_file(dependency), ...
    "present"), ...
    'F90_XAUTO02_MEASUREMENT_DEPENDENCY_BINDING');
runScenario=local_handle('run_scenario');measureRun=local_handle('measure_run');
staticAudit=local_handle('static_audit');nominalValues=local_handle('nominal_values');
emptyRun=local_handle('empty_run');emptyRow=local_handle('empty_row');
setBase=local_handle('local_set_base');snapshotBase=local_handle('local_snapshot_base');
restoreBase=local_handle('local_restore_base');
def=f90_xauto02_definition;baseSnapshot=snapshotBase();
baseCleanup=onCleanup(@() restoreBase(baseSnapshot)); %#ok<NASGU>
facts=struct('platform_valid',false,'score_inputs_valid',false, ...
    'diagnostics_valid',false,'gate_reasons',strings(0,1), ...
    'static_audit',struct,'scenario_rows',struct([]), ...
    'physical_suite',struct,'causal_pairs',struct);
try
    assert(isfile(modelPath),'F90_XAUTO02_MODEL_NOT_FOUND');
    nominal=nominalValues(def);setBase(nominal);[~,model]=fileparts(modelPath);
    model=string(model);load_system(modelPath);
    modelCleanup=onCleanup(@() local_close(model)); %#ok<NASGU>
    audit=staticAudit(model,def);set_param(model,'SimulationCommand','update');
    feval(model,[],[],[],'compile');feval(model,[],[],[],'term');
    scenarioDefs=[struct('id','nominal','values',nominal),def.scenarios];
    runs=repmat(emptyRun(),1,numel(scenarioDefs));
    rows=repmat(emptyRow(),1,numel(scenarioDefs));
    for index=1:numel(scenarioDefs)
        runs(index)=runScenario(model,scenarioDefs(index),def);
        rows(index)=measureRun(runs(index),def);
    end
    [suite,pairs]=local_suite_facts(runs,rows,def);
    gate=all([rows.valid])&&audit.output_contract_connected;
    reasons=strings(0,1);
    if ~gate,reasons(end+1)="GATE_OR_SCENARIO_FAILURE";end
    facts.platform_valid=true;facts.score_inputs_valid=gate;
    facts.diagnostics_valid=true;facts.gate_reasons=reasons;
    facts.static_audit=audit;facts.scenario_rows=rows;
    facts.physical_suite=suite;facts.causal_pairs=pairs;
    facts.range_scenario_ids=def.range_scenario_ids;
    facts.dynamic_scenario_ids=def.dynamic_scenario_ids;
    save(fullfile(outDir,'waveforms.mat'),'runs','def','-v7.3');
catch ME
    facts.gate_reasons="Evaluator/platform failure: "+string(ME.message);
    facts.error_identifier=string(ME.identifier);facts.error_message=string(ME.message);
end
evidence=formal90_write_evidence("F90-XAUTO-02",modelPath,outDir, ...
    def.groups.weights,facts,dependency);
end

function [suite,pairs]=local_suite_facts(runs,rows,def)
derivative=local_handle('local_derivative');
backward=local_handle('local_backward_derivative');
longFit=local_handle('longitudinal_fit');wheelFit=local_handle('wheel_fit');
rollFit=local_handle('roll_fit');
longBase=[];longForce=[];longDrag=[];accelResidual=[];
wheelCentered=[];wheelBackward=[];wheelForce=[];wheelTorque=[];wheelSpeed=[];
slipError=[];verticalLeft=[];verticalRight=[];rollX=[];rollMoment=[];
for index=1:numel(runs)
    if ~runs(index).valid,continue;end
    run=runs(index);t=run.t;b=run.body;a=run.axle;w=run.wheel;
    u=run.actuation;m=double(run.inputs.vehicle_mass);vx=b(:,2);
    fx=w(:,13:16);fz=w(:,9:12);omega=w(:,1:4);delivered=u(:,5:8);
    mask=t>=.35&vx>.75;stride=max(1,round(.01/median(diff(t))));
    selected=find(mask);selected=selected(1:stride:end);
    dv=derivative(vx,t);db=backward(vx,t);use=(dv+db)/2;
    longBase=[longBase;m*use(selected)]; %#ok<AGROW>
    longForce=[longForce;sum(fx(selected,:),2)];longDrag=[longDrag;vx(selected).^2]; %#ok<AGROW>
    accelResidual=[accelResidual;b(selected,9)-use(selected)]; %#ok<AGROW>
    domega=derivative(omega,t);domegaBack=backward(omega,t);
    wheelCentered=[wheelCentered;domega(selected,:)]; %#ok<AGROW>
    wheelBackward=[wheelBackward;domegaBack(selected,:)]; %#ok<AGROW>
    wheelForce=[wheelForce;fx(selected,:)];wheelTorque=[wheelTorque;delivered(selected,:)]; %#ok<AGROW>
    wheelSpeed=[wheelSpeed;omega(selected,:)]; %#ok<AGROW>
    kSlip=(.34*omega-vx)./max(max(abs(.34*omega),abs(vx)),.7);
    slipError=[slipError;abs(w(:,5:8)-kSlip)]; %#ok<AGROW>
    azb=derivative(b(:,4),t);azf=derivative(a(:,2),t);azr=derivative(a(:,6),t);
    verticalLeft=[verticalLeft;.78*m*azb(selected)+.11*m*azf(selected)+.11*m*azr(selected)]; %#ok<AGROW>
    verticalRight=[verticalRight;sum(fz(selected,:),2)-m*9.81]; %#ok<AGROW>
    pdd=derivative(b(:,8),t);pfdd=derivative(a(:,4),t);prdd=derivative(a(:,8),t);
    rollX=[rollX;pdd(selected),pfdd(selected),prdd(selected)]; %#ok<AGROW>
    rollMoment=[rollMoment;.8*(fz(selected,1)-fz(selected,2)+fz(selected,3)-fz(selected,4))/m]; %#ok<AGROW>
end
[suite.longitudinal_balance_error,suite.fitted_drag]=longFit(longBase,longForce,longDrag);
suite.reported_acceleration_error=sqrt(mean(accelResidual.^2))/ ...
    max(sqrt(mean((longBase/1600).^2)),1);
[cErr,cFit]=wheelFit(wheelCentered,wheelForce,wheelTorque,wheelSpeed);
[bErr,bFit]=wheelFit(wheelBackward,wheelForce,wheelTorque,wheelSpeed);
if bErr<cErr,suite.wheel_balance_error=bErr;suite.wheel_fit=bFit;suite.wheel_derivative="backward";
else,suite.wheel_balance_error=cErr;suite.wheel_fit=cFit;suite.wheel_derivative="centered";end
suite.slip_kinematic_error=median(slipError,'all');
suite.vertical_balance_error=sqrt(mean((verticalLeft-verticalRight).^2))/ ...
    max(sqrt(mean(verticalRight.^2)),500);
[suite.roll_balance_error,suite.roll_inertia_fit,suite.roll_positive_inertia]= ...
    rollFit(rollX,rollMoment);
suite.static_state_evidence=double(any([rows.body_vertical_accel_rms]>.02)&& ...
    any([rows.normal_force_rms_variation]>.005));
pairs=struct('target_response',local_target_pair(runs,rows), ...
    'road_response',local_road_pair(runs,rows), ...
    'fault_response',local_fault_pair(runs,rows,def));
end
function pair=local_target_pair(runs,rows)
pair=struct('valid',false,'speed_separation',0,'torque_separation',0);
lo=find(string({runs.id})=="target_probe_low",1);hi=find(string({runs.id})=="target_probe_high",1);
if isempty(lo)||isempty(hi)||~runs(lo).valid||~runs(hi).valid,return;end
ml=runs(lo).t>=2.5&runs(lo).t<=6.3;mh=runs(hi).t>=2.5&runs(hi).t<=6.3;
cl=runs(lo).t>=.15&runs(lo).t<=1.25;ch=runs(hi).t>=.15&runs(hi).t<=1.25;
pair.speed_separation=mean(runs(hi).body(mh,2))-mean(runs(lo).body(ml,2));
pair.torque_separation=mean(runs(hi).actuation(ch,1:4),'all')- ...
    mean(runs(lo).actuation(cl,1:4),'all');
pair.valid=all([rows([lo,hi]).valid]);
end
function pair=local_road_pair(runs,rows)
pair=struct('valid',false,'road_rms_ratio',0,'vertical_response_ratio',0, ...
    'normal_response_ratio',0);
lo=find(string({runs.id})=="road_probe_low",1);hi=find(string({runs.id})=="road_probe_high",1);
if isempty(lo)||isempty(hi)||~runs(lo).valid||~runs(hi).valid,return;end
pair.road_rms_ratio=rows(hi).road_rms/max(rows(lo).road_rms,1e-9);
pair.vertical_response_ratio=rows(hi).body_vertical_accel_rms/max(rows(lo).body_vertical_accel_rms,1e-9);
pair.normal_response_ratio=rows(hi).normal_force_rms_variation/max(rows(lo).normal_force_rms_variation,1e-9);
pair.valid=true;
end
function pair=local_fault_pair(runs,rows,def)
pair=struct('valid',false,'requested_torque_change',0, ...
    'delivered_torque_change',0,'speed_effect',0, ...
    'loss_contract_error',1,'recovery_time',def.sim.stop);
no=find(string({runs.id})=="fault_pair_none",1);loss=find(string({runs.id})=="fault_pair_loss",1);
if isempty(no)||isempty(loss)||~runs(no).valid||~runs(loss).valid,return;end
t=runs(loss).t;start=double(runs(loss).inputs.drive_loss_time);
stop=start+def.public_constants.drive_loss_duration_s;event=t>=start+.08&t<=stop-.08;
cmdNo=mean(abs(runs(no).actuation(event,[2,4])),'all');
cmdLoss=mean(abs(runs(loss).actuation(event,[2,4])),'all');
delNo=mean(abs(runs(no).actuation(event,[6,8])),'all');
delLoss=mean(abs(runs(loss).actuation(event,[6,8])),'all');
pair.requested_torque_change=abs(cmdLoss-cmdNo)/max(cmdNo,50);
pair.delivered_torque_change=abs(delLoss-delNo)/max(delNo,50);
pair.speed_effect=max(abs(runs(loss).body(event,2)-runs(no).body(event,2)))/ ...
    max(double(runs(loss).inputs.speed_reference),1);
pair.loss_contract_error=rows(loss).loss_delivery_error;
pair.recovery_time=rows(loss).recovery_time;pair.valid=true;
end
function h=local_handle(name),h=@(varargin)f90_xauto02_measurement_compatibility(name,varargin{:});end
function local_close(model),try,if bdIsLoaded(model),close_system(model,0);end,catch,end,end
