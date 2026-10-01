function out=xp9_score_xmech04(runs,spec)
%XP9_SCORE_XMECH04 Six-axis torque-controlled serial-arm score.
% The score is representation neutral: final task performance, measured
% joint/pose consistency, actuator bounds, worst official operating point,
% and a same-input disturbance/no-disturbance pair.  Controller form and
% inverse-kinematics implementation are not inspected.
rows=repmat(empty_row(),numel(runs),1);allValid=true;
for i=1:numel(runs)
    rows(i)=measure_run(runs(i));
    allValid=allValid&&rows(i).valid;
end
out=empty_out();
out.score_inputs_valid=allValid&&numel(runs)==1+numel(spec.scenarios);
out.diagnostics_valid=out.score_inputs_valid;
out.G=out.score_inputs_valid;
if ~out.G,out.gate_reasons="SCENARIO_OR_PHYSICAL_OUTPUT_CONTRACT_INVALID";end
out.scenario_rows=rows;

if isempty(rows)
    out.A=0;out.Q=0;out.M=0;out.R=0;out.D=0;
    out.score=0;return
end

nominal=rows(1);
qPosition=xp9_utility(nominal.final_position_error_cm, ...
    [0 .50 1.50 3 7 20],[1 1 .96 .85 .50 0]);
qWrist=xp9_utility(nominal.final_wrist_error_deg, ...
    [0 .30 1 3 8 25],[1 1 .96 .82 .42 0]);
qRest=xp9_utility(nominal.final_speed_rms, ...
    [0 .01 .03 .08 .25 .8],[1 1 .96 .80 .35 0]);
out.A=xp9_group([qPosition qWrist qRest],[.58 .27 .15],true);

qBound=xp9_utility(nominal.torque_excess_ratio, ...
    [0 .001 .006 .02 .08 .30],[1 1 .94 .72 .25 0]);
qTail=xp9_utility(nominal.tail_joint_ripple_rad, ...
    [0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
qTorque=xp9_utility(nominal.tail_torque_ripple_ratio, ...
    [0 .001 .006 .025 .10 .35],[1 1 .94 .72 .25 0]);
out.Q=xp9_group([qBound qTail qTorque],[.42 .35 .23],true);

qDerivative=xp9_utility(max([rows.derivative_residual]), ...
    [0 .015 .04 .10 .28 .70],[1 1 .95 .75 .28 0]);
qPositionClosure=xp9_utility(max([rows.position_closure_cm]), ...
    [0 .02 .08 .25 .8 3],[1 1 .95 .75 .28 0]);
qMotion=xp9_utility(max([rows.motion_activity_rad]), ...
    [0 .01 .04 .12 .30 .65],[0 .35 .70 .93 1 1]);
qActuator=xp9_utility(max([rows.actuator_activity_ratio]), ...
    [0 .002 .008 .025 .07 .18],[0 .35 .72 .94 1 1]);
out.M=xp9_group([qDerivative qPositionClosure qMotion qActuator], ...
    [.28 .32 .20 .20],true);
coreMechanism=all(isfinite([qMotion qActuator]))&& ...
    max([rows.motion_activity_rad])>1e-5&& ...
    max([rows.actuator_activity_ratio])>1e-7;
if ~coreMechanism,out.M=0;end

required=~[rows.is_no_disturbance_control];
rangeUtilities=zeros(nnz(required),1);j=0;
for i=find(required)
    j=j+1;r=rows(i);
    qp=xp9_utility(r.final_position_error_cm, ...
        [0 .75 2 4.5 10 28],[1 1 .95 .76 .35 0]);
    qw=xp9_utility(r.final_wrist_error_deg, ...
        [0 .5 1.5 4 12 35],[1 1 .95 .78 .35 0]);
    qs=xp9_utility(r.final_speed_rms, ...
        [0 .015 .04 .12 .35 1],[1 1 .95 .76 .30 0]);
    qb=xp9_utility(r.torque_excess_ratio, ...
        [0 .001 .006 .02 .08 .30],[1 1 .94 .72 .25 0]);
    rangeUtilities(j)=xp9_group([qp qw qs qb],[.55 .25 .12 .08],true);
end
out.R=xp9_tail(rangeUtilities,ones(size(rangeUtilities)));

pair=measure_pair(runs,rows,"heavy_corner","heavy_corner_no_disturbance");
out.pair_metrics=pair;
if pair.valid
    qEvent=xp9_utility(pair.event_evidence, ...
        [0 1e-5 1e-4 1e-3 5e-3 .02],[0 .35 .75 .96 1 1]);
    qPeak=xp9_utility(pair.peak_position_divergence_cm, ...
        [0 .25 .8 2.5 7 20],[1 1 .95 .75 .30 0]);
    qRecovery=xp9_utility(pair.recovery_time_s, ...
        [0 .15 .35 .70 1.40 3],[1 1 .95 .75 .30 0]);
    qPost=xp9_utility(pair.post_position_divergence_cm, ...
        [0 .10 .40 1.5 5 15],[1 1 .95 .72 .25 0]);
    out.D=xp9_group([qEvent qPeak qRecovery qPost],[.15 .35 .30 .20],true);
else
    out.D=0;
end
if ~pair.core_event_present,out.D=0;end

out.utility_metrics=struct('nominal_accuracy',out.A, ...
    'nominal_quality',out.Q,'mechanism',out.M, ...
    'worst_range',out.R,'disturbance_recovery',out.D);
out.raw_metrics=rows;
w=spec.groups.weights;
out.score=xp9_total(out.G,[out.A out.Q out.M out.R out.D], ...
    [w.A w.Q w.M w.R w.D]);
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

function r=empty_row()
r=struct('scenario',"",'valid',false, ...
    'is_no_disturbance_control',false, ...
    'final_position_error_cm',NaN,'final_wrist_error_deg',NaN, ...
    'final_speed_rms',NaN,'tail_joint_ripple_rad',NaN, ...
    'tail_torque_ripple_ratio',NaN,'torque_excess_ratio',NaN, ...
    'derivative_residual',NaN,'position_closure_cm',NaN, ...
    'motion_activity_rad',NaN,'actuator_activity_ratio',NaN);
end

function p=empty_pair()
p=struct('valid',false,'core_event_present',false, ...
    'event_evidence',NaN,'peak_position_divergence_cm',NaN, ...
    'post_position_divergence_cm',NaN,'recovery_time_s',NaN);
end

function out=empty_out()
out=struct('schema',"simuverity.xp9-score.v1", ...
    'policy_id',"simuverity-101-v1:f90-xmech-04:scoring", ...
    'formula',"G*100*A^.20*Q^.10*M^.30*R^.20*D^.20", ...
    'score_inputs_valid',false,'diagnostics_valid',false, ...
    'G',false,'gate_reasons',strings(0,1), ...
    'A',0,'Q',0,'M',0,'R',0,'D',0,'score',0, ...
    'raw_metrics',struct(),'utility_metrics',struct(), ...
    'scenario_rows',struct([]),'pair_metrics',empty_pair(), ...
    'diagnostic_scope', ...
    "six measured revolute-joint states, serial-chain position closure, bounded actuator torque, official operating corners, and a same-input external-load counterfactual");
end
