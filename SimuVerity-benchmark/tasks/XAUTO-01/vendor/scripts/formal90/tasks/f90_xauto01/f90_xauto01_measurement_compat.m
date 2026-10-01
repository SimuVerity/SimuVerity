function varargout = f90_xauto01_measurement_compat(helperName, varargin)
%F90_XAUTO01_MEASUREMENT_COMPAT R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xauto01_measurement_compat:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["select_slip_orientation", "shared_vehicle_dynamics", "brake_demand_probe", "empty_row", "measure_run"];
        end
    case "select_slip_orientation"
        if nargout == 0
            select_slip_orientation(varargin{:});
        else
            [varargout{1:nargout}] = select_slip_orientation(varargin{:});
        end
    case "shared_vehicle_dynamics"
        if nargout == 0
            shared_vehicle_dynamics(varargin{:});
        else
            [varargout{1:nargout}] = shared_vehicle_dynamics(varargin{:});
        end
    case "brake_demand_probe"
        if nargout == 0
            brake_demand_probe(varargin{:});
        else
            [varargout{1:nargout}] = brake_demand_probe(varargin{:});
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
    otherwise
        error("SimuVerity:f90_xauto01_measurement_compat:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
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

function [err,cDrag]=longitudinal_fit(base,force,drag,forceSign)
err=1;cDrag=NaN;if numel(base)<100,return;end
y=-(base+forceSign*force);cDrag=max((drag'*y)/max(drag'*drag,eps),0);
residual=base+forceSign*force+cDrag*drag;
err=sqrt(mean(residual.^2))/max(sqrt(mean(base.^2)),100);
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

function dt=local_recovery(t,speed,slip,yawRate,eventEnd,baselineSlip)
dt=max(t(end)-eventEnd+1,0);start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.24/median(diff(t))));
good=(speed<=2.0)|(max(abs(slip-baselineSlip),[],2)<=.13&abs(yawRate)<=.22);
lastStart=numel(t)-window+1;
if start>lastStart,return;end
for k=start:lastStart
    if all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
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
