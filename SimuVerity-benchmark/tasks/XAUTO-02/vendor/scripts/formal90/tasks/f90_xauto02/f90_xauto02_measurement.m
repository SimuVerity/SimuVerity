function receipt = f90_xauto02_measurement(modelPath,outDir)
%F90_XAUTO02_CANDIDATE_SIMULATION_CORE Dedicated multi-scenario physical scorer.
%
% The scorer identifies the required outputs by their public contract, then
% judges connections and measured behavior.  Block names are not used to
% infer the vehicle mechanism.  Required operating performance is reduced
% by the worst applicable official scenario.
arguments
    modelPath (1,1) string
    outDir (1,1) string
end

if ~isfolder(outDir), mkdir(outDir); end
def = f90_xauto02_definition;
receipt = empty_receipt(def,modelPath);
oldPath = path;
pathCleanup = onCleanup(@() path(oldPath)); %#ok<NASGU>
restoredefaultpath;
addpath(fileparts(mfilename("fullpath")),"-begin");
addpath(fullfile(fullfile(getenv("SIMUVERITY_TASK_VENDOR_ROOT")),"scripts","xp9"),"-end");
baseSnapshot = local_snapshot_base;
baseCleanup = onCleanup(@() local_restore_base(baseSnapshot)); %#ok<NASGU>

try
    assert(isfile(modelPath),"F90_XAUTO02_MODEL_NOT_FOUND");
    receipt.model_file_presence = xp9_file_presence_file(modelPath);
    nominal = nominal_values(def);
    local_set_base(nominal);
    [~,model] = fileparts(modelPath);
    model = string(model);
    if bdIsLoaded(model), close_system(model,0); end
    load_system(modelPath);
    modelCleanup = onCleanup(@() local_close(model)); %#ok<NASGU>
    receipt.load_pass = true;
    receipt.static_audit = static_audit(model,def);

    set_param(model,"SimulationCommand","update");
    receipt.update_pass = true;
    feval(model,[],[],[],"compile");
    feval(model,[],[],[],"term");
    receipt.compile_pass = true;

    scenarioDefs = [struct("id","nominal","values",nominal),def.scenarios];
    runs = repmat(empty_run,1,numel(scenarioDefs));
    rows = repmat(empty_row,1,numel(scenarioDefs));
    for k = 1:numel(scenarioDefs)
        runs(k) = run_scenario(model,scenarioDefs(k),def);
        rows(k) = measure_run(runs(k),def);
    end
    receipt.scenarios = rows;
    [suite,pairs] = measure_suite(runs,rows,def);
    receipt.metric_values = struct("physical_suite",suite,"causal_pairs",pairs);

    G = receipt.load_pass && receipt.update_pass && receipt.compile_pass && ...
        all([rows.valid]) && receipt.static_audit.output_contract_connected;
    groups = compute_groups(rows,suite,pairs,receipt.static_audit,def,G);
    receipt.groups = groups;
    receipt.valid = G;
    receipt.failure_reasons = failure_reasons(rows,suite,pairs, ...
        receipt.static_audit,G);
    w = def.groups.weights;
    total = 100*(w.A*groups.A+w.Q*groups.Q+w.M*groups.M+ ...
        w.R*groups.R+w.D*groups.D);
    if ~G, total = 0; end
    receipt.total = min(max(double(total),0),100);
    receipt.score_formula = ...
        "G * 100 * (.18*A + .12*Q + .32*M + .20*R + .18*D), with causal-mechanism ceilings";
    save(fullfile(outDir,"waveforms.mat"),"runs","def","-v7.3");
catch ME
    receipt.valid = false;
    receipt.total = 0;
    receipt.groups = struct("G",0,"A",0,"Q",0,"M",0,"R",0,"D",0);
    receipt.failure_reasons = unique([receipt.failure_reasons; ...
        "SCORER_EXCEPTION:"+string(ME.identifier)+":"+string(ME.message)], ...
        "stable");
    receipt.error_identifier = string(ME.identifier);
    receipt.error_message = string(ME.message);
    receipt.error_report = string(getReport(ME,"extended","hyperlinks","off"));
end

receipt.finished_at = local_now;
receipt.runtime_identity = struct( ...
    "generation_run_id",string(getenv("SIMUVERITY_GENERATION_RUN_ID")), ...
    "lane",string(getenv("SIMUVERITY_MATLAB_LANE")), ...
    "workspace",string(getenv("SIMUVERITY_WORKSPACE")), ...
    "matlab_prefdir",string(getenv("MATLAB_PREFDIR")), ...
    "appdata",string(getenv("APPDATA")), ...
    "localappdata",string(getenv("LOCALAPPDATA")), ...
    "temp",string(getenv("TEMP")), ...
    "mcp_port_reserved",string(getenv("SIMUVERITY_MCP_PORT")));
local_write_json(fullfile(outDir,"receipt.json"),receipt);
fprintf("F90_XAUTO02_SCORE valid=%d total=%.6f out=%s\n", ...
    receipt.valid,receipt.total,outDir);
end

function run = run_scenario(model,scenario,def)
run = empty_run;
run.id = string(scenario.id);
run.inputs = scenario.values;
try
    local_set_base(run.inputs);
    in = Simulink.SimulationInput(model);
    names = fieldnames(run.inputs);
    for k = 1:numel(names)
        in = in.setVariable(names{k},run.inputs.(names{k}), ...
            "Workspace",model);
    end
    step = num2str(def.sim.step,17);
    in = in.setModelParameter( ...
        "StopTime",num2str(def.sim.stop,17), ...
        "FixedStep",step, ...
        "MaxStep",step, ...
        "ReturnWorkspaceOutputs","on");
    out = sim(in);
    outputNames = string({def.outputs.name});
    data = cell(1,numel(outputNames));
    times = cell(1,numel(outputNames));
    for k = 1:numel(outputNames)
        ts = out.get(outputNames(k));
        assert(isa(ts,"timeseries"), ...
            "F90_XAUTO02_OUTPUT_NOT_TIMESERIES:%s",outputNames(k));
        data{k} = normalize_data(ts);
        times{k} = double(ts.Time(:));
        assert(size(data{k},2)==def.outputs(k).channels, ...
            "F90_XAUTO02_CHANNEL_COUNT:%s",outputNames(k));
        assert(all(isfinite(data{k}),"all")&&all(isfinite(times{k})), ...
            "F90_XAUTO02_NONFINITE:%s",outputNames(k));
    end
    t = times{1};
    for k = 2:numel(times)
        assert(numel(times{k})==numel(t) && ...
            max(abs(times{k}-t))<=1e-9, ...
            "F90_XAUTO02_TIME_MISMATCH:%s",outputNames(k));
    end
    assert(t(1)<=1e-9 && t(end)>=def.sim.stop-1e-9, ...
        "F90_XAUTO02_TIME_COVERAGE");
    run.t = t;
    run.body = data{1};
    run.axle = data{2};
    run.wheel = data{3};
    run.actuation = data{4};
    run.stage = "simulated";
    run.valid = true;
catch ME
    run.stage = "failed";
    run.error = string(ME.identifier)+":"+string(ME.message);
end
end

function row = measure_run(run,def)
row = empty_row;
row.id = run.id;
if ~run.valid
    row.error = run.error;
    return
end
t = run.t; b = run.body; a = run.axle;
w = run.wheel; u = run.actuation; v = run.inputs;
vx = b(:,2); pitch = b(:,5); roll = b(:,7); ax = b(:,9); az = b(:,10);
omega = w(:,1:4); slip = w(:,5:8); fz = w(:,9:12);
fx = w(:,13:16); road = w(:,17:20);
cmd = u(:,1:4); delivered = u(:,5:8);
eventStart = double(v.drive_loss_time);
eventEnd = eventStart+def.public_constants.drive_loss_duration_s;
tracking = t>=1.5 & ~(t>=eventStart-.05&t<=eventEnd+.45);
if nnz(tracking)<100, tracking=t>=1.5; end
final = t>=def.sim.stop-.60;
roadActive = t>=.5 & max(abs(road),[],2)>=.05*double(v.road_amplitude);
if nnz(roadActive)<100, roadActive=t>=1.5; end
moving = t>=.25 & vx>.75;

row.initial_speed_error = abs(vx(1)-double(v.initial_speed))/ ...
    max(abs(double(v.initial_speed)),1);
row.speed_tracking_nrmse = sqrt(mean((vx(tracking)- ...
    double(v.speed_reference)).^2))/max(abs(double(v.speed_reference)),1);
row.final_speed_error = abs(mean(vx(final))-double(v.speed_reference))/ ...
    max(abs(double(v.speed_reference)),1);
row.body_vertical_accel_rms = sqrt(mean(az(roadActive).^2));
row.body_longitudinal_accel_peak = max(abs(ax));
row.pitch_peak = max(abs(pitch));
row.roll_peak = max(abs(roll));
row.heave_peak = max(abs(b(:,3)));
row.axle_heave_peak = max(abs(a(:,[1 5])),[],"all");
row.lift_fraction = mean(any(fz<.05*double(v.vehicle_mass)*9.81/4,2));
row.normal_force_peak_ratio = max(fz,[],"all") / ...
    (double(v.vehicle_mass)*9.81/4);
row.slip_p95 = local_percentile(abs(slip(moving,:)),95);
row.slip_peak = max(abs(slip(moving,:)),[],"all");
row.command_ratio_peak = max(abs(cmd),[],"all")/1150;
du = local_derivative(cmd,t);
row.command_ripple = sqrt(mean(du(tracking,:).^2,"all"))/ ...
    max(mean(abs(cmd(tracking,:)),"all"),50)/120;
row.road_rms = sqrt(mean(road(roadActive,:).^2,"all"));
row.normal_force_rms_variation = sqrt(mean((fz(roadActive,:)- ...
    mean(fz(roadActive,:),1)).^2,"all")) / ...
    max(double(v.vehicle_mass)*9.81/4,1);
row.speed_error_report_error = sqrt(mean((u(:,9)- ...
    (double(v.speed_reference)-vx)).^2))/max(abs(double(v.speed_reference)),1);
expectedIndicator = double(t>=eventStart & t<eventEnd);
row.loss_indicator_error = mean(abs(u(:,10)-expectedIndicator));
loss = double(v.drive_loss_fraction);
contractWindow = t>=eventStart+.15 & t<eventEnd-.05;
if nnz(contractWindow)<20
    contractWindow = t>=eventStart & t<eventEnd;
end
cmdLeft = cmd(contractWindow,[1 3]);
cmdRight = cmd(contractWindow,[2 4]);
deliveredLeft = delivered(contractWindow,[1 3]);
deliveredRight = delivered(contractWindow,[2 4]);
leftGain = sum(cmdLeft.*deliveredLeft,"all") / ...
    max(sum(cmdLeft.^2,"all"),25^2);
rightGain = sum(cmdRight.*deliveredRight,"all") / ...
    max(sum(cmdRight.^2,"all"),25^2);
row.loss_delivery_error = abs(rightGain/max(leftGain,.05)-(1-loss));
row.recovery_time = local_recovery(t,vx,double(v.speed_reference),eventEnd);
event = t>=eventStart & t<eventEnd;
pre = t>=max(.5,eventStart-.70) & t<eventStart-.10;
if nnz(event)>=20 && nnz(pre)>=20
    row.event_speed_error_peak = ...
        max(abs(vx(event)-double(v.speed_reference)))/ ...
        max(abs(double(v.speed_reference)),1);
    rightPre = mean(abs(cmd(pre,[2 4])),"all");
    rightEvent = mean(abs(cmd(event,[2 4])),"all");
    row.event_command_response = ...
        abs(rightEvent-rightPre)/max(rightPre,50);
else
    row.event_speed_error_peak = 1;
    row.event_command_response = 0;
end

gross = max(abs([b,a,w,u]),[],"all")<1e8;
domain = all(vx>=-1e-6) && all(fz>=-1e-5,"all") && ...
    row.normal_force_peak_ratio<=4.0 && row.slip_peak<=3.0 && ...
    row.pitch_peak<=1.2 && row.roll_peak<=1.2;
row.valid = gross && domain && row.initial_speed_error<=.20 && ...
    all(isfinite(struct_numeric(row)));
if ~row.valid, row.error = "PHYSICAL_OR_OUTPUT_DOMAIN_INVALID"; end
end

function [suite,pairs] = measure_suite(runs,rows,def)
longBase=[]; longForce=[]; longDrag=[]; accelResidual=[];
wheelCentered=[]; wheelBackward=[]; wheelForce=[]; wheelTorque=[]; wheelSpeed=[];
slipError=[]; verticalLeft=[]; verticalRight=[];
rollX=[]; rollMoment=[];
for k = 1:numel(runs)
    if ~runs(k).valid, continue; end
    run=runs(k); t=run.t; b=run.body; a=run.axle;
    w=run.wheel; u=run.actuation; m=double(run.inputs.vehicle_mass);
    vx=b(:,2); fx=w(:,13:16); fz=w(:,9:12);
    omega=w(:,1:4); delivered=u(:,5:8);
    mask=t>=.35 & vx>.75;
    stride=max(1,round(.01/median(diff(t))));
    idx=find(mask);idx=idx(1:stride:end);
    dv=local_derivative(vx,t); db=local_backward_derivative(vx,t);
    use=(dv+db)/2;
    longBase=[longBase;m*use(idx)]; %#ok<AGROW>
    longForce=[longForce;sum(fx(idx,:),2)]; %#ok<AGROW>
    longDrag=[longDrag;vx(idx).^2]; %#ok<AGROW>
    accelResidual=[accelResidual;b(idx,9)-use(idx)]; %#ok<AGROW>

    domega=local_derivative(omega,t);
    domegaBack=local_backward_derivative(omega,t);
    wheelCentered=[wheelCentered;domega(idx,:)]; %#ok<AGROW>
    wheelBackward=[wheelBackward;domegaBack(idx,:)]; %#ok<AGROW>
    wheelForce=[wheelForce;fx(idx,:)]; %#ok<AGROW>
    wheelTorque=[wheelTorque;delivered(idx,:)]; %#ok<AGROW>
    wheelSpeed=[wheelSpeed;omega(idx,:)]; %#ok<AGROW>
    kSlip=(.34*omega-vx)./max(max(abs(.34*omega),abs(vx)),.7);
    slipError=[slipError;abs(w(:,5:8)-kSlip)]; %#ok<AGROW>

    azb=local_derivative(b(:,4),t);
    azf=local_derivative(a(:,2),t);
    azr=local_derivative(a(:,6),t);
    verticalLeft=[verticalLeft; ...
        .78*m*azb(idx)+.11*m*azf(idx)+.11*m*azr(idx)]; %#ok<AGROW>
    verticalRight=[verticalRight;sum(fz(idx,:),2)-m*9.81]; %#ok<AGROW>

    pdd=local_derivative(b(:,8),t);
    pfdd=local_derivative(a(:,4),t);
    prdd=local_derivative(a(:,8),t);
    rollX=[rollX;pdd(idx),pfdd(idx),prdd(idx)]; %#ok<AGROW>
    rollMoment=[rollMoment; ...
        .8*(fz(idx,1)-fz(idx,2)+fz(idx,3)-fz(idx,4))/m]; %#ok<AGROW>
end

[suite.longitudinal_balance_error,suite.fitted_drag] = ...
    longitudinal_fit(longBase,longForce,longDrag);
suite.reported_acceleration_error = sqrt(mean(accelResidual.^2))/ ...
    max(sqrt(mean((longBase/1600).^2)),1);
[cErr,cFit] = wheel_fit(wheelCentered,wheelForce,wheelTorque,wheelSpeed);
[bErr,bFit] = wheel_fit(wheelBackward,wheelForce,wheelTorque,wheelSpeed);
if bErr<cErr
    suite.wheel_balance_error=bErr;suite.wheel_fit=bFit;
    suite.wheel_derivative="backward";
else
    suite.wheel_balance_error=cErr;suite.wheel_fit=cFit;
    suite.wheel_derivative="centered";
end
suite.slip_kinematic_error=median(slipError,"all");
suite.vertical_balance_error=sqrt(mean((verticalLeft-verticalRight).^2))/ ...
    max(sqrt(mean(verticalRight.^2)),500);
[suite.roll_balance_error,suite.roll_inertia_fit, ...
    suite.roll_positive_inertia] = roll_fit(rollX,rollMoment);
suite.static_state_evidence = double(any([rows.body_vertical_accel_rms]>.02) && ...
    any([rows.normal_force_rms_variation]>.005));

pairs = struct;
pairs.target_response = target_pair(runs,rows);
pairs.road_response = road_pair(runs,rows);
pairs.fault_response = fault_pair(runs,rows,def);
end

function groups = compute_groups(rows,suite,pairs,static,def,G)
groups = struct("G",double(G),"A",0,"Q",0,"M",0,"R",0,"D",0);
if ~G, return; end
n = rows(string({rows.id})=="nominal");
qTrack=quality(n.speed_tracking_nrmse,.018,.12);
qFinal=quality(n.final_speed_error,.012,.10);
qRide=quality(n.body_vertical_accel_rms,.75,3.4);
qAtt=quality(max(n.pitch_peak,n.roll_peak),.08,.32);
groups.A=clip(.52*qTrack+.18*qFinal+.18*qRide+.12*qAtt);

qContact=quality(n.lift_fraction,.002,.18);
qSlip=quality(n.slip_p95,.10,.45);
qTorque=quality(n.command_ratio_peak,.96,1.04);
qRipple=quality(n.command_ripple,.08,.55);
groups.Q=clip(.32*qContact+.30*qSlip+.22*qTorque+.16*qRipple);

qLong=quality(suite.longitudinal_balance_error,.035,.28);
qWheel=quality(suite.wheel_balance_error,.06,.38);
qSlipKin=quality(suite.slip_kinematic_error,.012,.10);
qVert=quality(suite.vertical_balance_error,.06,.38);
qRoll=quality(suite.roll_balance_error,.10,.55)*suite.roll_positive_inertia;
qReport=quality(max([rows.speed_error_report_error]),.005,.08);
qFaultContract=quality(max([rows.loss_delivery_error]),.01,.12);
qStatic=.65*double(static.dynamic_state_evidence)+ ...
    .35*double(static.output_contract_connected);
groups.M=clip(.16*qLong+.17*qWheel+.13*qSlipKin+.16*qVert+ ...
    .10*qRoll+.07*qReport+.06*qFaultContract+.05*qStatic+ ...
    .05*pairs.target_response.score+.05*pairs.road_response.score);
groups.M=min(groups.M,.40+.60*pairs.target_response.score);
groups.M=min(groups.M,.40+.60*pairs.road_response.score);

rangeMask=ismember(string({rows.id}),def.range_scenario_ids);
rangeRows=rows(rangeMask);
rq=zeros(1,numel(rangeRows));
for k=1:numel(rangeRows)
    r=rangeRows(k);
    rq(k)=.42*quality(r.speed_tracking_nrmse,.035,.18)+ ...
        .18*quality(r.lift_fraction,.01,.25)+ ...
        .16*quality(r.slip_p95,.16,.60)+ ...
        .14*quality(max(r.pitch_peak,r.roll_peak),.15,.48)+ ...
        .10*quality(r.command_ratio_peak,.98,1.05);
end
groups.R=clip(min(rq));

dynamicMask=ismember(string({rows.id}),def.dynamic_scenario_ids);
dynamicRows=rows(dynamicMask);
dq=zeros(1,numel(dynamicRows));
for k=1:numel(dynamicRows)
    r=dynamicRows(k);
    dq(k)=.38*quality(r.recovery_time,.35,2.4)+ ...
        .24*quality(r.event_speed_error_peak,.04,.22)+ ...
        .20*quality(r.loss_delivery_error,.01,.12)+ ...
        .18*quality(r.loss_indicator_error,.002,.05);
end
groups.D=clip(.75*min(dq)+.25*pairs.fault_response.score);
groups.D=min(groups.D,.35+.65*pairs.fault_response.score);
end

function pair = target_pair(runs,rows)
pair=struct("valid",false,"speed_separation",0, ...
    "torque_separation",0,"score",0);
lo=find(string({runs.id})=="target_probe_low",1);
hi=find(string({runs.id})=="target_probe_high",1);
if isempty(lo)||isempty(hi)||~runs(lo).valid||~runs(hi).valid,return;end
tl=runs(lo).t; th=runs(hi).t;
ml=tl>=2.5&tl<=6.3;mh=th>=2.5&th<=6.3;
cl=tl>=.15&tl<=1.25;ch=th>=.15&th<=1.25;
vLo=mean(runs(lo).body(ml,2));vHi=mean(runs(hi).body(mh,2));
tLo=mean(runs(lo).actuation(cl,1:4),"all");
tHi=mean(runs(hi).actuation(ch,1:4),"all");
pair.speed_separation=vHi-vLo;
pair.torque_separation=tHi-tLo;
pair.valid=all([rows([lo hi]).valid]);
pair.score=clip(.65*quality(1/max(pair.speed_separation,1e-9),1/4.0,1/.8)+ ...
    .35*quality(1/max(pair.torque_separation,1e-9),1/250,1/35));
end

function pair = road_pair(runs,rows)
pair=struct("valid",false,"road_rms_ratio",0, ...
    "vertical_response_ratio",0,"normal_response_ratio",0,"score",0);
lo=find(string({runs.id})=="road_probe_low",1);
hi=find(string({runs.id})=="road_probe_high",1);
if isempty(lo)||isempty(hi)||~runs(lo).valid||~runs(hi).valid,return;end
rLo=rows(lo);rHi=rows(hi);
pair.road_rms_ratio=rHi.road_rms/max(rLo.road_rms,1e-9);
pair.vertical_response_ratio=rHi.body_vertical_accel_rms/ ...
    max(rLo.body_vertical_accel_rms,1e-9);
pair.normal_response_ratio=rHi.normal_force_rms_variation/ ...
    max(rLo.normal_force_rms_variation,1e-9);
pair.valid=true;
qRoad=quality(1/max(pair.road_rms_ratio,1e-9),1/3.5,1/1.4);
qBody=quality(1/max(pair.vertical_response_ratio,1e-9),1/1.8,1/1.1);
qNormal=quality(1/max(pair.normal_response_ratio,1e-9),1/1.8,1/1.1);
pair.score=clip(.40*qRoad+.30*qBody+.30*qNormal);
end

function pair = fault_pair(runs,rows,def)
pair=struct("valid",false,"requested_torque_change",0, ...
    "delivered_torque_change",0,"speed_effect",0, ...
    "loss_contract_error",1,"recovery_time",Inf,"score",0);
no=find(string({runs.id})=="fault_pair_none",1);
loss=find(string({runs.id})=="fault_pair_loss",1);
if isempty(no)||isempty(loss)||~runs(no).valid||~runs(loss).valid,return;end
t=runs(loss).t; start=double(runs(loss).inputs.drive_loss_time);
stop=start+def.public_constants.drive_loss_duration_s;
event=t>=start+.08&t<=stop-.08;
cmdNo=mean(abs(runs(no).actuation(event,[2 4])),"all");
cmdLoss=mean(abs(runs(loss).actuation(event,[2 4])),"all");
delNo=mean(abs(runs(no).actuation(event,[6 8])),"all");
delLoss=mean(abs(runs(loss).actuation(event,[6 8])),"all");
pair.requested_torque_change=abs(cmdLoss-cmdNo)/max(cmdNo,50);
pair.delivered_torque_change=abs(delLoss-delNo)/max(delNo,50);
pair.speed_effect=max(abs(runs(loss).body(event,2)- ...
    runs(no).body(event,2)))/max(double(runs(loss).inputs.speed_reference),1);
pair.loss_contract_error=rows(loss).loss_delivery_error;
pair.recovery_time=rows(loss).recovery_time;
pair.valid=true;
qCommand=quality(1/max(pair.requested_torque_change,1e-9),1/.18,1/.025);
qPhysical=quality(1/max(max(pair.delivered_torque_change,pair.speed_effect),1e-9), ...
    1/.06,1/.008);
qContract=quality(pair.loss_contract_error,.01,.12);
qRecovery=quality(pair.recovery_time,.35,2.4);
pair.score=clip(.30*qCommand+.25*qPhysical+.25*qContract+.20*qRecovery);
end

function audit = static_audit(model,def)
audit=struct("output_contract_connected",false, ...
    "output_log_count",0,"direct_command_log_count",0, ...
    "public_input_reference_count",0,"dynamic_state_evidence",false, ...
    "stateful_block_count",0,"matlab_function_count",0, ...
    "output_sources",strings(0,1));
logs=find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "BlockType","ToWorkspace");
required=string({def.outputs.name});
found=strings(0,1);sources=strings(0,1);direct=0;
for k=1:numel(logs)
    name=string(get_param(logs{k},"VariableName"));
    if ~ismember(name,required),continue;end
    found(end+1)=name; %#ok<AGROW>
    try
        ph=get_param(logs{k},"PortHandles");
        line=get_param(ph.Inport(1),"Line");
        src=get_param(line,"SrcBlockHandle");
        srcPath=string(getfullname(src));
        sources(end+1)=srcPath; %#ok<AGROW>
        srcType=string(get_param(src,"BlockType"));
        if ismember(srcType,["Constant","FromWorkspace","Step","Ramp"])
            direct=direct+1;
        end
    catch
        sources(end+1)="UNCONNECTED"; %#ok<AGROW>
    end
end
audit.output_log_count=numel(found);
audit.output_contract_connected=all(ismember(required,found)) && ...
    numel(unique(found))==numel(required) && ...
    ~any(sources=="UNCONNECTED");
audit.direct_command_log_count=direct;
audit.output_sources=sources;

blocks=find_system(model,"LookUnderMasks","all","FollowLinks","on", ...
    "Type","Block");
refs=0;
for k=1:numel(blocks)
    try
        value=string(get_param(blocks{k},"Value"));
        refs=refs+sum(value==string({def.public_inputs.name}));
    catch
    end
end
audit.public_input_reference_count=refs;
stateTypes=["Integrator","DiscreteIntegrator","UnitDelay","Memory","Delay", ...
    "StateSpace","DiscreteStateSpace","TransferFcn","DiscreteTransferFcn"];
types=strings(numel(blocks),1);
for k=1:numel(blocks)
    try,types(k)=string(get_param(blocks{k},"BlockType"));catch,end
end
audit.stateful_block_count=nnz(ismember(types,stateTypes));
charts=find(sfroot,"-isa","Stateflow.EMChart");
keep=false(size(charts));persistentState=false;
for k=1:numel(charts)
    keep(k)=startsWith(string(charts(k).Path),model+"/");
    if keep(k)
        try,persistentState=persistentState||contains(string(charts(k).Script),"persistent");catch,end
    end
end
audit.matlab_function_count=nnz(keep);
audit.dynamic_state_evidence=audit.stateful_block_count>0||persistentState;
end

function [err,cDrag] = longitudinal_fit(base,force,drag)
err=1;cDrag=NaN;
if numel(base)<100,return;end
y=force-base;
cDrag=max((drag'*y)/max(drag'*drag,eps),0);
residual=base-force+cDrag*drag;
err=sqrt(mean(residual.^2))/max(sqrt(mean(base.^2)),500);
end

function [err,fit] = wheel_fit(accel,force,torque,speed)
err=1;fit=struct("inertia",NaN,"viscous_loss",NaN, ...
    "positive_parameters",false);
if numel(accel)<400,return;end
X=[accel(:),speed(:)];Y=torque(:)-.34*force(:);
beta=X\Y;pred=X*beta;
residual=sqrt(mean((Y-pred).^2))/max(sqrt(mean(Y.^2)),100);
positive=double(all(beta>=0));
err=max(residual,1-positive);
fit=struct("inertia",beta(1),"viscous_loss",beta(2), ...
    "positive_parameters",logical(positive));
end

function [err,beta,positive] = roll_fit(X,y)
err=1;beta=nan(3,1);positive=false;
if size(X,1)<100,return;end
ridge=1e-8*eye(3);
beta=(X'*X+ridge)\(X'*y);
pred=X*beta;
residual=sqrt(mean((y-pred).^2))/max(sqrt(mean(y.^2)),.02);
positive=all(beta>0);
err=max(residual,double(~positive));
end

function reasons = failure_reasons(rows,suite,pairs,static,G)
reasons=strings(0,1);
if ~G,reasons(end+1)="GATE_OR_SCENARIO_FAILURE";end
for k=1:numel(rows)
    if ~rows(k).valid
        reasons(end+1)="SCENARIO:"+rows(k).id+":"+rows(k).error; %#ok<AGROW>
    end
end
if ~static.output_contract_connected
    reasons(end+1)="OUTPUT_CONNECTION_CONTRACT_FAILED";
end
if ~static.dynamic_state_evidence
    reasons(end+1)="NO_CAUSAL_DYNAMIC_STATE_EVIDENCE";
end
if suite.longitudinal_balance_error>.28
    reasons(end+1)="LONGITUDINAL_FORCE_BALANCE_FAILED";
end
if suite.wheel_balance_error>.38
    reasons(end+1)="WHEEL_TORQUE_BALANCE_FAILED";
end
if suite.vertical_balance_error>.38
    reasons(end+1)="VERTICAL_FORCE_BALANCE_FAILED";
end
if ~pairs.target_response.valid||pairs.target_response.score<.25
    reasons(end+1)="CLOSED_LOOP_TARGET_RESPONSE_FAILED";
end
if ~pairs.road_response.valid||pairs.road_response.score<.25
    reasons(end+1)="ROAD_TO_SUSPENSION_CAUSAL_RESPONSE_FAILED";
end
if ~pairs.fault_response.valid||pairs.fault_response.score<.20
    reasons(end+1)="ACTUATOR_LOSS_CAUSAL_RESPONSE_FAILED";
end
reasons=unique(reasons,"stable");
end

function dt = local_recovery(t,speed,target,eventEnd)
dt=max(t(end)-eventEnd+1,0);
start=find(t>=eventEnd,1);
if isempty(start),return;end
window=max(5,round(.35/median(diff(t))));
good=abs(speed-target)<=max(.45,.045*abs(target));
for k=start:max(start,numel(t)-window+1)
    if all(good(k:k+window-1))
        dt=t(k)-eventEnd;
        return
    end
end
end

function y = normalize_data(ts)
y=double(ts.Data);
n=numel(ts.Time);
if isvector(y)
    y=reshape(y,n,[]);
elseif size(y,1)~=n && size(y,ndims(y))==n
    order=[ndims(y),1:ndims(y)-1];
    y=permute(y,order);
end
y=reshape(y,n,[]);
end

function d = local_derivative(y,t)
d=zeros(size(y));
if numel(t)<3,return;end
d(1,:)=(y(2,:)-y(1,:))/(t(2)-t(1));
d(end,:)=(y(end,:)-y(end-1,:))/(t(end)-t(end-1));
d(2:end-1,:)=(y(3:end,:)-y(1:end-2,:))./ ...
    (t(3:end)-t(1:end-2));
end

function d = local_backward_derivative(y,t)
d=zeros(size(y));
if numel(t)<2,return;end
d(1,:)=(y(2,:)-y(1,:))/(t(2)-t(1));
d(2:end,:)=(y(2:end,:)-y(1:end-1,:))./ ...
    (t(2:end)-t(1:end-1));
end

function value = local_percentile(x,p)
x=sort(double(x(:)));
if isempty(x),value=NaN;return;end
index=1+(numel(x)-1)*p/100;
lo=floor(index);hi=ceil(index);
if lo==hi,value=x(lo);
else,value=x(lo)+(index-lo)*(x(hi)-x(lo));
end
end

function q = quality(value,good,bad)
if ~isfinite(value),q=0;return;end
if bad<=good,q=double(value<=good);return;end
q=min(max(1-(value-good)/(bad-good),0),1);
end

function value = clip(value)
value=min(max(double(value),0),1);
end

function values = nominal_values(def)
values=struct;
for k=1:numel(def.public_inputs)
    values.(def.public_inputs(k).name)=def.public_inputs(k).nominal;
end
end

function values = struct_numeric(s)
names=fieldnames(s);values=[];
for k=1:numel(names)
    v=s.(names{k});
    if isnumeric(v)&&~isempty(v),values=[values,double(v(:)')];end %#ok<AGROW>
end
end

function run = empty_run
run=struct("id","","inputs",struct,"stage","created","valid",false, ...
    "error","","t",[],"body",[],"axle",[],"wheel",[],"actuation",[]);
end

function row = empty_row
row=struct("id","","valid",false,"error","", ...
    "initial_speed_error",NaN,"speed_tracking_nrmse",NaN, ...
    "final_speed_error",NaN,"body_vertical_accel_rms",NaN, ...
    "body_longitudinal_accel_peak",NaN,"pitch_peak",NaN, ...
    "roll_peak",NaN,"heave_peak",NaN,"axle_heave_peak",NaN, ...
    "lift_fraction",NaN,"normal_force_peak_ratio",NaN, ...
    "slip_p95",NaN,"slip_peak",NaN,"command_ratio_peak",NaN, ...
    "command_ripple",NaN,"road_rms",NaN, ...
    "normal_force_rms_variation",NaN, ...
    "speed_error_report_error",NaN,"loss_indicator_error",NaN, ...
    "loss_delivery_error",NaN,"recovery_time",NaN, ...
    "event_speed_error_peak",NaN,"event_command_response",NaN);
end

function receipt = empty_receipt(def,modelPath)
receipt=struct( ...
    "schema","simuverity.formal90-f90-xauto02-score.v1", ...
    "task_id",def.formal_id, ...
    "status","CURRENT", ...
    "model_path",modelPath, ...
    "model_file_presence","", ...
    "valid",false, ...
    "load_pass",false, ...
    "update_pass",false, ...
    "compile_pass",false, ...
    "total",0, ...
    "groups",struct("G",0,"A",0,"Q",0,"M",0,"R",0,"D",0), ...
    "score_formula","", ...
    "static_audit",struct, ...
    "scenarios",struct([]), ...
    "metric_values",struct, ...
    "failure_reasons",strings(0,1), ...
    "error_identifier","", ...
    "error_message","", ...
    "error_report","");
end

function local_set_base(values)
evalin("base","clearvars; clear global");
names=fieldnames(values);
for k=1:numel(names),assignin("base",names{k},values.(names{k}));end
end

function snapshot = local_snapshot_base
names=evalin("base","who");values=cell(size(names));
for k=1:numel(names),values{k}=evalin("base",names{k});end
snapshot=struct("names",{names},"values",{values});
end

function local_restore_base(snapshot)
try
    evalin("base","clearvars");
    for k=1:numel(snapshot.names)
        assignin("base",snapshot.names{k},snapshot.values{k});
    end
catch
end
end

function local_close(model)
try
    if bdIsLoaded(model), close_system(model,0); end
catch
end
end

function local_write_json(path,value)
fid=fopen(path,"w","n","UTF-8");
assert(fid>=0,"F90_XAUTO02_RECEIPT_WRITE_FAILED:%s",path);
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fwrite(fid,jsonencode(value,PrettyPrint=true),"char");
end

function value = local_now
value=string(datetime("now","TimeZone","Asia/Shanghai", ...
    "Format","yyyy-MM-dd'T'HH:mm:ssXXX"));
end
