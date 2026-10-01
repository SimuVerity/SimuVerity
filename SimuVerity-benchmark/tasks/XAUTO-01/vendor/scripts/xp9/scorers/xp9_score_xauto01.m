function out=xp9_score_xauto01(runs,spec)
%XP9_SCORE_XAUTO01 Dedicated split-friction braking and vehicle score.
out=empty_out();
[slipSign,slipOrientation]=select_slip_orientation(runs);
[suite,forceSign,brakeSign]=shared_vehicle_dynamics(runs);
brakeProbe=brake_demand_probe(runs);
suite.brake_demand_probe=brakeProbe;
brakeCompletion=min(max(1-brakeProbe.response_deficit,0),1);
rows=repmat(empty_row(),numel(runs),1);allValid=true;
for i=1:numel(runs)
    rows(i)=measure_run(runs(i),slipSign,forceSign,brakeSign);allValid=allValid&&rows(i).valid;
end
out.score_inputs_valid=allValid&&numel(runs)==1+numel(spec.scenarios);
out.diagnostics_valid=allValid;out.G=out.score_inputs_valid;
if ~out.G,out.gate_reasons="SCENARIO_OR_PHYSICAL_OUTPUT_CONTRACT_INVALID";end
out.scenario_rows=rows;

if ~isempty(rows)
    n=rows(1);
    qStop=xp9_utility(n.final_speed_ratio,[0 .008 .025 .07 .18 .42],[1 1 .95 .75 .30 0]);
    qSlip=xp9_utility(n.slip_regulation_violation,[0 .004 .018 .06 .22 .65],[1 1 .94 .73 .27 0]);
    out.A=xp9_group([qStop qSlip],[.50 .50],true);

    qLock=xp9_utility(n.lock_fraction,[0 .004 .018 .065 .20 .55],[1 1 .94 .72 .25 0]);
    qYaw=xp9_utility(n.peak_yaw,[0 .025 .065 .15 .35 .75],[1 1 .94 .72 .24 0]);
    qLat=xp9_utility(n.peak_lateral,[0 .12 .32 .80 2.1 5.0],[1 1 .94 .72 .24 0]);
    qTorque=xp9_utility(n.torque_ripple,[0 .04 .10 .22 .50 1.0],[1 1 .94 .72 .25 0]);
    out.Q=xp9_group([qLock qYaw qLat qTorque],[.30 .25 .25 .20],true);

    qFriction=xp9_utility(n.friction_envelope_violation,[0 .002 .010 .040 .12 .35],[1 1 .95 .75 .30 0]);
    qKinematics=xp9_utility(n.slip_kinematic_error,[0 .006 .020 .060 .16 .45],[1 1 .95 .74 .28 0]);
    qCausality=xp9_utility(n.contact_causality_error,[0 .002 .010 .040 .15 .45],[1 1 .94 .72 .25 0]);
    qNormal=xp9_utility(suite.normal_load_error,[0 .001 .004 .012 .04 .12],[1 1 .95 .75 .30 0]);
    qInitial=xp9_utility(max(n.initial_speed_error,n.initial_wheel_speed_error), ...
        [0 .001 .004 .015 .05 .18],[1 1 .95 .75 .30 0]);
    qActuation=xp9_utility(n.actuation_contract_error, ...
        [0 .002 .008 .025 .10 .35],[1 1 .95 .75 .30 0]);
    qLong=xp9_utility(suite.longitudinal_error,[0 .015 .045 .12 .30 .70],[1 1 .95 .75 .30 0]);
    qWheel=xp9_utility(suite.wheel_error,[0 .02 .06 .16 .38 .85],[1 1 .95 .75 .30 0]);
    qPose=xp9_utility(suite.pose_kinematic_error,[0 .004 .015 .05 .16 .50],[1 1 .95 .75 .30 0]);
    qYawDyn=xp9_utility(suite.yaw_dynamic_error,[0 .025 .07 .18 .42 .90],[1 1 .94 .72 .25 0]);
    qBrake=xp9_utility(brakeProbe.response_deficit,[0 .03 .10 .25 .55 1],[1 1 .94 .72 .25 0]);
    qDomain=xp9_utility(max([rows.finite_physical_violation]), ...
        [0 1e-8 1e-6 1e-4 .01 .10 1],[1 .999 .995 .98 .80 .30 0]);
    qPlant=xp9_group([qLong qWheel qPose qYawDyn],[.27 .27 .20 .26],true);
    qBoundary=xp9_group([qInitial qActuation qBrake],[.25 .35 .40],true);
    out.M=xp9_group([qFriction qKinematics qCausality qNormal qPlant qBoundary qDomain], ...
        [.15 .16 .13 .10 .24 .16 .06],true);
    % A finite zero-response brake path remains scoreable, but it cannot
    % support a near-complete braking-mechanism claim.  Apply a continuous,
    % nonzero completion ceiling rather than a technical-validity gate.
    out.M=min(out.M,.35+.65*brakeCompletion);
else
    out.A=0;out.Q=0;out.M=0;
end

rq=zeros(numel(rows),1);dq=zeros(numel(rows),1);
for i=1:numel(rows)
    r=rows(i);
    qs=xp9_utility(r.final_speed_ratio,[0 .015 .045 .11 .27 .58],[1 1 .93 .70 .24 0]);
    qsl=xp9_utility(r.slip_regulation_violation,[0 .008 .030 .10 .35 .80],[1 1 .92 .69 .22 0]);
    qy=xp9_utility(r.peak_yaw,[0 .04 .10 .23 .52 1.05],[1 1 .92 .68 .20 0]);
    ql=xp9_utility(r.peak_lateral,[0 .20 .55 1.35 3.4 7.0],[1 1 .92 .68 .20 0]);
    qlock=xp9_utility(r.lock_fraction,[0 .008 .03 .10 .30 .70],[1 1 .92 .68 .20 0]);
    rq(i)=xp9_group([qs qsl qy ql qlock],[.25 .25 .18 .17 .15],true);
    qRec=xp9_utility(r.recovery_time,[0 .18 .40 .80 1.45 2.8],[1 1 .93 .72 .28 0]);
    qEvent=xp9_utility(r.event_consistency_error,[0 .020 .060 .14 .30 .65],[1 1 .94 .72 .26 0]);
    dq(i)=xp9_group([qRec qEvent],[.72 .28],true);
end
if isempty(rq)
    out.R=0;out.D=0;
else
    out.R=xp9_tail(rq,ones(size(rq)));
    % The paired brake-demand probes terminate their comparison before the
    % deliberately late friction event.  They are mechanism probes, not
    % friction-loss/recovery cases, so only the nominal and declared
    % friction-event scenarios contribute to D.
    dynamicMask=~startsWith(string({rows.scenario}),"brake_probe_");
    if any(dynamicMask)
        dynamicValues=dq(dynamicMask);
        out.D=xp9_tail(dynamicValues,ones(size(dynamicValues)));
    else
        out.D=0;
    end
end
out.utility_metrics=struct('nominal_accuracy',out.A,'nominal_quality',out.Q, ...
    'mechanism',out.M,'brake_mechanism_completion',brakeCompletion, ...
    'slip_orientation',slipOrientation, ...
    'brake_torque_orientation',struct('selected_sign',brakeSign, ...
    'positive_candidate_error',suite.brake_positive_candidate_error, ...
    'negative_candidate_error',suite.brake_negative_candidate_error), ...
    'shared_vehicle_dynamics',suite,'worst_range',out.R,'worst_dynamic',out.D);
out.raw_metrics=rows;w=spec.groups.weights;
out.score=xp9_total(out.G,[out.A out.Q out.M out.R out.D],[w.A w.Q w.M w.R w.D]);
end

function r=measure_run(run,slipSign,forceSign,brakeSign)
r=empty_row();r.scenario=string(run.scenario);
if string(run.stage)~="simulated",return;end
[t,v,okV]=xp9_series(run,'vehicle_state',5);
[t2,w,okW]=xp9_series(run,'wheel_state',8);
[t3,c,okC]=xp9_series(run,'tire_contact',10);
[t4,b,okB]=xp9_series(run,'brake_actuation',5);
if ~(okV&&okW&&okC&&okB&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
% xp9_series handles malformed/non-finite logs.  Keep only gross numerical
% explosion and the declared normalized applied-demand interface in G;
% finite state/contact-domain errors are scored continuously below.
bad=any(abs(v)>1e9,'all')||any(abs(w)>1e9,'all')|| ...
        any(abs(c)>1e9,'all')||any(abs(b(:,1:4))>1e9,'all')|| ...
        any(b(:,5)<-1e-4)||any(b(:,5)>1.001);
if bad,return;end

on=double(run.inputs.brake_onset);event=double(run.inputs.friction_event_time);eventEnd=event+1.0;
speed=v(:,4);reportedSlip=w(:,5:8);slip=slipSign*reportedSlip;
yaw=v(:,3);yawRate=v(:,5);
active=t>=on+.20&speed>.5&~(t>=event-.08&t<=eventEnd+.45);
if nnz(active)<20,active=t>=on+.10;end
pre=t>=event-.55&t<=event-.10;
evt=t>=event+.10&t<=event+.78;
post=t>=eventEnd+.08&t<=eventEnd+.45;
r.final_speed_ratio=speed(end)/max(double(run.inputs.initial_speed),1);
r.slip_regulation_violation=mean(any(abs(slip(active,:))>.35,2));
r.lock_fraction=mean(any(abs(slip(active,:))>.82,2));
r.peak_yaw=max(abs(yaw(t>=on)));
r.peak_lateral=max(abs(v(t>=on,2)));
db=local_derivative(b(:,1:4),t);braking=t>=on+.2&speed>1;
r.torque_ripple=sqrt(mean(db(braking,:).^2,'all'))/max(mean(abs(b(braking,1:4)),'all'),100)/70;

Fx=c(:,1:4);orientedFx=forceSign*Fx;Fz=c(:,5:8);omega=w(:,1:4);m=double(run.inputs.vehicle_mass);
orientedBrake=brakeSign*b(:,1:4);
mask=t>.12&speed>.5;if nnz(mask)<20,mask=t>.12;end
wheelPath=[speed-.81*yawRate,speed+.81*yawRate,speed-.81*yawRate,speed+.81*yawRate];
surfaceSpeed=.31*omega;
kinSlip=(wheelPath-surfaceSpeed)./max(max(abs(wheelPath),abs(surfaceSpeed)),.55);
r.slip_kinematic_error=median(abs(slip(mask,:)-kinSlip(mask,:)),'all');
mu=[c(:,9),c(:,10),c(:,9),c(:,10)];capacity=mu.*Fz;
frictionExcess=max(abs(Fx)-capacity,0)./max(capacity,50);
r.friction_envelope_violation=prctile(frictionExcess(mask,:),95,'all');
speedScale=max(double(run.inputs.initial_speed),1);
wheelScale=max(speedScale/.31,1);normalScale=max(m*9.81/4,1);
r.vehicle_speed_domain_violation=max([max(max(-speed,0))/speedScale, ...
    max(max(speed-1.2*speedScale,0))/speedScale]);
r.wheel_speed_domain_violation=max([max(max(-omega,0),[],'all')/wheelScale, ...
    max(max(omega-1.5*wheelScale,0),[],'all')/wheelScale]);
r.slip_domain_violation=max(max(abs(reportedSlip)-2,0),[],'all');
r.normal_force_domain_violation=max([max(max(-Fz,0),[],'all')/normalScale, ...
    max(max(Fz-m*9.81,0),[],'all')/normalScale]);
r.friction_coefficient_domain_violation=max([max(max(-mu,0),[],'all'), ...
    max(max(mu-1,0),[],'all')]);
r.force_capacity_peak_violation=max(frictionExcess,[],'all');
r.finite_physical_violation=max([r.vehicle_speed_domain_violation, ...
    r.wheel_speed_domain_violation,r.slip_domain_violation, ...
    r.normal_force_domain_violation,r.friction_coefficient_domain_violation, ...
    r.force_capacity_peak_violation]);
dv=gradient(speed,t);
contactSignBad=mean((slip(mask,:).*orientedFx(mask,:))<-.002,'all');
brakeDirectionBad=mean((orientedBrake(mask,:)>100)& ...
    ((slip(mask,:)<-.01)|(orientedFx(mask,:)<-10)),'all');
strongBrake=abs(b(:,1:4))>100;
if any(strongBrake,'all')
    r.brake_orientation_error=mean(orientedBrake(strongBrake)<0);
else
    r.brake_orientation_error=1;
end
decelerationBad=mean((sum(abs(Fx(mask,:)),2)>200)&(dv(mask)>.05));
r.contact_causality_error=max([contactSignBad,brakeDirectionBad,decelerationBad, ...
    r.brake_orientation_error]);
r.normal_residual=median(abs(sum(Fz(mask,:),2)-m*9.81))/(m*9.81);

r.initial_speed_error=abs(speed(1)-double(run.inputs.initial_speed))/max(double(run.inputs.initial_speed),1);
r.initial_wheel_speed_error=median(abs(.31*omega(1,:)-double(run.inputs.initial_speed))) / ...
    max(double(run.inputs.initial_speed),1);
preOn=t<=on-.05;postOn=t>=on+.06&t<=min(on+.55,event-.10)&speed>.5;
if nnz(preOn)<10||nnz(postOn)<20
    r.actuation_contract_error=1;
else
    demand=double(run.inputs.brake_demand);
    preTorque=mean(abs(b(preOn,1:4)),'all')/max(m*9.81*.31,1);
    postTorque=mean(abs(b(postOn,1:4)),'all')/max(m*9.81*.31*demand,1);
    postForce=mean(abs(Fx(postOn,:)),'all')/max(m*9.81*demand,1);
    responseDeficit=max([0,(.012-postTorque)/.012,(.012-postForce)/.012]);
    % The reported demand is retained as an interface diagnostic, but the
    % score trusts only actual pre-onset torque and physical brake/contact
    % response.  Demand causality is checked by the paired probe below.
    r.actuation_contract_error=max([preTorque,responseDeficit]);
end

if nnz(pre)>=20&&nnz(evt)>=20&&nnz(post)>=20
    leftFriction=double(run.inputs.left_friction);rightFriction=double(run.inputs.right_friction);
    drop=double(run.inputs.friction_drop);
    expectedEvent=rightFriction*(1-drop);
    reportScale=max([leftFriction,rightFriction,.1]);
    r.mu_report_error=max(abs([median(c(pre,9))-leftFriction, ...
        median(c(pre,10))-rightFriction,median(c(evt,10))-expectedEvent, ...
        median(c(post,10))-rightFriction]))/reportScale;
    rightGrip=mean(abs(Fx(:,[2 4]))./max(Fz(:,[2 4]),50),2);
    gripPre=median(rightGrip(pre));gripEvent=median(rightGrip(evt));
    eventEntry=t>=event-.08&t<=event+.08;
    r.event_entry_speed=median(speed(eventEntry));
    newRightCapacity=max(expectedEvent,.02);
    r.right_grip_binding_ratio=max([prctile(rightGrip(pre),90), ...
        prctile(rightGrip(evt),90)])/newRightCapacity;
    r.friction_event_binding=r.event_entry_speed>.5&&r.right_grip_binding_ratio>=.90;
    forceDrop=max((gripPre-gripEvent)/max(gripPre,.05),0);
    slipChange=abs(median(slip(evt,[2 4]),'all')-median(slip(pre,[2 4]),'all'));
    torqueChange=abs(median(b(evt,[2 4]),'all')-median(b(pre,[2 4]),'all'))/(m*9.81*.31);
    yawChange=abs(median(yawRate(evt))-median(yawRate(pre)));
    forceEvidence=forceDrop/max(.12*drop,.02);
    companionEvidence=max([slipChange/.025,torqueChange/.015,yawChange/.015]);
    if r.friction_event_binding
        physicalStrength=min(forceEvidence,companionEvidence);
        r.event_physical_response_deficit=max(0,1-physicalStrength);
        baselineSlip=median(slip(pre,:),1);
        r.recovery_time=local_recovery(t,speed,slip,yawRate,eventEnd,baselineSlip);
    else
        % A lower friction ceiling cannot change chassis/wheel dynamics if
        % the vehicle has already stopped or the actual tire force remains
        % comfortably below that ceiling. In this unexcited branch the
        % correct physical response is no response; only the reported
        % public friction schedule remains checkable.
        r.event_physical_response_deficit=0;
        r.recovery_time=0;
    end
    r.event_consistency_error=max(r.mu_report_error,r.event_physical_response_deficit);
else
    r.mu_report_error=1;r.event_physical_response_deficit=1;
    r.event_consistency_error=1;r.recovery_time=max(t(end)-eventEnd+1,0);
    r.event_entry_speed=NaN;r.right_grip_binding_ratio=NaN;
    r.friction_event_binding=true;
end
r.valid=all(isfinite([r.final_speed_ratio r.slip_regulation_violation r.lock_fraction ...
    r.peak_yaw r.peak_lateral r.torque_ripple r.friction_envelope_violation ...
    r.finite_physical_violation r.vehicle_speed_domain_violation ...
    r.wheel_speed_domain_violation r.slip_domain_violation ...
    r.normal_force_domain_violation r.friction_coefficient_domain_violation ...
    r.force_capacity_peak_violation ...
    r.slip_kinematic_error r.contact_causality_error r.normal_residual ...
    r.initial_speed_error r.initial_wheel_speed_error r.actuation_contract_error ...
    r.mu_report_error r.event_physical_response_deficit r.event_consistency_error r.recovery_time ...
    r.event_entry_speed r.right_grip_binding_ratio ...
    r.brake_orientation_error]));
end

function [orientation,detail]=select_slip_orientation(runs)
plus=[];minus=[];
for i=1:numel(runs)
    run=runs(i);[t,v,okV]=xp9_series(run,'vehicle_state',5);
    [t2,w,okW]=xp9_series(run,'wheel_state',8);
    if ~(okV&&okW&&isequal(t,t2)),continue;end
    speed=v(:,4);yawRate=v(:,5);omega=w(:,1:4);reported=w(:,5:8);
    wheelPath=[speed-.81*yawRate,speed+.81*yawRate,speed-.81*yawRate,speed+.81*yawRate];
    surfaceSpeed=.31*omega;
    kin=(wheelPath-surfaceSpeed)./max(max(abs(wheelPath),abs(surfaceSpeed)),.55);
    mask=t>.12&speed>.5;
    plus(end+1)=median(abs(reported(mask,:)-kin(mask,:)),'all'); %#ok<AGROW>
    minus(end+1)=median(abs(-reported(mask,:)-kin(mask,:)),'all'); %#ok<AGROW>
end
if isempty(plus),orientation=1;plusError=1;minusError=1;
else,plusError=median(plus);minusError=median(minus);orientation=1;if minusError<plusError,orientation=-1;end
end
detail=struct('selected_sign',orientation,'plus_error',plusError,'minus_error',minusError);
end

function [s,forceSign,brakeSign]=shared_vehicle_dynamics(runs)
longBase=[];longForce=[];longDrag=[];allBrakeTorque=[];
wheelX=cell(1,4);wheelForce=cell(1,4);wheelTorque=cell(1,4);
poseResidual=[];poseScale=[];yawX=[];yawMoment=[];
normalTotal=[];normalWeight=[];normalSpeedSquared=[];
for i=1:numel(runs)
    run=runs(i);[t,v,okV]=xp9_series(run,'vehicle_state',5);
    [t2,w,okW]=xp9_series(run,'wheel_state',8);
    [t3,c,okC]=xp9_series(run,'tire_contact',10);
    [t4,b,okB]=xp9_series(run,'brake_actuation',5);
    if ~(okV&&okW&&okC&&okB&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),continue;end
    speed=v(:,4);yaw=v(:,3);yawRate=v(:,5);omega=w(:,1:4);Fx=c(:,1:4);
    Fz=c(:,5:8);torque=b(:,1:4);
    dv=local_derivative(speed,t);domega=local_derivative(omega,t);
    domegaBackward=local_backward_derivative(omega,t);dr=local_derivative(yawRate,t);
    dx=local_derivative(v(:,1),t);dy=local_derivative(v(:,2),t);dpsi=local_derivative(yaw,t);
    mask=t>.15&speed>.5;stride=max(1,round(.01/median(diff(t))));idx=find(mask);idx=idx(1:stride:end);
    m=double(run.inputs.vehicle_mass);base=m*dv(idx);sumFx=sum(Fx(idx,:),2);
    longBase=[longBase;base];longForce=[longForce;sumFx];longDrag=[longDrag;speed(idx).*abs(speed(idx))]; %#ok<AGROW>
    allBrakeTorque=[allBrakeTorque;torque(idx,:)]; %#ok<AGROW>
    for k=1:4
        wheelX{k}=[wheelX{k};domega(idx,k),domegaBackward(idx,k),omega(idx,k)];
        wheelForce{k}=[wheelForce{k};.31*Fx(idx,k)];
        wheelTorque{k}=[wheelTorque{k};torque(idx,k)];
    end
    poseResidual=[poseResidual;dx(idx)-speed(idx).*cos(yaw(idx)), ...
        dy(idx)-speed(idx).*sin(yaw(idx)),dpsi(idx)-yawRate(idx)]; %#ok<AGROW>
    poseScale=[poseScale;speed(idx),speed(idx),yawRate(idx)]; %#ok<AGROW>
    yawX=[yawX;dr(idx),yawRate(idx),yawRate(idx).*abs(yawRate(idx)),sin(yaw(idx))]; %#ok<AGROW>
    yawMoment=[yawMoment;((Fx(idx,1)+Fx(idx,3))-(Fx(idx,2)+Fx(idx,4)))*.81]; %#ok<AGROW>
    normalTotal=[normalTotal;sum(Fz(idx,:),2)]; %#ok<AGROW>
    normalWeight=[normalWeight;m*9.81*ones(numel(idx),1)]; %#ok<AGROW>
    normalSpeedSquared=[normalSpeedSquared;speed(idx).^2]; %#ok<AGROW>
end
[errP,dragP]=longitudinal_fit(longBase,longForce,longDrag,1);
[errM,dragM]=longitudinal_fit(longBase,longForce,longDrag,-1);
if errM<errP,forceSign=-1;longError=errM;drag=dragM;
else,forceSign=1;longError=errP;drag=dragP;end
[plusError,plus]=wheel_candidate_fit(wheelX,wheelForce,wheelTorque,forceSign,1);
[minusError,minus]=wheel_candidate_fit(wheelX,wheelForce,wheelTorque,forceSign,-1);
% Prefer the cross-scenario wheel balance when it identifies a convention.
% If both candidates are equally poor (for example, a deliberately weak
% plant), do not let numerical noise flip the reported-torque orientation:
% fall back to the single global sign carried by the nontrivial samples.
if min(plusError,minusError)<=.8*max(plusError,minusError)
    inference="cross-scenario wheel dynamics";
    if minusError<plusError,brakeSign=-1;wheel=minus;else,brakeSign=1;wheel=plus;end
else
    strong=allBrakeTorque(abs(allBrakeTorque)>100);
    brakeSign=1;if ~isempty(strong)&&median(strong)<0,brakeSign=-1;end
    inference="global reported-sign fallback after unidentifiable dynamics";
    if brakeSign<0,wheel=minus;else,wheel=plus;end
end
wheelErrorEach=wheel.error_each;wheelInertia=wheel.inertia;
wheelSignEach=wheel.sign_each;wheelLossFamily=wheel.loss_family;
wheelLossCoefficients=wheel.loss_coefficients;
wheelError=max(wheelErrorEach);wheelSignViolation=max(wheelSignEach);
poseError=1;
if ~isempty(poseResidual)
    xyError=sqrt(mean(sum(poseResidual(:,1:2).^2,2)))/max(sqrt(mean(poseScale(:,1).^2)),.5);
    yawKin=sqrt(mean(poseResidual(:,3).^2))/max(sqrt(mean(poseScale(:,3).^2)),.01);
    poseError=max(xyError,yawKin);
end
[yawDynamic,yawBeta,yawOrientation]=yaw_dynamics_fit(yawX,forceSign*yawMoment);
[normalError,normalAeroCoefficient]=normal_load_fit(normalTotal,normalWeight,normalSpeedSquared);
s=struct('longitudinal_error',longError,'force_orientation',forceSign, ...
    'brake_torque_orientation',brakeSign, ...
    'brake_orientation_inference',inference, ...
    'brake_positive_candidate_error',plusError, ...
    'brake_negative_candidate_error',minusError, ...
    'fitted_drag_coefficient',drag,'wheel_error',wheelError, ...
    'fitted_wheel_inertia',wheelInertia,'wheel_loss_family',wheelLossFamily, ...
    'wheel_loss_coefficients',{wheelLossCoefficients}, ...
    'wheel_error_each',wheelErrorEach,'wheel_sign_violation',wheelSignViolation, ...
    'pose_kinematic_error',poseError,'yaw_dynamic_error',yawDynamic, ...
    'normal_load_error',normalError, ...
    'fitted_aerodynamic_normal_force_coefficient',normalAeroCoefficient, ...
    'fitted_yaw_coefficients',yawBeta,'yaw_orientation',yawOrientation);
end

function [err,kAero]=normal_load_fit(totalLoad,weight,speedSquared)
% A reduced planar model may include unresolved aerodynamic lift/downforce.
% Fit one shared signed v^2 vertical-force coefficient instead of forcing
% sum(Fz)=m*g. Arbitrary per-scenario or time-varying load fabrication still
% leaves a large cross-scenario residual.
err=1;kAero=NaN;
if numel(totalLoad)<100||numel(weight)~=numel(totalLoad),return;end
y=totalLoad-weight;x=speedSquared;
kAero=(x'*y)/max(x'*x,eps);
predicted=weight+kAero*x;
nonpositive=mean(predicted<=0);
residual=sqrt(mean((totalLoad-predicted).^2))/max(sqrt(mean(weight.^2)),100);
err=max(residual,nonpositive);
end

function [candidateError,candidate]=wheel_candidate_fit(wheelX,wheelForce,wheelTorque,forceSign,brakeSign)
errorEach=ones(1,4);inertia=nan(1,4);signEach=ones(1,4);
lossFamily=strings(1,4);lossCoefficients=cell(1,4);
for k=1:4
    % A single force and brake-torque orientation is shared by every wheel
    % and every scenario.  This accepts either signed physical torque or a
    % positive resisting-torque magnitude, while a per-wheel/per-scenario
    % sign switch cannot select a different candidate locally.
    Y=forceSign*wheelForce{k}-brakeSign*wheelTorque{k};
    [errorEach(k),inertia(k),signEach(k),lossFamily(k),lossCoefficients{k}]= ...
        wheel_loss_fit(wheelX{k},Y);
end
candidateError=max(errorEach);
candidate=struct('error_each',errorEach,'inertia',inertia, ...
    'sign_each',signEach,'loss_family',lossFamily, ...
    'loss_coefficients',{lossCoefficients});
end

function [err,inertia,signViolation,family,coefficients]=wheel_loss_fit(base,Y)
err=1;inertia=NaN;signViolation=1;family="none";coefficients=NaN;
if size(base,1)<100,return;end
w=base(:,end);accelerations=base(:,1:end-1);
names=["viscous","coulomb","viscous-quadratic","coulomb-viscous"];
best=Inf;
for d=1:size(accelerations,2)
    a=accelerations(:,d);
    features={ [a,w], [a,double(w>1e-4)], [a,w,w.*abs(w)], ...
        [a,double(w>1e-4),w] };
    derivativeName="centered";if d==2,derivativeName="backward";end
    for j=1:numel(names)
        X=features{j};if rank(X)<size(X,2),continue;end
        beta=X\Y;pred=X*beta;
        residual=sqrt(mean((Y-pred).^2))/max(sqrt(mean(Y.^2)),50);
        % A negative wheel inertia is not a small coefficient-sign blemish:
        % it invalidates that global brake-torque orientation. Keep the
        % softer aggregate passivity term for optional loss coefficients.
        inertiaViolation=max(-beta(1),0)/max(abs(beta(1)),eps);
        lossViolation=0;
        if numel(beta)>1
            lossViolation=sum(max(-beta(2:end),0))/max(sum(abs(beta(2:end))),eps);
        end
        oneSign=max(inertiaViolation,lossViolation);
        score=max(residual,oneSign);
        if score<best
            best=score;err=score;inertia=beta(1);signViolation=oneSign;
            family=derivativeName+"-"+names(j);coefficients=beta';
        end
    end
end
end

function [err,beta,orientation]=yaw_dynamics_fit(X,moment)
err=1;beta=nan(4,1);orientation=1;
if size(X,1)<100||sqrt(mean(X(:,1).^2))<1e-4||sqrt(mean(moment.^2))<20,return;end
best=Inf;
for signChoice=[1 -1]
    y=signChoice*moment;ridge=1e-9*eye(size(X,2));candidate=(X'*X+ridge)\(X'*y);
    pred=X*candidate;residual=sqrt(mean((y-pred).^2))/max(sqrt(mean(y.^2)),20);
    inertiaViolation=max(-candidate(1),0)/max(abs(candidate(1)),1);
    score=max(residual,inertiaViolation);
    if score<best,best=score;beta=candidate;orientation=signChoice;end
end
err=best;
end

function out=brake_demand_probe(runs)
out=struct('valid',false,'torque_gain',0,'contact_impulse_gain',0, ...
    'stopping_distance_gain',0,'half_speed_time_gain',0,'effort_path',0, ...
    'outcome_path',0,'response_strength',0,'response_deficit',1);
names=string({runs.scenario});lo=find(names=="brake_probe_low",1);hi=find(names=="brake_probe_high",1);
if isempty(lo)||isempty(hi),return;end
[low,okL]=probe_metrics(runs(lo));[high,okH]=probe_metrics(runs(hi));if ~(okL&&okH),return;end
out.torque_gain=max(high.torque_impulse/low.torque_impulse-1,0);
out.contact_impulse_gain=max(high.contact_impulse/low.contact_impulse-1,0);
out.stopping_distance_gain=max((low.distance-high.distance)/max(low.distance,.1),0);
out.half_speed_time_gain=max((low.half_speed_time-high.half_speed_time)/max(low.half_speed_time,.1),0);
out.effort_path=min(out.torque_gain/.08,out.contact_impulse_gain/.05);
out.outcome_path=max(out.stopping_distance_gain/.04,out.half_speed_time_gain/.04);
out.response_strength=max(out.effort_path,out.outcome_path);
out.response_deficit=max(0,1-out.response_strength);out.valid=true;
end

function [m,ok]=probe_metrics(run)
m=struct('torque_impulse',0,'contact_impulse',0,'distance',0,'half_speed_time',0);ok=false;
[t,v,okV]=xp9_series(run,'vehicle_state',5);[t2,c,okC]=xp9_series(run,'tire_contact',10);
[t3,b,okB]=xp9_series(run,'brake_actuation',5);
if ~(okV&&okC&&okB&&isequal(t,t2)&&isequal(t,t3)),return;end
on=double(run.inputs.brake_onset);stop=min(double(run.inputs.friction_event_time)-.10,t(end));mask=t>=on&t<=stop;
if nnz(mask)<100,return;end
m.torque_impulse=trapz(t(mask),sum(abs(b(mask,1:4)),2));
m.contact_impulse=trapz(t(mask),sum(abs(c(mask,1:4)),2));
m.distance=trapz(t(mask),max(v(mask,4),0));
idx=find(t>=on&v(:,4)<=.5*double(run.inputs.initial_speed),1);
if isempty(idx)||t(idx)>stop,m.half_speed_time=stop-on;else,m.half_speed_time=t(idx)-on;end
ok=all(isfinite([m.torque_impulse m.contact_impulse m.distance m.half_speed_time])) ...
    &&m.torque_impulse>1&&m.contact_impulse>1&&m.distance>.1;
end

function [err,cDrag]=longitudinal_fit(base,force,drag,forceSign)
err=1;cDrag=NaN;if numel(base)<100,return;end
y=-(base+forceSign*force);cDrag=max((drag'*y)/max(drag'*drag,eps),0);
residual=base+forceSign*force+cDrag*drag;
err=sqrt(mean(residual.^2))/max(sqrt(mean(base.^2)),100);
end

function dt=local_recovery(t,speed,slip,yawRate,eventEnd,baselineSlip)
dt=max(t(end)-eventEnd+1,0);start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.24/median(diff(t))));
good=(speed<=2.0)|(max(abs(slip-baselineSlip),[],2)<=.13&abs(yawRate)<=.22);
for k=start:max(start,numel(t)-window+1)
    if all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
end

function dy=local_derivative(y,t)
dy=zeros(size(y));
dy(1,:)=(y(2,:)-y(1,:))/(t(2)-t(1));
dy(end,:)=(y(end,:)-y(end-1,:))/(t(end)-t(end-1));
dy(2:end-1,:)=(y(3:end,:)-y(1:end-2,:))./(t(3:end)-t(1:end-2));
end

function dy=local_backward_derivative(y,t)
dy=zeros(size(y));
dy(1,:)=(y(2,:)-y(1,:))/(t(2)-t(1));
dy(2:end,:)=(y(2:end,:)-y(1:end-1,:))./(t(2:end)-t(1:end-1));
end

function r=empty_row()
r=struct('scenario',"",'valid',false,'final_speed_ratio',NaN,'slip_regulation_violation',NaN, ...
    'lock_fraction',NaN,'peak_yaw',NaN,'peak_lateral',NaN,'torque_ripple',NaN, ...
    'friction_envelope_violation',NaN,'slip_kinematic_error',NaN, ...
    'contact_causality_error',NaN,'brake_orientation_error',NaN,'normal_residual',NaN, ...
    'finite_physical_violation',NaN,'vehicle_speed_domain_violation',NaN, ...
    'wheel_speed_domain_violation',NaN,'slip_domain_violation',NaN, ...
    'normal_force_domain_violation',NaN,'friction_coefficient_domain_violation',NaN, ...
    'force_capacity_peak_violation',NaN, ...
    'initial_speed_error',NaN,'initial_wheel_speed_error',NaN,'actuation_contract_error',NaN, ...
    'mu_report_error',NaN,'event_entry_speed',NaN,'right_grip_binding_ratio',NaN, ...
    'friction_event_binding',false,'event_physical_response_deficit',NaN, ...
    'event_consistency_error',NaN,'recovery_time',NaN);
end
function out=empty_out()
out=struct('schema',"simuverity.xp9-score.v1",'policy_id',"simuverity-101-v1:p9-xauto01:scoring", ...
    'formula',"G*100*A^.20*Q^.10*M^.30*R^.20*D^.20", ...
    'score_inputs_valid',false,'diagnostics_valid',false,'G',false, ...
    'gate_reasons',strings(0,1),'A',0,'Q',0,'M',0,'R',0,'D',0,'score',0, ...
    'raw_metrics',struct(),'utility_metrics',struct(),'scenario_rows',struct([]), ...
    'diagnostic_scope',"global slip/force/brake-torque convention inference, pose-rate and contact-moment yaw closure, per-wheel positive inertia, shared weight-plus-aerodynamic normal-load balance, paired physical brake-demand response, and excitation-conditional unilateral friction-loss recovery");
end
