function varargout = f90_xmech01_measurement_compat_core(helperName, varargin)
%F90_XMECH01_MEASUREMENT_COMPAT_CORE R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xmech01_measurement_compat_core:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["empty_row", "measure_run", "measure_suite", "core_vehicle_contact_present", "core_traction_event_present"];
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
    case "measure_suite"
        if nargout == 0
            measure_suite(varargin{:});
        else
            [varargout{1:nargout}] = measure_suite(varargin{:});
        end
    case "core_vehicle_contact_present"
        if nargout == 0
            core_vehicle_contact_present(varargin{:});
        else
            [varargout{1:nargout}] = core_vehicle_contact_present(varargin{:});
        end
    case "core_traction_event_present"
        if nargout == 0
            core_traction_event_present(varargin{:});
        else
            [varargout{1:nargout}] = core_traction_event_present(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xmech01_measurement_compat_core:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function r=empty_row()
r=struct('scenario',"",'valid',false,'is_no_loss_control',false,'track_error',NaN, ...
    'forward_response_error',NaN,'turn_response_error',NaN,'slip95',NaN, ...
    'track_ripple',NaN,'force_ripple',NaN,'negative_normal_violation',NaN, ...
    'normal_balance_residual',NaN, ...
    'friction_excess',NaN,'force_slip_violation',NaN,'slip_definition_residual',NaN, ...
    'slip_sign_violation',NaN,'contact_binding',NaN,'event_slip_change',NaN, ...
    'event_force_change',NaN,'event_motion_change',NaN,'post_event_degradation',NaN, ...
    'recovery_time',NaN);
end

function r=measure_run(run)
r=empty_row();r.scenario=string(run.scenario);r.is_no_loss_control=endsWith(r.scenario,"_no_loss");
if string(run.stage)~="simulated",return;end
[t,m,okM]=xp9_series(run,'vehicle_motion',5);
[t2,s,okS]=xp9_series(run,'track_state',4);
[t3,c,okC]=xp9_series(run,'terrain_contact',4);
[t4,a,okA]=xp9_series(run,'drive_actuation',2);
if ~(okM&&okS&&okC&&okA&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
invalid=any(abs(m(:,1:3))>1e4,'all')||any(abs(m(:,4:5))>30,'all')|| ...
    any(abs(s(:,1:2))>30,'all')||any(abs(s(:,3:4))>8,'all')|| ...
    any(abs(c(:,3:4))>3e4,'all')||any(abs(c(:,1:2))>3e4,'all')|| ...
    any(abs(a)>3e4,'all');
if invalid,return;end
event=double(run.inputs.traction_event_time);eventEnd=event+1.2;
tail=t>=max(eventEnd+1.3,t(end)-1.8);pre=t>=event-.8&t<=event-.1;evt=t>=event+.08&t<=eventEnd-.05;
post=t>=eventEnd+.6&t<=min(t(end),eventEnd+1.6);
if nnz(tail)<40||nnz(pre)<30||nnz(evt)<60||nnz(post)<30,return;end
uL=s(:,1);uR=s(:,2);slip=s(:,3:4);v=m(:,4);yawRate=m(:,5);
FL=c(:,1);FR=c(:,2);NL=c(:,3);NR=c(:,4);width=1.2;
cmdL=double(run.inputs.left_track_command);cmdR=double(run.inputs.right_track_command);
r.track_error=max(median(abs(uL(tail)-cmdL)),median(abs(uR(tail)-cmdR)));
forwardRatio=median(v(tail))/max(median(.5*(abs(uL(tail))+abs(uR(tail)))),.20);
r.forward_response_error=distance_to_interval(forwardRatio,.50,1.08);
delta=cmdR-cmdL;
if abs(delta)<.08
    r.turn_response_error=median(abs(yawRate(tail)))/.20;
else
    turnRatio=median(yawRate(tail))*width/delta;
    r.turn_response_error=distance_to_interval(turnRatio,.30,1.45);
end
r.slip95=max(local_quantile(abs(slip(tail,:)),.95));
r.track_ripple=max(std(uL(tail))/max(abs(mean(uL(tail))),.25), ...
    std(uR(tail))/max(abs(mean(uR(tail))),.25));
sumF=FL+FR;r.force_ripple=std(sumF(tail))/max(mean(abs(sumF(tail))),100);

mTotal=720+double(run.inputs.payload_mass);grade=double(run.inputs.grade_angle)*pi/180;
r.negative_normal_violation=max(max(-[NL,NR],0),[],'all')/max(mTotal*9.81,1);
r.normal_balance_residual=median(abs(NL+NR-mTotal*9.81*cos(grade)))/(mTotal*9.81);
eventMask=t>=event&t<eventEnd;
muL=double(run.inputs.terrain_friction)*(1-double(run.inputs.left_traction_loss)*double(eventMask));
muR=double(run.inputs.terrain_friction)*ones(size(t));
excess=[max(abs(FL)-muL.*NL,0)./max(muL.*NL,100), ...
    max(abs(FR)-muR.*NR,0)./max(muR.*NR,100)];
r.friction_excess=max(local_quantile(excess,.99));
vLocal=[v-.5*width*yawRate,v+.5*width*yawRate];rel=[uL,uR]-vLocal;
expectedSlip=rel./max(max(abs([uL,uR]),abs(vLocal)),.35);
slipErr=abs(slip-expectedSlip);dynamic=t>.35;
r.slip_definition_residual=max(local_quantile(slipErr(dynamic,:),.95));
weights=abs(expectedSlip(dynamic,:));bad=(slip(dynamic,:).*expectedSlip(dynamic,:)<=0)&weights>.003;
r.slip_sign_violation=sum(weights(bad))/max(sum(weights(:)),1e-8);
    work=[FL,FR].*rel;
    v1=sum(max(-work,0),'all')/max(sum(abs(work),'all'),1);
    v2=sum(max(work,0),'all')/max(sum(abs(work),'all'),1);
    r.force_slip_violation=min(v1,v2); % diagnostic; suite fixes one global convention
eventCapacity=max(muL(evt).*NL(evt),100);
r.contact_binding=local_quantile(abs(FL(evt))./eventCapacity,.95);

dv=backward_rate(v,t);dr=backward_rate(yawRate,t);
r.event_slip_change=abs(median(abs(rel(evt,1)))-median(abs(rel(pre,1))))/max(.5*(cmdL+cmdR),.30);
r.event_force_change=abs(median(FL(evt))-median(FL(pre)))/(mTotal*9.81);
r.event_motion_change=max(abs(median(dv(evt))-median(dv(pre)))/9.81, ...
    width*abs(median(dr(evt))-median(dr(pre)))/9.81);
r.post_event_degradation=max([abs(median(uL(post))-median(uL(pre)))/max(abs(cmdL),.3), ...
    abs(median(uR(post))-median(uR(pre)))/max(abs(cmdR),.3), ...
    abs(median(v(post))-median(v(pre)))/max(abs(median(v(pre))),.3), ...
    width*abs(median(yawRate(post))-median(yawRate(pre)))/max(abs(delta),.2)]);
target=[median(v(pre)),median(yawRate(pre)),median(rel(pre,1))];
r.recovery_time=local_recovery(t,uL,uR,v,yawRate,rel(:,1),cmdL,cmdR,target,eventEnd);
r.valid=all(isfinite([r.track_error r.forward_response_error r.turn_response_error ...
    r.slip95 r.track_ripple r.force_ripple r.negative_normal_violation r.normal_balance_residual ...
    r.friction_excess r.force_slip_violation r.slip_definition_residual ...
    r.slip_sign_violation r.contact_binding r.event_slip_change ...
    r.event_force_change r.event_motion_change r.post_event_degradation])) ...
    &&~isnan(r.recovery_time);
end

function s=measure_suite(runs,rows)
s=empty_suite();Xt=[];drive=[];slipActivity=[];
uAll=[];aAll=[];cAll=[];relAll=[];
Xc=[];contactPower=[];knownPower=[];
zAll=[];vAll=[];psiAll=[];dpsiAll=[];rAll=[];
for i=1:numel(runs)
    run=runs(i);if string(run.stage)~="simulated",return;end
    [t,m,okM]=xp9_series(run,'vehicle_motion',5);
    [t2,tr,okT]=xp9_series(run,'track_state',4);
    [t3,c,okC]=xp9_series(run,'terrain_contact',4);
    [t4,a,okA]=xp9_series(run,'drive_actuation',2);
    if ~(okM&&okT&&okC&&okA&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
    fit=t>.45&t<t(end)-.08;u=tr(:,1:2);du=[backward_rate(u(:,1),t),backward_rate(u(:,2),t)];
    Xt=[Xt;u(fit,1).*du(fit,1),abs(u(fit,1)),u(fit,1).^2,abs(u(fit,1)).^3; ...
        u(fit,2).*du(fit,2),abs(u(fit,2)),u(fit,2).^2,abs(u(fit,2)).^3]; %#ok<AGROW>
    uAll=[uAll;u(fit,1);u(fit,2)]; %#ok<AGROW>
    aAll=[aAll;a(fit,1);a(fit,2)];cAll=[cAll;c(fit,1);c(fit,2)]; %#ok<AGROW>

    mass=720+double(run.inputs.payload_mass);grade=double(run.inputs.grade_angle)*pi/180;
    v=m(:,4);r=m(:,5);dv=backward_rate(v,t);dr=backward_rate(r,t);width=1.2;
    vL=v-.5*width*r;vR=v+.5*width*r;
    payload=double(run.inputs.payload_mass);
    Xc=[Xc;r(fit).*dr(fit),payload*r(fit).*dr(fit),abs(v(fit)),v(fit).^2, ...
        abs(v(fit)).^3,abs(r(fit)),r(fit).^2]; %#ok<AGROW>
    contactPower=[contactPower;c(fit,1).*vL(fit)+c(fit,2).*vR(fit)]; %#ok<AGROW>
    knownPower=[knownPower;mass*9.81*sin(grade).*v(fit)+mass*v(fit).*dv(fit)]; %#ok<AGROW>
    rel=[u(:,1)-vL,u(:,2)-vR];relAll=[relAll;rel(fit,1);rel(fit,2)]; %#ok<AGROW>
    drive=[drive;abs(a(fit,:))/(mass*9.81)]; %#ok<AGROW>
    slipActivity=[slipActivity;abs(tr(fit,3:4))]; %#ok<AGROW>

    dx=backward_rate(m(:,1),t);dy=backward_rate(m(:,2),t);dpsi=backward_rate(m(:,3),t);
    kin=fit&abs(v)>.08;
    zAll=[zAll;dx(kin)+1i*dy(kin)];vAll=[vAll;v(kin)]; %#ok<AGROW>
    psiAll=[psiAll;m(kin,3)];dpsiAll=[dpsiAll;dpsi(kin)];rAll=[rAll;r(kin)]; %#ok<AGROW>
end
% Infer one contact action/reaction sign and one actuator generalized-force
% sign for both sides and every run.  Losses may be absent (conservative),
% Coulomb, viscous, quadratic, or any nonnegative combination.
best=Inf;bt=nan(4,1);bc=nan(7,1);okT=false;okC=false;
for contactSign=[-1 1]
    work=contactSign*cAll.*relAll;
    directionViolation=sum(max(-work,0))/max(sum(abs(work)),1);
    for driveSign=[-1 1]
        yTrack=(driveSign*aAll-contactSign*cAll).*uAll;
        [rt,bTrack,trackOK]=fit_nonnegative_model(Xt,yTrack,30);
        yChassis=contactSign*contactPower-knownPower;
        [rc,bChassis,chassisOK]=fit_nonnegative_model(Xc,yChassis,50);
        trackPassive=trackOK&&numel(bTrack)==4&&bTrack(1)>1;
        chassisPassive=chassisOK&&numel(bChassis)==7&&any(bChassis(1:2)>1);
        objective=rt+rc+2*directionViolation+2*double(~trackPassive)+2*double(~chassisPassive);
        if objective<best
            best=objective;s.contact_force_sign=contactSign;s.drive_force_sign=driveSign;
            s.contact_power_direction_violation=directionViolation;
            s.track_power_residual=rt;s.chassis_power_residual=rc;
            bt=bTrack;bc=bChassis;okT=trackPassive;okC=chassisPassive;
        end
    end
end
s.track_power_coefficients=bt(:)';s.chassis_power_coefficients=bc(:)';
s.track_passive=okT;s.chassis_passive=okC;
s.drive_activity=local_quantile(drive(:),.80);
s.track_motion_activity=local_quantile(abs(uAll),.80);
s.contact_force_activity=local_quantile(abs(cAll),.80);
s.vehicle_motion_activity=local_quantile(abs(vAll),.80);
s.slip_activity=local_quantile(slipActivity(:),.80);
[s.planar_kinematic_residual,s.yaw_kinematic_residual,s.coordinate_sign,s.heading_offset,kinOK]= ...
    coordinate_closure(zAll,vAll,psiAll,dpsiAll,rAll);
[s.paired_valid,s.paired_binding,s.paired_effect_strength,s.paired_recovery_time, ...
    s.paired_no_loss_degradation,s.paired_loss_index,s.paired_loss_scenario]= ...
    measure_loss_pair(runs);
s.max_contact_binding=max([[rows.contact_binding],s.paired_binding]);
s.slip_activity_required=isfinite(s.max_contact_binding)&&s.max_contact_binding>=.55;
s.valid=okT&&okC&&kinOK&&s.paired_valid&&all(isfinite([s.track_power_residual ...
    s.chassis_power_residual s.contact_force_sign s.drive_force_sign ...
    s.contact_power_direction_violation s.drive_activity s.track_motion_activity ...
    s.contact_force_activity s.vehicle_motion_activity s.slip_activity s.max_contact_binding ...
    s.planar_kinematic_residual s.yaw_kinematic_residual s.paired_binding ...
    s.paired_effect_strength s.paired_no_loss_degradation s.paired_loss_index]))&& ...
    ~isnan(s.paired_recovery_time);
end

function tf=core_vehicle_contact_present(s)
% Existence gate only: all measured parts of the commanded-drive, moving
% track, terrain-contact and moving-chassis chain must be non-degenerate.
% Sign, passivity and equation-fit quality remain continuous M evidence.
activity=[s.drive_activity s.track_motion_activity ...
    s.contact_force_activity s.vehicle_motion_activity];
tf=all(isfinite(activity))&&all(activity>1e-8);
end

function tf=core_traction_event_present(rows,s)
% When no evaluated contact approaches its friction limit, a zero visible
% response is physically legitimate.  Once binding is observed, however,
% a completely identical loss/no-loss response means the public event path
% is absent.  The tolerance only removes floating-point noise; it is not a
% performance threshold.
tf=true;tol=1e-8;
for i=1:numel(rows)
    r=rows(i);if r.is_no_loss_control,continue;end
    if r.contact_binding>=.55
        evidence=max([r.event_slip_change r.event_force_change r.event_motion_change]);
        if ~(isfinite(evidence)&&evidence>tol),tf=false;return;end
    end
end
if s.paired_valid&&s.paired_binding>=.55&& ...
        ~(isfinite(s.paired_effect_strength)&&s.paired_effect_strength>tol)
    tf=false;
end
end

function d=distance_to_interval(x,lo,hi)
if x<lo,d=lo-x;elseif x>hi,d=x-hi;else,d=0;end
end

function dx=backward_rate(x,t)
dx=zeros(size(x));dx(2:end)=diff(x)./diff(t);dx(1)=dx(2);
end

function q=local_quantile(x,p)
x=double(x);
if isempty(x)
    % A technically runnable model may have no nonzero chassis-motion
    % samples.  Preserve that as missing/low capability evidence instead of
    % turning the evaluator itself into a platform failure.
    q=NaN(1,max(size(x,2),1));
    return
end
x=sort(x,1);n=size(x,1);k=max(1,min(n,ceil(p*n)));q=x(k,:);
end

function dt=local_recovery(t,uL,uR,v,r,relL,cmdL,cmdR,target,eventEnd)
dt=Inf;start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.35/median(diff(t))));
good=abs(uL-cmdL)<=.08&abs(uR-cmdR)<=.08&abs(v-target(1))<=.14& ...
    abs(r-target(2))<=.18&abs(relL-target(3))<=.09;
for k=start:max(start,numel(t)-window+1)
    if k+window-1<=numel(t)&&all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
end

function [xyRes,yawRes,sgn,phi,ok]=coordinate_closure(z,v,psi,dpsi,r)
xyRes=1;yawRes=1;sgn=NaN;phi=NaN;ok=false;
good=isfinite(real(z))&isfinite(imag(z))&isfinite(v)&isfinite(psi)&isfinite(dpsi)&isfinite(r);
z=z(good);v=v(good);psi=psi(good);dpsi=dpsi(good);r=r(good);
if numel(v)<100||rms(v)<.05,return;end
best=Inf;
for candidate=[-1 1]
    base=v.*exp(1i*candidate*psi);
    corr=sum(z.*conj(base));if abs(corr)<1e-10,continue;end
    ph=angle(corr);pred=base.*exp(1i*ph);
    xr=rms(abs(z-pred))/max(rms(v),.10);
    yr=rms(dpsi-candidate*r)/max(rms(r),.05);
    if xr+yr<best,best=xr+yr;xyRes=xr;yawRes=yr;sgn=candidate;phi=ph;end
end
ok=isfinite(best);
end

function [valid,binding,effect,recovery,degradation,lossIndex,lossScenario]=measure_loss_pair(runs)
% Evaluate every explicit loss/no-loss counterfactual and retain the pair
% with the strongest measured friction-limit binding.  This keeps neutral
% unbound contacts legal while ensuring the evaluator-owned binding probe
% actually tests the public traction-loss causal path.
valid=false;binding=NaN;effect=NaN;recovery=NaN;degradation=NaN;
lossIndex=NaN;lossScenario="";bestBinding=-Inf;
names=string({runs.scenario});
for candidate=1:numel(runs)
    if names(candidate)=="nominal"
        controlName="paired_no_loss";
    elseif endsWith(names(candidate),"_no_loss")
        continue
    else
        controlName=names(candidate)+"_no_loss";
    end
    iZero=find(names==controlName,1);if isempty(iZero),continue;end
    [pairValid,pairBinding,pairEffect,pairRecovery,pairDegradation]= ...
        measure_one_loss_pair(runs,candidate,iZero);
    if pairValid&&pairBinding>bestBinding
        valid=true;bestBinding=pairBinding;binding=pairBinding;effect=pairEffect;
        recovery=pairRecovery;degradation=pairDegradation;
        lossIndex=candidate;lossScenario=names(candidate);
    end
end
end

function [res,b,ok]=fit_nonnegative_model(X,y,floorValue)
res=1;b=nan(size(X,2),1);ok=false;
good=all(isfinite(X),2)&isfinite(y);X=X(good,:);y=y(good);
p=size(X,2);if size(X,1)<max(40,8*p)||rms(y)<1e-9,return;end
best=Inf;bestB=zeros(p,1);
for mask=1:(2^p-1)
    use=logical(bitget(mask,1:p));Xu=X(:,use);
    if rank(Xu)<nnz(use),continue;end
    bu=Xu\y;if any(bu<0)||any(~isfinite(bu)),continue;end
    candidate=zeros(p,1);candidate(use)=bu;err=rms(y-X*candidate);
    if err<best,best=err;bestB=candidate;end
end
if ~isfinite(best),return;end
b=bestB;res=best/max(rms(y),floorValue);ok=all(isfinite(b))&&isfinite(res);
end

function s=empty_suite()
s=struct('valid',false,'track_power_residual',NaN,'chassis_power_residual',NaN, ...
    'track_power_coefficients',nan(1,4),'chassis_power_coefficients',nan(1,7), ...
    'track_passive',false,'chassis_passive',false,'contact_force_sign',NaN, ...
    'drive_force_sign',NaN,'contact_power_direction_violation',NaN,'drive_activity',NaN, ...
    'track_motion_activity',NaN,'contact_force_activity',NaN, ...
    'vehicle_motion_activity',NaN, ...
    'slip_activity',NaN,'slip_activity_required',false,'max_contact_binding',NaN, ...
    'planar_kinematic_residual',NaN,'yaw_kinematic_residual',NaN, ...
    'coordinate_sign',NaN,'heading_offset',NaN,'paired_valid',false, ...
    'paired_binding',NaN,'paired_effect_strength',NaN,'paired_recovery_time',NaN, ...
    'paired_no_loss_degradation',NaN,'paired_loss_index',NaN, ...
    'paired_loss_scenario',"",'core_vehicle_contact',false, ...
    'core_traction_event',false);
end

function [valid,binding,effect,recovery,degradation]=measure_one_loss_pair(runs,iLoss,iZero)
valid=false;binding=NaN;effect=NaN;recovery=NaN;degradation=NaN;
[tL,mL,ok1]=xp9_series(runs(iLoss),'vehicle_motion',5);[tZ,mZ,ok2]=xp9_series(runs(iZero),'vehicle_motion',5);
[t2,sL,ok3]=xp9_series(runs(iLoss),'track_state',4);[t3,sZ,ok4]=xp9_series(runs(iZero),'track_state',4);
[t4,cL,ok5]=xp9_series(runs(iLoss),'terrain_contact',4);[t5,cZ,ok6]=xp9_series(runs(iZero),'terrain_contact',4);
if ~(ok1&&ok2&&ok3&&ok4&&ok5&&ok6&&isequal(tL,tZ)&&isequal(tL,t2)&&isequal(tL,t3)&&isequal(tL,t4)&&isequal(tL,t5)),return;end
event=double(runs(iLoss).inputs.traction_event_time);eventEnd=event+1.2;
evt=tL>=event+.08&tL<=eventEnd-.05;post=tL>=eventEnd+.6&tL<=min(tL(end),eventEnd+1.6);
if nnz(evt)<60||nnz(post)<30,return;end
mu=double(runs(iLoss).inputs.terrain_friction)*(1-double(runs(iLoss).inputs.left_traction_loss));
binding=local_quantile(abs(cL(evt,1))./max(mu*cL(evt,3),100),.95);
width=1.2;motion=max(median(abs(mL(evt,4)-mZ(evt,4)))/max(median(abs(mZ(evt,4))),.30), ...
    width*median(abs(mL(evt,5)-mZ(evt,5)))/max(abs(double(runs(iLoss).inputs.right_track_command)-double(runs(iLoss).inputs.left_track_command)),.20));
slip=max(median(abs(sL(evt,3:4)-sZ(evt,3:4))));
force=max(median(abs(cL(evt,1:2)-cZ(evt,1:2))))/max((720+double(runs(iLoss).inputs.payload_mass))*9.81,1);
effect=max([motion slip force]);
degradation=max([median(abs(sL(post,1:2)-sZ(post,1:2)),'all')/max(mean(abs(sZ(post,1:2)),'all'),.30), ...
    median(abs(mL(post,4)-mZ(post,4)))/max(median(abs(mZ(post,4))),.30), ...
    width*median(abs(mL(post,5)-mZ(post,5)))/max(abs(double(runs(iLoss).inputs.right_track_command)-double(runs(iLoss).inputs.left_track_command)),.20)]);
recovery=paired_recovery(tL,mL,sL,mZ,sZ,eventEnd);
valid=all(isfinite([binding effect degradation]))&&~isnan(recovery);
end

function dt=paired_recovery(t,mL,sL,mZ,sZ,eventEnd)
dt=Inf;start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.35/median(diff(t))));
good=max(abs(sL(:,1:2)-sZ(:,1:2)),[],2)<=.08&abs(mL(:,4)-mZ(:,4))<=.12& ...
    abs(mL(:,5)-mZ(:,5))<=.15&max(abs(sL(:,3:4)-sZ(:,3:4)),[],2)<=.08;
for k=start:max(start,numel(t)-window+1)
    if k+window-1<=numel(t)&&all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
end
