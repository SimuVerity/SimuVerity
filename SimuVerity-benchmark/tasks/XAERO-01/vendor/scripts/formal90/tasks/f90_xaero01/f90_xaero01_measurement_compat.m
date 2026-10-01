function varargout = f90_xaero01_measurement_compat(helperName, varargin)
%F90_XAERO01_MEASUREMENT_COMPAT R2025a-safe measurement dispatch.
%
% Contains only the measurement helpers required by the current extractor.

helperName = char(string(helperName));
switch helperName
    case "__list__"
        assert(nargout <= 1, ...
            "SimuVerity:f90_xaero01_measurement_compat:ListOutputs", ...
            "The helper list has one output.");
        if nargout == 1
            varargout{1} = ["empty_row", "measure_run", "shared_flight_evidence"];
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
    case "shared_flight_evidence"
        if nargout == 0
            shared_flight_evidence(varargin{:});
        else
            [varargout{1:nargout}] = shared_flight_evidence(varargin{:});
        end
    otherwise
        error("SimuVerity:f90_xaero01_measurement_compat:UnknownHelper", ...
            "Unsupported measurement helper: %s", helperName);
end
end

function r=empty_row()
r=struct('scenario',"",'valid',false,'hover_error',NaN,'hover_speed',NaN, ...
    'hover_attitude',NaN,'max_tilt',NaN,'motor_saturation_fraction',NaN, ...
    'path_overshoot',NaN,'path_orthogonal_deviation',NaN,'energy_used_Wh',NaN, ...
    'initial_position_error',NaN,'initial_speed_error',NaN, ...
    'propulsion_rating_violation',NaN,'thrust_rating_violation',NaN, ...
    'rotor_speed_rating_violation',NaN,'power_rating_violation',NaN, ...
    'energy_nonnegative_violation',NaN,'baseline_wind_error',NaN, ...
    'energy_balance_residual',NaN, ...
    'gust_signature_error',NaN,'payload_signature_error',NaN,'payload_schedule_error',NaN, ...
    'gust_physical_response_deficit',NaN,'payload_physical_response_deficit',NaN, ...
    'event_consistency_error',NaN, ...
    'gust_recovery_time',NaN,'payload_recovery_time',NaN);
end

function r=measure_run(run)
r=empty_row();r.scenario=string(run.scenario);
if string(run.stage)~="simulated",return;end
[t,f,okF]=xp9_series(run,'flight_state',12);
[t2,p,okP]=xp9_series(run,'propulsion',10);
[t3,e,okE]=xp9_series(run,'environment_state',4);
if ~(okF&&okP&&okE&&isequal(t,t2)&&isequal(t,t3)),return;end
% G rejects malformed/non-finite data (handled by xp9_series) and gross
% numerical explosions only.  Finite flight-envelope, actuator-rating,
% energy and environment errors are task performance and are scored below.
bad=any(abs(f)>1e6,'all')||any(abs(p(:,1:4))>1e5,'all')|| ...
        any(abs(p(:,5:8))>1e7,'all')||any(abs(p(:,9))>1e9)|| ...
        any(abs(p(:,10))>1e12)||any(abs(e)>1e6,'all');
if bad,return;end

target=[double(run.inputs.target_x),double(run.inputs.target_y),double(run.inputs.target_z)];
gust=double(run.inputs.gust_time);gustEnd=gust+1.2;release=double(run.inputs.payload_release_time);
tail=t>=max([t(end)-2.0,gustEnd+1.5,release+1.5]);
preG=t>=gust-.60&t<=gust-.10;evtG=t>=gust+.12&t<=gust+1.02;
preP=t>=release-.60&t<=release-.10;postP=t>=release+.10&t<=release+.55;
if nnz(tail)<100||nnz(preG)<80||nnz(evtG)<100||nnz(preP)<80||nnz(postP)<80,return;end
pos=f(:,1:3);vel=f(:,4:6);ang=f(:,7:9);rate=f(:,10:12);
posErr=sqrt(sum((pos-target).^2,2));speed=sqrt(sum(vel.^2,2));
r.hover_error=median(posErr(tail));r.hover_speed=median(speed(tail));
r.hover_attitude=median(sqrt(sum(rate(tail,:).^2,2)));
r.max_tilt=max(max(abs(ang(:,1:2)),[],2));
r.motor_saturation_fraction=mean(any(p(:,1:4)>=19.8|p(:,1:4)<0,2));
unitTarget=target/max(norm(target),.1);projection=pos*unitTarget';
r.path_overshoot=max(max(projection/max(norm(target),.1)-1,0));
r.path_orthogonal_deviation=max(sqrt(sum((pos-projection*unitTarget).^2,2))) / ...
    max(norm(target),.1);
r.energy_used_Wh=p(1,10)-p(end,10);
r.initial_position_error=norm(pos(1,:));r.initial_speed_error=norm(vel(1,:));
r.thrust_rating_violation=max([max(max(p(:,1:4)-20,0),[],'all'), ...
    max(max(-p(:,1:4),0),[],'all')])/20;
r.rotor_speed_rating_violation=max([max(max(p(:,5:8)-1100,0),[],'all'), ...
    max(max(-p(:,5:8),0),[],'all')])/1100;
r.power_rating_violation=max([max(max(p(:,9)-2400,0)),max(max(-p(:,9),0))])/2400;
energyScale=max(abs(p(1,10)),1);
r.energy_nonnegative_violation=max(max(-p(:,10),0))/energyScale;
r.propulsion_rating_violation=max([r.thrust_rating_violation, ...
    r.rotor_speed_rating_violation,r.power_rating_violation, ...
    r.energy_nonnegative_violation]);

mass=3.2+double(run.inputs.payload_mass)*double(t<release);
thrust=p(:,1:4);T=sum(thrust,2);acc=local_derivative(vel,t);mask=t>.15&abs(t-release)>.15;
dEnergy=gradient(p(:,10),t);r.energy_balance_residual= ...
    sqrt(mean((dEnergy(mask)+p(mask,9)/3600).^2))/max(mean(p(mask,9))/3600,1e-5);

windStep=median(e(evtG,1:3),1)-median(e(preG,1:3),1);
expectedWind=double(run.inputs.wind_speed)*double(run.inputs.gust_factor);
head=double(run.inputs.wind_heading)*pi/180;expectedBase= ...
    double(run.inputs.wind_speed)*[cos(head),sin(head),0];
outsideGust=~(t>=gust&t<gustEnd);
r.baseline_wind_error=median(sqrt(sum((e(outsideGust,1:3)-expectedBase).^2,2))) / ...
    max(double(run.inputs.wind_speed),.2);
horizontalStep=windStep(1:2);magnitudeError= ...
    abs(norm(horizontalStep)-expectedWind)/max(expectedWind,.2);
if expectedWind>.05&&norm(horizontalStep)>.02
    along=[cos(head),sin(head)];crossError=abs(dot(horizontalStep/norm(horizontalStep),along));
    crossError=max(0,crossError-.5)/.5;
else
    crossError=0;
end
r.gust_signature_error=max(magnitudeError,crossError);
payloadExpected=double(run.inputs.payload_mass)*double(t<release);
payloadScale=max(double(run.inputs.payload_mass),.2);
r.payload_schedule_error=sqrt(mean((e(:,4)-payloadExpected).^2))/payloadScale;
payloadDrop=median(e(preP,4))-median(e(postP,4));
r.payload_signature_error=max(r.payload_schedule_error, ...
    abs(payloadDrop-double(run.inputs.payload_mass))/payloadScale);
gustAcceleration=norm(median(acc(evtG,:),1)-median(acc(preG,:),1));
gustThrust=norm(median(thrust(evtG,:),1)-median(thrust(preG,:),1))/max(mean(mass(preG))*9.81,1);
gustTilt=norm(median(ang(evtG,1:2),1)-median(ang(preG,1:2),1));
gustEvidence=max([gustAcceleration/.12,gustThrust/.025,gustTilt/.02]);
r.gust_physical_response_deficit=max(0,1-gustEvidence);
payloadAcceleration=norm(median(acc(postP,:),1)-median(acc(preP,:),1));
payloadThrust=abs(median(T(postP))-median(T(preP)))/max(double(run.inputs.payload_mass)*9.81,.2);
payloadEvidence=max(payloadAcceleration/.12,payloadThrust/.12);
r.payload_physical_response_deficit=max(0,1-payloadEvidence);
r.event_consistency_error=max([r.gust_signature_error,r.payload_signature_error, ...
    r.gust_physical_response_deficit,r.payload_physical_response_deficit]);
r.gust_recovery_time=local_recovery(t,posErr,speed,gustEnd,median(posErr(preG)));
r.payload_recovery_time=local_recovery(t,posErr,speed,release,median(posErr(preP)));
r.valid=all(isfinite([r.hover_error r.hover_speed r.hover_attitude r.max_tilt ...
    r.motor_saturation_fraction r.path_overshoot r.path_orthogonal_deviation r.energy_used_Wh ...
    r.initial_position_error r.initial_speed_error r.propulsion_rating_violation ...
    r.thrust_rating_violation r.rotor_speed_rating_violation ...
    r.power_rating_violation r.energy_nonnegative_violation ...
    r.baseline_wind_error r.payload_schedule_error ...
    r.energy_balance_residual r.gust_signature_error r.payload_signature_error ...
    r.gust_physical_response_deficit r.payload_physical_response_deficit ...
    r.event_consistency_error r.gust_recovery_time r.payload_recovery_time]));
end

function [flight,angular,propulsion]=shared_flight_evidence(runs)
relativeWorld=[];forceWorld=[];relativeBody=[];forceBody=[];
angularX=zeros(0,15);angularMix=zeros(0,3);
angularRelativeWorld=[];angularRelativeBody=[];angularScenario=[];
eulerResidual=[];eulerScale=[];rotorX=[];rotorY=[];
powerThrust=[];powerOmega=[];powerY=[];
for i=1:numel(runs)
    run=runs(i);[t,f,okF]=xp9_series(run,'flight_state',12);
    [t2,p,okP]=xp9_series(run,'propulsion',10);[t3,e,okE]=xp9_series(run,'environment_state',4);
    if ~(okF&&okP&&okE&&isequal(t,t2)&&isequal(t,t3)),continue;end
    vel=f(:,4:6);ang=f(:,7:9);rate=f(:,10:12);thrust=p(:,1:4);omega=p(:,5:8);
    acc=local_derivative(vel,t);dRate=local_derivative(rate,t);T=sum(thrust,2);
    roll=ang(:,1);pitch=ang(:,2);yaw=atan2(sin(ang(:,3)),cos(ang(:,3)));
    bodyZ=[cos(yaw).*sin(pitch).*cos(roll)+sin(yaw).*sin(roll), ...
        sin(yaw).*sin(pitch).*cos(roll)-cos(yaw).*sin(roll), ...
        cos(pitch).*cos(roll)];
    thrustWorld=bodyZ.*T;mass=3.2+e(:,4);gravity=[zeros(numel(t),2),9.81*ones(numel(t),1)];
    relative=e(:,1:3)-vel;
    gust=double(run.inputs.gust_time);release=double(run.inputs.payload_release_time);
    % Rotor-to-body angular closure is evaluated away from the declared
    % gust transient and release discontinuity.  Background-wind moments
    % remain legal and are represented by shared nuisance families below.
    mask=t>.15&~(t>=gust-.12&t<=gust+1.32)&abs(t-release)>.15;
    idx=find(mask);stride=max(1,round(.01/median(diff(t))));idx=idx(1:stride:end);
    oneForce=mass.*(acc+gravity)-thrustWorld;
    relativeWorld=[relativeWorld;relative(idx,:)];forceWorld=[forceWorld;oneForce(idx,:)]; %#ok<AGROW>
    bodyRelative=world_to_body(relative,roll,pitch,yaw);
    bodyForce=world_to_body(oneForce,roll,pitch,yaw);
    relativeBody=[relativeBody;bodyRelative(idx,:)];forceBody=[forceBody;bodyForce(idx,:)]; %#ok<AGROW>
    ct=max(cos(pitch),.15);
    expectedEulerRate=[rate(:,1)+rate(:,2).*sin(roll).*tan(pitch)+rate(:,3).*cos(roll).*tan(pitch), ...
        rate(:,2).*cos(roll)-rate(:,3).*sin(roll), ...
        rate(:,2).*sin(roll)./ct+rate(:,3).*cos(roll)./ct];
    % Yaw is periodic and the public contract does not prescribe an
    % absolute branch.  Differentiate a continuous unwrapped branch so a
    % legal +/-pi wrap cannot create a false kinematic impulse.
    kinematicAngles=[roll,pitch,unwrap(yaw)];
    measuredEulerRate=local_derivative(kinematicAngles,t);
    eulerResidual=[eulerResidual;measuredEulerRate(idx,:)-expectedEulerRate(idx,:)]; %#ok<AGROW>
    eulerScale=[eulerScale;expectedEulerRate(idx,:)]; %#ok<AGROW>
    diffThrust=[thrust(:,2)+thrust(:,4)-thrust(:,1)-thrust(:,3), ...
        thrust(:,3)+thrust(:,4)-thrust(:,1)-thrust(:,2), ...
        thrust(:,1)-thrust(:,2)-thrust(:,3)+thrust(:,4)];
    oneX=rigid_body_regression(rate(idx,:),dRate(idx,:),zeros(numel(idx),3));
    angularX=[angularX;oneX];angularMix=[angularMix;diffThrust(idx,:)]; %#ok<AGROW>
    angularRelativeWorld=[angularRelativeWorld;relative(idx,:)]; ...
        angularRelativeBody=[angularRelativeBody;bodyRelative(idx,:)]; ...
        angularScenario=[angularScenario;i*ones(numel(idx),1)]; %#ok<AGROW>
    for rotor=1:4
        use=idx(thrust(idx,rotor)>.5&omega(idx,rotor)>.5);
        oneHot=zeros(numel(use),4);oneHot(:,rotor)=1;
        rotorX=[rotorX;oneHot,log(omega(use,rotor))];rotorY=[rotorY;log(thrust(use,rotor))]; %#ok<AGROW>
    end
    powerThrust=[powerThrust;thrust(idx,:)];powerOmega=[powerOmega;omega(idx,:)]; ...
        powerY=[powerY;p(idx,9)]; %#ok<AGROW>
end

[flightResidual,dragModel,dragCandidates]=best_drag_family( ...
    relativeWorld,forceWorld,relativeBody,forceBody);
dragDirectionError=1;if ~isempty(relativeWorld),dragDirectionError=mean(sum(relativeWorld.*forceWorld,2)<-.01);end
flightError=max(flightResidual,dragDirectionError);
eulerError=1;
if ~isempty(eulerResidual)
    eulerError=sqrt(mean(eulerResidual.^2,'all'))/max(sqrt(mean(eulerScale.^2,'all')),.02);
end
flight=struct('error',flightError,'force_balance_residual',flightResidual, ...
    'relative_wind_direction_error',dragDirectionError,'selected_drag_family',dragModel, ...
    'drag_family_candidates',dragCandidates, ...
    'euler_kinematic_error',eulerError);

% Rotor numbering, positive body-axis convention, and whether the public
% arm denotes an axis-projected or radial X-layout distance are not fixed
% by the task.  Evaluate a finite set of physically valid, globally shared
% candidates.  Signs and positive arm interpretation are selected once
% across every scenario; they cannot change per sample or per run.
candidateFits=struct([]);candidateSummary=struct([]);
armValues=[.32,.32/sqrt(2)];
armNames=["axis-projected","x-layout-radial-arm"];
for armIndex=1:numel(armValues)
    for rollSign=[-1,1]
        for pitchSign=[-1,1]
            for yawSign=[-1,1]
                moment=[rollSign*armValues(armIndex)*angularMix(:,1), ...
                    pitchSign*armValues(armIndex)*angularMix(:,2), ...
                    yawSign*.018*angularMix(:,3)];
                angularY=reshape(moment.',[],1);
                oneFit=fit_rigid_body(angularX,angularY,angularRelativeWorld, ...
                    angularRelativeBody,angularScenario);
                oneFit.roll_mixing_sign=rollSign;
                oneFit.pitch_mixing_sign=pitchSign;
                oneFit.yaw_mixing_sign=yawSign;
                oneFit.effective_arm=armValues(armIndex);
                oneFit.arm_representation=armNames(armIndex);
                candidateFits=[candidateFits;oneFit]; %#ok<AGROW>
                oneSummary=struct('roll_mixing_sign',rollSign, ...
                    'pitch_mixing_sign',pitchSign,'yaw_mixing_sign',yawSign, ...
                    'effective_arm',armValues(armIndex), ...
                    'arm_representation',armNames(armIndex),'error',oneFit.error);
                candidateSummary=[candidateSummary;oneSummary]; %#ok<AGROW>
            end
        end
    end
end
[~,bestCandidate]=min([candidateFits.error]);angular=candidateFits(bestCandidate);
angular.mixing_candidates=candidateSummary;
angular.yaw_plus_candidate_error=min([candidateFits([candidateFits.yaw_mixing_sign]>0).error]);
angular.yaw_minus_candidate_error=min([candidateFits([candidateFits.yaw_mixing_sign]<0).error]);
angular.core_dynamics_supported=angular.rigid_body_residual<=.05&& ...
    angular.inertia_positive_definite_violation<=.02;
angular.mechanism_completion_cap=1;
if ~angular.core_dynamics_supported,angular.mechanism_completion_cap=.35;end

rotorResidual=1;rotorExponent=NaN;rotorCorrelation=-1;
if size(rotorX,1)>=100&&rank(rotorX)==size(rotorX,2)
    beta=rotorX\rotorY;rotorExponent=beta(end);pred=rotorX*beta;
    rotorResidual=sqrt(mean((rotorY-pred).^2));
    rotorCorrelation=positive_correlation(rotorX(:,end),rotorY);
end
rotorError=max([rotorResidual,double(rotorExponent<=0),(1-rotorCorrelation)/2]);
speedCV=NaN;speedThrustCorrelation=NaN;speedRepresentation="unresolved";
if ~isempty(powerOmega)
    speedCV=median(std(powerOmega,0,1)./max(mean(powerOmega,1),1));
    speedThrustCorrelation=positive_correlation(powerOmega(:),powerThrust(:));
    if speedCV<=.02
        speedRepresentation="constant-speed-or-variable-pitch";
    elseif speedThrustCorrelation<0
        speedRepresentation="load-droop-or-variable-pitch";
    elseif rotorError<=.14
        speedRepresentation="positive-speed-thrust-law";
    else
        speedRepresentation="other-bounded-speed-report";
    end
end
[powerError,powerModel,powerCandidates]=best_monotone_power_family( ...
    powerThrust,powerOmega,powerY);
powerResidual=powerModel.residual;
propulsion=struct('error',powerError, ...
    'rotor_log_residual',rotorResidual,'shared_rotor_exponent',rotorExponent, ...
    'rotor_monotone_correlation',rotorCorrelation,'power_residual',powerResidual, ...
    'rotor_relation_error_diagnostic',rotorError, ...
    'rotor_speed_coefficient_of_variation',speedCV, ...
    'speed_thrust_correlation',speedThrustCorrelation, ...
    'speed_representation',speedRepresentation, ...
    'speed_thrust_relation_is_diagnostic',true, ...
    'selected_power_feature',powerModel.feature, ...
    'selected_power_family',powerModel.family, ...
    'power_direction_error',powerModel.direction_error, ...
    'power_coefficients',powerModel.coefficients, ...
    'power_family_candidates',powerCandidates);
end

function dt=local_recovery(t,posErr,speed,eventEnd,baseline)
dt=max(t(end)-eventEnd+1,0);start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.35/median(diff(t))));
good=posErr<=max(baseline+.45,.65)&speed<=.65;
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

function [bestError,best,candidates]=best_monotone_power_family(thrust,omega,power)
% The public task does not prescribe fixed pitch, a motor map, or a
% speed-controlled rotor. Power is checked against the actual load feature
% used by each candidate, while rotor speed remains a bounded diagnostic.
blank=struct('feature',"none",'family',"none",'residual',1, ...
    'direction_error',1,'score',1,'coefficients',NaN);
best=blank;bestError=1;candidates=repmat(blank,0,1);
if size(thrust,1)<100||size(omega,1)~=size(thrust,1)||numel(power)~=size(thrust,1)
    return;
end
features={sum(thrust,2),sum(max(thrust,0).^1.5,2),sum(thrust.^2,2), ...
    sum(thrust.*max(omega,0),2)};
names=["total-thrust","sum-thrust-3-over-2","sum-thrust-squared", ...
    "thrust-speed-load"];
for k=1:numel(features)
    one=fit_power_feature(features{k},power,names(k));
    candidates=[candidates;one(:)]; %#ok<AGROW>
    [candidateError,j]=min([one.score]);
    if candidateError<bestError
        bestError=candidateError;best=one(j);
    end
end
end

function [bestError,bestName,candidates]=best_drag_family(rw,fw,rb,fb)
names=["world-linear","world-quadratic","world-linear-plus-quadratic", ...
    "body-linear","body-quadratic","body-linear-plus-quadratic"];
features={rw,rw.*abs(rw),[rw,rw.*abs(rw)],rb,rb.*abs(rb),[rb,rb.*abs(rb)]};
targets={fw,fw,fw,fb,fb,fb};
candidates=repmat(struct('name',"",'residual',1,'coefficients',NaN),numel(names),1);
bestError=1;bestName="none";
for k=1:numel(names)
    X=features{k};Y=targets{k};residual=1;beta=NaN;
    if size(X,1)>=100&&rank(X)>=size(X,2)
        beta=X\Y;pred=X*beta;
        residual=sqrt(mean((Y-pred).^2,'all'))/max(sqrt(mean(Y.^2,'all')),1);
    end
    candidates(k)=struct('name',names(k),'residual',residual,'coefficients',beta);
    if residual<bestError,bestError=residual;bestName=names(k);end
end
end

function body=world_to_body(world,roll,pitch,yaw)
cr=cos(roll);sr=sin(roll);cp=cos(pitch);sp=sin(pitch);cy=cos(yaw);sy=sin(yaw);
body=[cy.*cp.*world(:,1)+sy.*cp.*world(:,2)-sp.*world(:,3), ...
    (cy.*sp.*sr-sy.*cr).*world(:,1)+(sy.*sp.*sr+cy.*cr).*world(:,2)+cp.*sr.*world(:,3), ...
    (cy.*sp.*cr+sy.*sr).*world(:,1)+(sy.*sp.*cr-cy.*sr).*world(:,2)+cp.*cr.*world(:,3)];
end

function fit=fit_rigid_body(X,y,relativeWorld,relativeBody,scenario)
blank=struct('error',1,'rigid_body_residual',1, ...
    'inertia_positive_definite_violation',1,'damping_sign_violation',1, ...
    'fitted_inertia',NaN(3),'inertia_eigenvalues',NaN(1,3), ...
    'fitted_damping',NaN(3),'external_moment_family',"none", ...
    'external_moment_coefficients',NaN);
fit=blank;
if size(X,1)<300||size(X,2)~=15||size(relativeWorld,1)*3~=size(X,1),return;end
n=size(relativeWorld,1);labels=unique(scenario(:))';oneHot=zeros(n,numel(labels));
for k=1:numel(labels),oneHot(:,k)=double(scenario==labels(k));end
worldQuadratic=relativeWorld.*abs(relativeWorld);
bodyQuadratic=relativeBody.*abs(relativeBody);
names=["none","scenario-offset","world-linear","world-quadratic", ...
    "world-linear-plus-quadratic","body-linear","body-quadratic", ...
    "body-linear-plus-quadratic","scenario-plus-world-combined", ...
    "scenario-plus-body-combined"];
features={zeros(n,0),oneHot,relativeWorld,worldQuadratic, ...
    [relativeWorld,worldQuadratic],relativeBody,bodyQuadratic, ...
    [relativeBody,bodyQuadratic],[oneHot,relativeWorld,worldQuadratic], ...
    [oneHot,relativeBody,bodyQuadratic]};
best=Inf;
for k=1:numel(names)
    external=axis_feature_matrix(features{k});design=[X,external];
    if rank(X(:,1:6))<6,continue;end
    beta=lsqminnorm(design,y,1e-10);prediction=design*beta;
    dynamicScale=max(sqrt(mean(y.^2)),.02);
    residual=sqrt(mean((y-prediction).^2))/dynamicScale;
    inertia=[beta(1),beta(4),beta(5);beta(4),beta(2),beta(6);beta(5),beta(6),beta(3)];
    ev=eig((inertia+inertia')/2);
    inertiaViolation=max(0,-min(ev))/max(max(abs(ev)),1e-4);
    damping=reshape(beta(7:15),3,3)';dampingEv=eig((damping+damping')/2);
    dampingViolation=max(0,-min(dampingEv))/max(max(abs(dampingEv)),1e-4);
    score=max([residual,inertiaViolation,dampingViolation]);
    if score<best
        best=score;fit=blank;fit.error=score;fit.rigid_body_residual=residual;
        fit.inertia_positive_definite_violation=inertiaViolation;
        fit.damping_sign_violation=dampingViolation;fit.fitted_inertia=inertia;
        fit.inertia_eigenvalues=ev';fit.fitted_damping=damping;
        fit.external_moment_family=names(k);fit.external_moment_coefficients=beta(16:end)';
    end
end
end

function [X,y]=rigid_body_regression(w,a,moment)
% M = I*wdot + w x (I*w) + D*w - M_external.  I is symmetric;
% D is a full matrix whose symmetric part must be passive.  A separate
% shared candidate family represents M_external in fit_rigid_body.
n=size(w,1);X=zeros(3*n,15);y=zeros(3*n,1);
for k=1:n
    p=w(k,1);q=w(k,2);r=w(k,3);ap=a(k,1);aq=a(k,2);ar=a(k,3);
    j=3*(k-1);
    X(j+1,:)=[ap,-r*q,q*r,aq-r*p,ar+q*p,q^2-r^2,p,q,r,0,0,0,0,0,0];
    X(j+2,:)=[r*p,aq,-p*r,ap+r*q,r^2-p^2,ar-p*q,0,0,0,p,q,r,0,0,0];
    X(j+3,:)=[-p*q,p*q,ar,p^2-q^2,ap-q*r,aq+p*r,0,0,0,0,0,0,p,q,r];
    y(j+(1:3))=moment(k,:)';
end
end

function c=positive_correlation(x,y)
x=double(x(:));y=double(y(:));c=-1;if numel(x)<20,return;end
x=x-mean(x);y=y-mean(y);den=sqrt(sum(x.^2)*sum(y.^2));if den>eps,c=sum(x.*y)/den;end
c=min(max(c,-1),1);
end

function candidates=fit_power_feature(x,y,name)
blank=struct('feature',name,'family',"none",'residual',1, ...
    'direction_error',1,'score',1,'coefficients',NaN);
candidates=repmat(blank,4,1);
x=double(x(:));y=double(y(:));good=isfinite(x)&isfinite(y)&x>=0&y>=0;
x=x(good);y=y(good);
if numel(x)<100,return;end
x0=min(x);xr=max(x)-x0;
if xr<=1e-7*max(max(abs(x)),1),return;end
xn=(x-x0)/xr;yScale=max([std(y),.03*mean(abs(y)),1]);
slopeTol=1e-9*max(yScale,1);

X=[ones(numel(xn),1),xn];beta=X\y;pred=X*beta;
candidates(1)=power_candidate(name,"affine",y,pred,beta, ...
    double(beta(2)<=slopeTol),yScale);

X=[ones(numel(xn),1),xn,xn.^2];beta=X\y;pred=X*beta;
% The derivative is evaluated in this candidate's own feature. In
% particular, sum(T_i^2) is never differentiated as though it were
% (sum(T_i))^2.
slope=beta(2)+2*beta(3)*xn;
candidates(2)=power_candidate(name,"quadratic",y,pred,beta, ...
    mean(slope<=slopeTol),yScale);

[pred,beta]=best_log_prediction(xn,y);
candidates(3)=power_candidate(name,"logarithmic",y,pred,beta, ...
    double(beta(2)<=slopeTol),yScale);

[pred,netRise]=monotone_prediction(xn,y);
directionError=double(netRise<=1e-6*max([max(y)-min(y),mean(abs(y)),1]));
candidates(4)=power_candidate(name,"shape-constrained",y,pred,NaN, ...
    directionError,yScale);
end

function A=axis_feature_matrix(Z)
% Map one shared scalar feature table to three independent body-moment
% components.  Families are global across all scenarios; they cannot absorb
% arbitrary per-time-step trajectories.
n=size(Z,1);p=size(Z,2);A=zeros(3*n,3*p);
if p==0,return;end
A(1:3:end,1:p)=Z;
A(2:3:end,p+(1:p))=Z;
A(3:3:end,2*p+(1:p))=Z;
end

function [bestPrediction,bestBeta]=best_log_prediction(x,y)
bestSse=Inf;bestPrediction=mean(y)*ones(size(y));bestBeta=[mean(y);0;NaN];
for k=logspace(-3,3,31)
    z=log1p(k*x);X=[ones(numel(z),1),z];beta=X\y;prediction=X*beta;
    sse=mean((y-prediction).^2);
    if sse<bestSse
        bestSse=sse;bestPrediction=prediction;bestBeta=[beta;k];
    end
end
end

function c=power_candidate(feature,family,y,pred,beta,directionError,yScale)
residual=sqrt(mean((y-pred).^2))/yScale;
c=struct('feature',feature,'family',family,'residual',residual, ...
    'direction_error',directionError,'score',max(residual,directionError), ...
    'coefficients',beta(:)');
end

function [prediction,netRise]=monotone_prediction(x,y)
% Quantile bins prevent a high-resolution isotonic fit from memorising an
% arbitrary power trace. PAVA supplies a representation-neutral monotone
% check over only the observed load range.
[xs,order]=sort(x);ys=y(order);n=numel(xs);nBins=min(24,max(6,floor(n/80)));
edges=round(linspace(0,n,nBins+1));bx=zeros(nBins,1);by=zeros(nBins,1);
for b=1:nBins
    use=(edges(b)+1):edges(b+1);bx(b)=median(xs(use));by(b)=median(ys(use));
end
[bx,ia]=unique(bx,'stable');by=by(ia);
if numel(bx)<3,prediction=mean(y)*ones(size(y));netRise=0;return;end
fit=pava_increasing(by);netRise=fit(end)-fit(1);
predSorted=interp1(bx,fit,xs,'linear','extrap');prediction=zeros(size(y));
prediction(order)=predSorted;
end

function fit=pava_increasing(y)
level=y(:);weight=ones(size(level));first=(1:numel(level))';last=first;
m=numel(level);i=1;
while i<m
    if level(i)<=level(i+1),i=i+1;continue;end
    w=weight(i)+weight(i+1);
    level(i)=(weight(i)*level(i)+weight(i+1)*level(i+1))/w;
    weight(i)=w;last(i)=last(i+1);
    level(i+1)=[];weight(i+1)=[];first(i+1)=[];last(i+1)=[];m=m-1;
    if i>1,i=i-1;end
end
fit=zeros(numel(y),1);
for i=1:m,fit(first(i):last(i))=level(i);end
end
