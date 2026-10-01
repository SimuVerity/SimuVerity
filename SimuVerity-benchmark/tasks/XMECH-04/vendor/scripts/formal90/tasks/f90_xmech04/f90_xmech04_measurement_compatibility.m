function varargout = f90_xmech04_measurement_compatibility(helperName, varargin)
%f90_xmech04_measurement_compatibility R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xmech04_measurement_compatibility:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["empty_row", "measure_run", "measure_pair"];
        end
    case "empty_row"
        if nargout == 0
            empty_row(varargin{:});
        else
            [varargout{1:nargout}] = empty_row(varargin{:});
        end
    case "measure_run"
        if nargout == 0
            measure_run(varargin{:});
        else
            [varargout{1:nargout}] = measure_run(varargin{:});
        end
    case "measure_pair"
        if nargout == 0
            measure_pair(varargin{:});
        else
            [varargout{1:nargout}] = measure_pair(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xmech04_measurement_compatibility:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function r=empty_row()
r=struct('scenario',"",'valid',false, ...
    'is_no_disturbance_control',false, ...
    'final_position_error_cm',NaN,'final_wrist_error_deg',NaN, ...
    'final_speed_rms',NaN,'tail_joint_ripple_rad',NaN, ...
    'tail_torque_ripple_ratio',NaN,'torque_excess_ratio',NaN, ...
    'derivative_residual',NaN,'position_closure_cm',NaN, ...
    'motion_activity_rad',NaN,'actuator_activity_ratio',NaN);
end

function r=measure_run(run)
r=empty_row();
r.scenario=string(run.scenario);
r.is_no_disturbance_control=endsWith(r.scenario,"_no_disturbance");
if string(run.stage)~="simulated",return;end
[t,state,ok1]=xp9_series(run,'joint_state',12);
[tp,pose,ok2]=xp9_series(run,'end_effector_pose',6);
[tt,tau,ok3]=xp9_series(run,'joint_torque',6);
if ~(ok1&&ok2&&ok3&&t(1)<=.01&&t(end)>=5.95),return;end
pose=interp1(tp,pose,t,'linear','extrap');
tau=interp1(tt,tau,t,'linear','extrap');
if any(abs(state(:,1:6))>4*pi,'all')|| ...
        any(abs(state(:,7:12))>80,'all')|| ...
        any(abs(pose(:,1:3))>1e4,'all')|| ...
        any(abs(tau)>1e4,'all')
    return
end
moveTime=double(run.inputs.move_time);
tail=t>=max([moveTime+.8,5.15,t(end)-.75]);
dynamic=t>=.10&t<=min(t(end)-.05,moveTime+.8);
if nnz(tail)<25||nnz(dynamic)<50,return;end
target=reshape(double(run.inputs.target_xyz_cm),1,3);
qGoal=target_q(target,double(run.inputs.wrist_target_deg));
limits=[80 70 60 22 18 14]*double(run.inputs.torque_limit_scale);

r.final_position_error_cm=norm(mean(pose(tail,1:3),1)-target);
r.final_wrist_error_deg=max(abs(wrap_degrees( ...
    (mean(state(tail,4:6),1)-qGoal(4:6))*180/pi)));
r.final_speed_rms=sqrt(mean(state(tail,7:12).^2,'all'));
r.tail_joint_ripple_rad=max(std(state(tail,1:6),0,1));
r.tail_torque_ripple_ratio=max(std(tau(tail,:),0,1)./limits);
r.torque_excess_ratio=max(max(abs(tau)./limits-1,0),[],'all');

dqEstimate=local_rate(state(:,1:6),t);
scale=max(sqrt(mean(state(dynamic,7:12).^2,'all')),.12);
r.derivative_residual=sqrt(mean( ...
    (dqEstimate(dynamic,:)-state(dynamic,7:12)).^2,'all'))/scale;
expectedPosition=serial_position(state(:,1:3));
r.position_closure_cm=sqrt(mean( ...
    (expectedPosition(dynamic,:)-pose(dynamic,1:3)).^2,'all'));
r.motion_activity_rad=max(max(state(:,1:6),[],1)- ...
    min(state(:,1:6),[],1));
r.actuator_activity_ratio=max(local_quantile(abs(tau)./limits,.90));
r.valid=all(isfinite([r.final_position_error_cm ...
    r.final_wrist_error_deg r.final_speed_rms ...
    r.tail_joint_ripple_rad r.tail_torque_ripple_ratio ...
    r.torque_excess_ratio r.derivative_residual ...
    r.position_closure_cm r.motion_activity_rad ...
    r.actuator_activity_ratio]));
end

function pair=measure_pair(runs,rows,disturbedName,controlName)
pair=empty_pair();
names=string({runs.scenario});
iD=find(names==disturbedName,1);
iC=find(names==controlName,1);
if isempty(iD)||isempty(iC)||~rows(iD).valid||~rows(iC).valid,return;end
[t,sD,ok1]=xp9_series(runs(iD),'joint_state',12);
[tc,sC,ok2]=xp9_series(runs(iC),'joint_state',12);
[tp,pD,ok3]=xp9_series(runs(iD),'end_effector_pose',6);
[tpc,pC,ok4]=xp9_series(runs(iC),'end_effector_pose',6);
[tt,aD,ok5]=xp9_series(runs(iD),'joint_torque',6);
[ttc,aC,ok6]=xp9_series(runs(iC),'joint_torque',6);
if ~(ok1&&ok2&&ok3&&ok4&&ok5&&ok6),return;end
sC=interp1(tc,sC,t,'linear','extrap');
pD=interp1(tp,pD,t,'linear','extrap');
pC=interp1(tpc,pC,t,'linear','extrap');
aD=interp1(tt,aD,t,'linear','extrap');
aC=interp1(ttc,aC,t,'linear','extrap');
eventStart=double(runs(iD).inputs.disturbance_start);eventEnd=eventStart+.35;
event=t>=eventStart&t<=eventEnd+.30;
post=t>=max(eventEnd+.75,double(runs(iD).inputs.move_time)+.35);
if nnz(event)<20||nnz(post)<20,return;end
qDiff=vecnorm(sD(:,1:6)-sC(:,1:6),2,2);
pDiff=vecnorm(pD(:,1:3)-pC(:,1:3),2,2);
limits=[80 70 60 22 18 14]*double(runs(iD).inputs.torque_limit_scale);
tauEvidence=max(abs(aD(event,:)-aC(event,:))./limits,[],'all');
stateEvidence=max(qDiff(event))/max(sqrt(6),1);
pair.event_evidence=max(tauEvidence,stateEvidence);
pair.peak_position_divergence_cm=max(pDiff(event));
pair.post_position_divergence_cm=median(pDiff(post));
pair.recovery_time_s=paired_recovery(t,qDiff,pDiff,eventEnd);
pair.core_event_present=isfinite(pair.event_evidence)&& ...
    pair.event_evidence>1e-8;
pair.valid=pair.core_event_present&&all(isfinite([ ...
    pair.event_evidence pair.peak_position_divergence_cm ...
    pair.post_position_divergence_cm]))&& ...
    ~isnan(pair.recovery_time_s);
end

function q=target_q(target,wrist)
x=target(1);y=target(2);z=target(3)-10;radial=hypot(x,y);
c3=(radial^2+z^2-50^2-30^2)/(2*50*30);
c3=min(max(c3,-.999999),.999999);elbow=-acos(c3);
q=zeros(1,6);q(1)=atan2(y,x);
q(2)=atan2(z,radial)-atan2(30*sin(elbow),50+30*cos(elbow));
q(3)=-elbow;q(4:6)=reshape(wrist,1,3)*pi/180;
end

function p=serial_position(q)
radial=50*cos(q(:,2))+30*cos(q(:,2)-q(:,3));
p=[radial.*cos(q(:,1)),radial.*sin(q(:,1)), ...
    10+50*sin(q(:,2))+30*sin(q(:,2)-q(:,3))];
end

function dx=local_rate(x,t)
dx=zeros(size(x));
for j=1:size(x,2)
    dx(:,j)=gradient(x(:,j),t);
end
end

function d=wrap_degrees(d)
d=mod(d+180,360)-180;
end

function q=local_quantile(x,p)
x=sort(double(x),1);n=size(x,1);
if n==0,q=NaN(1,max(1,size(x,2)));return;end
k=max(1,min(n,ceil(p*n)));q=x(k,:);
end

function dt=paired_recovery(t,qDiff,pDiff,eventEnd)
dt=Inf;start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.20/median(diff(t))));
good=qDiff<=.04&pDiff<=1.0;
for k=start:max(start,numel(t)-window+1)
    if k+window-1<=numel(t)&&all(good(k:k+window-1))
        dt=t(k)-eventEnd;return
    end
end
end

function p=empty_pair()
p=struct('valid',false,'core_event_present',false, ...
    'event_evidence',NaN,'peak_position_divergence_cm',NaN, ...
    'post_position_divergence_cm',NaN,'recovery_time_s',NaN);
end
