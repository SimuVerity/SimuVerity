function varargout = f90_xauto02_measurement_compatibility(helperName, varargin)
%F90_XAUTO02_MEASUREMENT_COMPATIBILITY R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xauto02_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["run_scenario", "measure_run", "static_audit", "nominal_values", "empty_run", "empty_row", "local_set_base", "local_snapshot_base", "local_restore_base", "local_derivative", "local_backward_derivative", "longitudinal_fit", "wheel_fit", "roll_fit"];
        end
    case "run_scenario"
        if nargout == 0
            run_scenario(varargin{:});
        else
            [varargout{1:nargout}] = run_scenario(varargin{:});
        end
    case "measure_run"
        if nargout == 0
            measure_run(varargin{:});
        else
            [varargout{1:nargout}] = measure_run(varargin{:});
        end
    case "static_audit"
        if nargout == 0
            static_audit(varargin{:});
        else
            [varargout{1:nargout}] = static_audit(varargin{:});
        end
    case "nominal_values"
        if nargout == 0
            nominal_values(varargin{:});
        else
            [varargout{1:nargout}] = nominal_values(varargin{:});
        end
    case "empty_run"
        if nargout == 0
            empty_run(varargin{:});
        else
            [varargout{1:nargout}] = empty_run(varargin{:});
        end
    case "empty_row"
        if nargout == 0
            empty_row(varargin{:});
        else
            [varargout{1:nargout}] = empty_row(varargin{:});
        end
    case "local_set_base"
        if nargout == 0
            local_set_base(varargin{:});
        else
            [varargout{1:nargout}] = local_set_base(varargin{:});
        end
    case "local_snapshot_base"
        if nargout == 0
            local_snapshot_base(varargin{:});
        else
            [varargout{1:nargout}] = local_snapshot_base(varargin{:});
        end
    case "local_restore_base"
        if nargout == 0
            local_restore_base(varargin{:});
        else
            [varargout{1:nargout}] = local_restore_base(varargin{:});
        end
    case "local_derivative"
        if nargout == 0
            local_derivative(varargin{:});
        else
            [varargout{1:nargout}] = local_derivative(varargin{:});
        end
    case "local_backward_derivative"
        if nargout == 0
            local_backward_derivative(varargin{:});
        else
            [varargout{1:nargout}] = local_backward_derivative(varargin{:});
        end
    case "longitudinal_fit"
        if nargout == 0
            longitudinal_fit(varargin{:});
        else
            [varargout{1:nargout}] = longitudinal_fit(varargin{:});
        end
    case "wheel_fit"
        if nargout == 0
            wheel_fit(varargin{:});
        else
            [varargout{1:nargout}] = wheel_fit(varargin{:});
        end
    case "roll_fit"
        if nargout == 0
            roll_fit(varargin{:});
        else
            [varargout{1:nargout}] = roll_fit(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xauto02_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
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
        ts = simuverity_public_output_compatibility( ...
            out,outputNames(k),def.outputs(k).channels, ...
            AllowBaseWorkspace=true);
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

function values = nominal_values(def)
values=struct;
for k=1:numel(def.public_inputs)
    values.(def.public_inputs(k).name)=def.public_inputs(k).nominal;
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

function local_set_base(values)
evalin("base","clearvars; clear global");
if strlength(string(getenv( ...
        "SIMUVERITY_CANDIDATE_DEPENDENCY_MANIFEST"))) > 0
    assert(exist("simuverity_reload_candidate_dependencies","file") == 2, ...
        "F90_XAUTO02_CANDIDATE_DEPENDENCY_RELOAD_HELPER_MISSING");
    simuverity_reload_candidate_dependencies();
end
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

function value = local_percentile(x,p)
x=sort(double(x(:)));
if isempty(x),value=NaN;return;end
index=1+(numel(x)-1)*p/100;
lo=floor(index);hi=ceil(index);
if lo==hi,value=x(lo);
else,value=x(lo)+(index-lo)*(x(hi)-x(lo));
end
end

function values = struct_numeric(s)
names=fieldnames(s);values=[];
for k=1:numel(names)
    v=s.(names{k});
    if isnumeric(v)&&~isempty(v),values=[values,double(v(:)')];end %#ok<AGROW>
end
end
