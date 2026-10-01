function out=xp9_score_xfluid01(runs,spec)
%XP9_SCORE_XFLUID01 Representation-neutral pressure-flow-motion score.
% Pump-side branch deliveries are public nonnegative quantities.  Signed
% pressure/flow/torque conventions and raw/effective valve representations
% are inferred once and then held fixed across the complete run suite.
out=empty_out();rows=repmat(empty_row(),numel(runs),1);allValid=true;
for i=1:numel(runs)
    rows(i)=measure_run(runs(i));allValid=allValid&&rows(i).valid;
end
suite=measure_suite(runs,rows);
suite.core_hydraulic_path=core_hydraulic_path_present(suite,rows);
suite.core_leak_event=core_leak_event_present(suite,rows);
out.score_inputs_valid=allValid&&numel(runs)==1+numel(spec.scenarios);
out.diagnostics_valid=out.score_inputs_valid&&suite.valid;out.G=out.score_inputs_valid;
if ~out.G,out.gate_reasons="SCENARIO_OR_HYDRAULIC_OUTPUT_CONTRACT_INVALID";end
out.scenario_rows=rows;out.suite_metrics=suite;

if ~isempty(rows)
    n=rows(1);
    qAngle=zeros(1,3);qVel=zeros(1,3);
    for k=1:3
        qAngle(k)=xp9_utility(n.angle_error_by_axis(k),[0 .12 .30 .70 1.8 4.5],[1 1 .95 .75 .28 0]);
        qVel(k)=xp9_utility(n.tail_velocity_by_axis(k),[0 .08 .20 .50 1.4 4],[1 1 .95 .73 .25 0]);
    end
    out.A=xp9_group([qAngle qVel],[.78/3*ones(1,3) .22/3*ones(1,3)],true);
    qPress=xp9_utility(n.pump_ripple,[0 .002 .008 .025 .08 .22],[1 1 .95 .75 .28 0]);
    qValve=zeros(1,3);
    for k=1:3
        qValve(k)=xp9_utility(n.valve_ripple_by_axis(k),[0 .002 .008 .025 .08 .20],[1 1 .95 .73 .25 0]);
    end
    qFlow=xp9_utility(n.flow_utilization,[0 .65 .85 .95 1.00 1.18],[1 1 .96 .88 .70 0]);
    out.Q=xp9_group([qPress qValve qFlow],[.35 .25/3*ones(1,3) .40],true);

    qCont=zeros(1,3);qTorque=zeros(1,3);qPower=zeros(1,3);qMech=zeros(1,3);qOpening=zeros(1,3);
    for k=1:3
        qCont(k)=xp9_utility(suite.continuity_residual(k),[0 .018 .05 .13 .32 .70],[1 1 .94 .72 .25 0]);
        qOpening(k)=xp9_utility(suite.opening_flow_residual(k),[0 .025 .07 .17 .38 .75],[1 1 .94 .72 .25 0]);
        qTorque(k)=xp9_utility(suite.pressure_torque_residual(k),[0 .018 .05 .13 .32 .70],[1 1 .94 .72 .25 0]);
        qPower(k)=xp9_utility(suite.hydraulic_power_residual(k),[0 .015 .045 .12 .30 .68],[1 1 .94 .72 .25 0]);
        qMech(k)=xp9_utility(suite.mechanical_residual(k),[0 .025 .07 .17 .38 .78],[1 1 .94 .72 .25 0]);
    end
    qRate=xp9_utility(suite.state_rate_residual,[0 .006 .018 .05 .15 .45],[1 1 .95 .75 .28 0]);
    qPump=xp9_utility(max([rows.pump_flow_residual]),[0 .006 .018 .05 .15 .45],[1 1 .95 .75 .28 0]);
    qZero=xp9_utility(suite.zero_valve_flow_ratio,[0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
    qSupplyUpper=xp9_utility(max([rows.supply_pressure_upper_violation]), ...
        [0 .002 .008 .025 .08 .25],[1 1 .95 .75 .28 0]);
    qSupplyNegative=xp9_utility(max([rows.negative_supply_pressure_violation]), ...
        [0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
    qBranchPressure=xp9_utility(max([rows.branch_pressure_envelope_violation]), ...
        [0 .002 .008 .025 .08 .25],[1 1 .95 .75 .28 0]);
    qBranchFlow=xp9_utility(max([rows.negative_branch_flow_violation]), ...
        [0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
    qPumpNegative=xp9_utility(max([rows.negative_pump_flow_violation]), ...
        [0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
    qValveBound=xp9_utility(max([rows.valve_bound_violation]), ...
        [0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
    qRatedEnvelope=xp9_group([qSupplyUpper qSupplyNegative qBranchPressure ...
        qBranchFlow qPumpNegative qValveBound],ones(1,6),true);
    qHydraulic=xp9_group([qCont qOpening qTorque qPower qRate qPump qZero qRatedEnvelope ...
        double(suite.hydraulic_coefficients_physical) double(suite.opening_flow_positive) ...
        double(suite.pressure_torque_positive)],ones(1,19),true);

    qMechanical=xp9_group([qMech double(suite.mechanical_coefficients_physical)],[1 1 1 1],true);
    qLeakPassive=xp9_utility(suite.leak_passivity_violation,[0 .001 .004 .015 .06 .25],[1 1 .95 .75 .28 0]);
    qLeakMonotonic=xp9_utility(suite.leak_monotonic_violation,[0 .001 .01 .06 .22 .60],[1 1 .95 .75 .28 0]);
    qDeadband=xp9_utility(suite.deadband_effect_strength,[0 .0005 .0015 .004 .012 .04],[0 .28 .62 .88 1 1]);
    if suite.deadband_compensation_credit,qDeadband=1;end
    qActivity=xp9_utility(n.hydraulic_activity,[0 120 350 900 2200 5000],[0 .25 .60 .88 1 1]);
    qLedger=xp9_group([qLeakPassive qLeakMonotonic qDeadband qActivity], [.26 .24 .22 .28],true);
    out.M=xp9_group([qHydraulic qMechanical qLedger],[.48 .28 .24],true);
    if ~suite.core_hydraulic_path,out.M=0;end
else
    out.A=0;out.Q=0;out.M=0;
end

rq=ones(numel(rows),1);dq=ones(numel(rows),1);
for i=1:numel(rows)
    r=rows(i);
    qeAxis=zeros(1,3);qvAxis=zeros(1,3);
    for k=1:3
        qeAxis(k)=xp9_utility(r.angle_error_by_axis(k),[0 .20 .50 1.2 3.0 7.0],[1 1 .93 .70 .25 0]);
        qvAxis(k)=xp9_utility(r.tail_velocity_by_axis(k),[0 .12 .30 .75 2.0 5.0],[1 1 .93 .70 .25 0]);
    end
    qe=xp9_group(qeAxis,ones(1,3),false);
    qv=xp9_group(qvAxis,ones(1,3),false);
    qp=xp9_utility(r.min_pressure_ratio,[0 .45 .60 .72 .82 1.0],[0 .25 .62 .88 1 1]);
    qf=xp9_utility(r.flow_utilization,[0 .68 .86 .96 1.00 1.20],[1 1 .95 .86 .70 0]);
    rq(i)=xp9_group([qe qv qp qf],[.42 .16 .22 .20],true);
    qRec=xp9_utility(r.recovery_time,[0 .20 .55 1.1 2.2 4.0],[1 1 .93 .70 .25 0]);
    % Only positive, passive and monotone leakage evidence is required;
    % the scorer does not assume an exact linear conductance law.
    qLeak=xp9_utility(r.leak_conductance_gain-1,[0 .03 .10 .28 .65 1.20],[0 .30 .65 .90 1 1]);
    qComp=xp9_utility(r.event_compensation,[0 .001 .004 .012 .04 .12],[0 .30 .65 .90 1 1]);
    qMotion=xp9_utility(r.event_motion_response,[0 .0005 .002 .007 .025 .08],[0 .30 .65 .90 1 1]);
    qResponse=max(qComp,qMotion);
    dq(i)=xp9_group([qRec qLeak qResponse],[.45 .30 .25],true);
end
if isempty(rq),out.R=0;out.D=0;else
    out.R=xp9_tail(rq,ones(size(rq)));
    out.D=xp9_tail(dq,ones(size(dq)));
end
if ~suite.core_leak_event,out.D=0;end
out.utility_metrics=struct('nominal_accuracy',out.A,'nominal_quality',out.Q, ...
    'mechanism',out.M,'worst_range',out.R,'worst_dynamic',out.D);
out.raw_metrics=rows;w=spec.groups.weights;
out.score=xp9_total(out.G,[out.A out.Q out.M out.R out.D],[w.A w.Q w.M w.R w.D]);
end

function tf=core_hydraulic_path_present(s,rows)
% Existence gate only: at least one non-degenerate measured pressure-flow-
% torque-motion branch plus shared-pump activity.  Coefficient signs and
% all equation-fit residuals remain continuous M-quality evidence.
branch=logical(s.branch_activity_present);
flowActivity=max([rows.flow_utilization]);
tf=any(branch)&&isfinite(flowActivity)&&flowActivity>1e-8;
end

function tf=core_leak_event_present(s,rows)
% The public reach-cylinder intervention must cause a measured leakage-flow
% change above numerical noise.  Gain, monotonicity and recovery quality
% remain continuous D/M evidence.
change=[rows.event_leak_flow_change];
tf=logical(numel(s.branch_activity_present)>=2&&s.branch_activity_present(2)&& ...
    any(isfinite(change)&change>1e-12));
end

function r=measure_run(run)
r=empty_row();r.scenario=string(run.scenario);
if string(run.stage)~="simulated",return;end
[t,j,okJ]=xp9_series(run,'joint_state',6);
[t2,p,okP]=xp9_series(run,'hydraulic_pressure',4);
[t3,f,okF]=xp9_series(run,'hydraulic_flow',10);
[t4,a,okA]=xp9_series(run,'actuation',6);
if ~(okJ&&okP&&okF&&okA&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
supply=double(run.inputs.supply_pressure);capacity=double(run.inputs.pump_flow_capacity);
% xp9_series already enforces finite, well-shaped Timeseries data.  Retain
% only a broad numerical-explosion guard here; every finite rated-envelope,
% sign or capacity error is continuous performance evidence below.
gross=any(abs(j)>1e7,'all')||any(abs(p)>1e10,'all')|| ...
    any(abs(f)>10,'all')||any(abs(a)>1e10,'all');
if gross,return;end
r.supply_pressure_upper_violation=max(max(p(:,1)-supply,0))/max(supply,1);
r.negative_supply_pressure_violation=max(max(-p(:,1),0))/max(supply,1);
r.branch_pressure_envelope_violation=max(max(abs(p(:,2:4))-max(p(:,1),0),0),[],'all')/max(supply,1);
r.negative_branch_flow_violation=max(max(-f(:,1:3),0),[],'all')/max(capacity,1e-9);
r.negative_pump_flow_violation=max(max(-f(:,10),0))/max(capacity,1e-9);
r.pump_capacity_exceedance=max(max(f(:,10)-capacity,0))/max(capacity,1e-9);
r.valve_bound_violation=max(max(abs(a(:,1:3))-1,0),[],'all');
event=double(run.inputs.leak_event_time);eventEnd=event+1.2;
tail=t>=max(eventEnd+1.2,t(end)-1.5);pre=t>=event-.7&t<=event-.12;evt=t>=event+.08&t<=eventEnd-.08;
fit=t>.20&t<t(end)-.02;
if nnz(tail)<100||nnz(pre)<100||nnz(evt)<100||nnz(fit)<200,return;end
ref=[double(run.inputs.lift_reference),double(run.inputs.reach_reference),double(run.inputs.bucket_reference)];
err=abs(j(:,1:3)-ref);r.angle_error_by_axis=median(err(tail,:),1);
r.tail_velocity_by_axis=rms(j(tail,4:6),1);
r.max_angle_error=max(r.angle_error_by_axis);
r.tail_velocity=max(r.tail_velocity_by_axis);
r.pump_ripple=std(p(tail,1))/max(mean(p(tail,1)),1e5);
r.valve_ripple_by_axis=std(a(tail,1:3),1);
r.valve_ripple=max(r.valve_ripple_by_axis);
r.flow_utilization=max(f(:,10))/max(capacity,1e-6);
r.min_pressure_ratio=min(p(:,1))/max(supply,1e5);
r.pump_flow_residual=rms(f(:,10)-sum(f(:,1:3),2))/max(rms(f(:,10)),1e-6);
r.hydraulic_activity=local_quantile(sum(abs(p(:,2:4).*f(:,1:3)),2),.80);

dAngle=[backward_rate(j(:,1),t),backward_rate(j(:,2),t),backward_rate(j(:,3),t)];
r.state_rate_residual=rms(dAngle(fit,:)-j(fit,4:6),'all')/max(rms(j(fit,4:6),'all'),.25);
closedEffective=abs(a(:,1:3))<=5e-4;
db=double(run.inputs.valve_deadband);
effectiveFromRaw=max(abs(a(:,1:3))-db,0)/max(1-db,eps);
closedRaw=effectiveFromRaw<=5e-4;
z1=sum(f(closedEffective(:,1),1))+sum(f(closedEffective(:,2),2))+sum(f(closedEffective(:,3),3));
z2=sum(f(closedRaw(:,1),1))+sum(f(closedRaw(:,2),2))+sum(f(closedRaw(:,3),3));
r.zero_valve_flow_ratio=min(z1,z2)/max(sum(f(:,1:3),'all'),1e-9);

preConduct=median(abs(f(pre,8))./max(abs(p(pre,3)),1e5));
evtConduct=median(abs(f(evt,8))./max(abs(p(evt,3)),1e5));
r.leak_conductance_gain=evtConduct/max(preConduct,1e-14);
r.event_leak_flow_change=abs(median(f(evt,8))-median(f(pre,8)));
leakPower=p(:,2:4).*f(:,7:9);
v1=sum(max(-leakPower,0),'all')/max(sum(abs(leakPower),'all'),1e-8);
v2=sum(max(leakPower,0),'all')/max(sum(abs(leakPower),'all'),1e-8);
r.leak_passivity_violation=min(v1,v2); % diagnostic; suite fixes orientations
qShift=abs(median(f(evt,2))-median(f(pre,2)))/max(capacity,1e-6);
valveShift=abs(median(a(evt,2))-median(a(pre,2)));
pressureShift=abs(median(p(evt,3))-median(p(pre,3)))/max(supply,1e5);
r.event_compensation=max([qShift valveShift pressureShift]);
velocityShift=abs(median(j(evt,5))-median(j(pre,5)))/30;
errorShift=abs(median(err(evt,2))-median(err(pre,2)))/5;
r.event_motion_response=max(velocityShift,errorShift);
preBaseline=median(max(err(pre,:),[],2));
r.recovery_time=local_recovery(t,max(err,[],2),eventEnd,max(.8,preBaseline+.25));
r.valid=all(isfinite([r.max_angle_error r.tail_velocity r.pump_ripple r.valve_ripple ...
    r.flow_utilization r.min_pressure_ratio r.pump_flow_residual r.hydraulic_activity ...
    r.supply_pressure_upper_violation r.negative_supply_pressure_violation ...
    r.branch_pressure_envelope_violation r.negative_branch_flow_violation ...
    r.negative_pump_flow_violation r.pump_capacity_exceedance r.valve_bound_violation ...
    r.state_rate_residual r.zero_valve_flow_ratio r.leak_conductance_gain ...
    r.event_leak_flow_change ...
    r.leak_passivity_violation r.event_compensation r.event_motion_response])) ...
    &&~isnan(r.recovery_time);
end

function s=measure_suite(runs,rows)
s=empty_suite();Dp=cell(1,3);Branch=cell(1,3);Opening=cell(1,3);
Piston=cell(1,3);Leak=cell(1,3);Pressure=cell(1,3);Torque=cell(1,3);
Rate=cell(1,3);Angle=cell(1,3);Head=cell(1,3);Deadband=cell(1,3);
    FutureBranch=cell(1,3);CurrentBranch=cell(1,3);Xm=cell(1,3);Ym=cell(1,3);Payload=cell(1,3);
for i=1:numel(runs)
    run=runs(i);if string(run.stage)~="simulated",return;end
    [t,j,okJ]=xp9_series(run,'joint_state',6);
    [t2,p,okP]=xp9_series(run,'hydraulic_pressure',4);
    [t3,f,okF]=xp9_series(run,'hydraulic_flow',10);
    [t4,a,okA]=xp9_series(run,'actuation',6);
    if ~(okJ&&okP&&okF&&okA&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
    fit=t>.25&t<t(end)-.02;bulk=double(run.inputs.fluid_bulk_modulus);
    dp=[backward_rate(p(:,2),t),backward_rate(p(:,3),t),backward_rate(p(:,4),t)];
    qrad=j(:,1:3)*pi/180;wrad=j(:,4:6)*pi/180;
    acc=[backward_rate(wrad(:,1),t),backward_rate(wrad(:,2),t),backward_rate(wrad(:,3),t)];
    payload=double(run.inputs.payload_mass);
    idx=find(fit);idx=idx(idx<numel(t));
    for k=1:3
        Dp{k}=[Dp{k};dp(fit,k)/bulk];
        Branch{k}=[Branch{k};f(fit,k)];
        Opening{k}=[Opening{k};a(fit,k)];
        Piston{k}=[Piston{k};f(fit,k+3)];
        Leak{k}=[Leak{k};f(fit,k+6)];
        Pressure{k}=[Pressure{k};p(fit,k+1)];
        Torque{k}=[Torque{k};a(fit,k+3)];
        Rate{k}=[Rate{k};wrad(fit,k)];
        Angle{k}=[Angle{k};qrad(fit,k)];
        Head{k}=[Head{k};max(p(idx,1)-abs(p(idx,k+1)),2e5)/1e6];
        Deadband{k}=[Deadband{k};double(run.inputs.valve_deadband)*ones(numel(idx),1)];
        FutureBranch{k}=[FutureBranch{k};f(idx+1,k)];
        CurrentBranch{k}=[CurrentBranch{k};f(idx,k)];
        other=setdiff(1:3,k,'stable');
        ownQ=qrad(fit,k);ownW=wrad(fit,k);
        qOther=qrad(fit,other);wOther=wrad(fit,other);
        % Candidate-neutral mechanical basis.  Columns 1:3 and 4:6 are a
        % full coupled inertia matrix and its optional payload dependence.
        % The remaining columns are optional nuisance load families; no
        % golden gravity, Coriolis, coupling or friction family is mandatory.
        Xm{k}=[Xm{k};acc(fit,:),payload*acc(fit,:), ...
            sin(ownQ),cos(ownQ),ownQ,ownW,sign(ownW),ownW.*abs(ownW), ...
            payload*sin(ownQ),payload*cos(ownQ),payload*ownQ, ...
            sin(qOther(:,1)-ownQ),cos(qOther(:,1)-ownQ), ...
            sin(qOther(:,2)-ownQ),cos(qOther(:,2)-ownQ), ...
            wOther(:,1),wOther(:,2),ownW.*wOther(:,1), ...
            ownW.*wOther(:,2),wOther(:,1).*wOther(:,2), ...
            wOther(:,1).^2,wOther(:,2).^2,ones(nnz(fit),1)];
        Ym{k}=[Ym{k};a(fit,k+3)];
        Payload{k}=[Payload{k};payload*ones(nnz(fit),1)];
    end
end
s.continuity_residual=zeros(1,3);s.continuity_coefficients=zeros(1,3);
s.continuity_signs=zeros(3,4);s.opening_flow_residual=zeros(1,3);
s.opening_flow_coefficients=zeros(1,3);s.opening_head_exponent=zeros(1,3);
s.pressure_torque_residual=zeros(1,3);s.pressure_torque_coefficients=cell(1,3);
s.torque_sign=zeros(1,3);s.hydraulic_power_residual=zeros(1,3);
s.mechanical_residual=zeros(1,3);s.mechanical_coefficients=cell(1,3);
s.leak_passivity_by_branch=zeros(1,3);
s.hydraulic_branch_present=false(1,3);s.mechanical_branch_present=false(1,3);
s.pressure_activity_by_axis=zeros(1,3);s.flow_activity_by_axis=zeros(1,3);
s.torque_activity_by_axis=zeros(1,3);s.motion_activity_by_axis=zeros(1,3);
s.branch_activity_present=false(1,3);
hydraulicOK=true;torqueOK=true;mechanicalOK=true;
for k=1:3
    [rc,bc,signs,rt,bt,tauSign,rp,rm,bm,leakV,okBranch,mechBranchOK]=oriented_branch( ...
        Dp{k},Branch{k},Opening{k},Piston{k},Leak{k},Pressure{k}, ...
        Angle{k},Torque{k},Rate{k},Xm{k},Ym{k});
    s.continuity_residual(k)=rc;s.continuity_coefficients(k)=bc;
    s.continuity_signs(k,:)=signs;s.pressure_torque_residual(k)=rt;
    s.pressure_torque_coefficients{k}=bt(:)';s.torque_sign(k)=tauSign;
    s.hydraulic_power_residual(k)=rp;s.mechanical_residual(k)=rm;
    s.mechanical_coefficients{k}=bm(:)';s.leak_passivity_by_branch(k)=leakV;
    s.hydraulic_branch_present(k)=okBranch&&bc>0;
    s.mechanical_branch_present(k)=mechBranchOK;
    s.pressure_activity_by_axis(k)=local_quantile(abs(Pressure{k}),.80);
    s.flow_activity_by_axis(k)=local_quantile(abs(Branch{k}),.80);
    s.torque_activity_by_axis(k)=local_quantile(abs(Torque{k}),.80);
    s.motion_activity_by_axis(k)=local_quantile(abs(Rate{k}),.80);
    s.branch_activity_present(k)=s.pressure_activity_by_axis(k)>1&& ...
        s.flow_activity_by_axis(k)>1e-10&&s.torque_activity_by_axis(k)>1e-8&& ...
        s.motion_activity_by_axis(k)>1e-10;
    hydraulicOK=hydraulicOK&&okBranch&&bc>0;
    torqueOK=torqueOK&&okBranch;mechanicalOK=mechanicalOK&&mechBranchOK;
end

% Choose one logged valve representation for the whole task: either the
% effective post-deadband opening, or a raw spool position transformed by
% the public deadband.  Within either representation, pressure-compensated,
% square-root and linear head dependences are legal held-out candidates.
[s.opening_representation,s.opening_flow_residual,s.opening_flow_coefficients, ...
    s.opening_head_exponent,s.opening_flow_positive]=opening_candidates( ...
    Opening,Head,Deadband,FutureBranch);
s.zero_valve_flow_ratio=closed_valve_ratio(Opening,Deadband,CurrentBranch,s.opening_representation);

s.leak_passivity_violation=max(s.leak_passivity_by_branch);
s.hydraulic_coefficients_physical=hydraulicOK;
s.pressure_torque_positive=torqueOK;
payloadRange=[min(Payload{1}),max(Payload{1})];
s.mechanical_coefficients_physical=mechanicalOK&& ...
    coupled_inertia_physical(s.mechanical_coefficients,payloadRange);
s.state_rate_residual=max([rows.state_rate_residual]);
s.leak_monotonic_violation=monotonic_violation(runs,rows);
[s.deadband_valid,s.deadband_effect_strength,s.deadband_opening_difference, ...
    s.deadband_flow_difference,s.deadband_pair_performance_good]=deadband_pair(runs,rows);
closureGood=max(s.continuity_residual)<=.13&&max(s.opening_flow_residual)<=.17&& ...
    max(s.pressure_torque_residual)<=.13&&max(s.hydraulic_power_residual)<=.12&& ...
    max(s.mechanical_residual)<=.17&&s.state_rate_residual<=.05&& ...
    max([rows.pump_flow_residual])<=.05&&hydraulicOK&&torqueOK&&mechanicalOK;
s.deadband_compensation_credit=s.opening_representation=="effective_opening"&& ...
    s.deadband_effect_strength<=1e-3&&s.deadband_pair_performance_good&&closureGood;
s.valid=s.deadband_valid&&all(isfinite([s.continuity_residual s.continuity_signs(:)' ...
    s.opening_flow_residual s.opening_flow_coefficients s.opening_head_exponent ...
    s.pressure_torque_residual s.torque_sign s.hydraulic_power_residual ...
    s.mechanical_residual s.zero_valve_flow_ratio s.leak_passivity_by_branch ...
    s.leak_passivity_violation ...
    s.pressure_activity_by_axis s.flow_activity_by_axis ...
    s.torque_activity_by_axis s.motion_activity_by_axis ...
    s.state_rate_residual s.leak_monotonic_violation s.deadband_effect_strength ...
    s.deadband_opening_difference s.deadband_flow_difference]));
end

function [contRes,contCoeff,signs,torqueRes,torqueCoeff,tauSign, ...
    powerRes,mechRes,mechCoeff,leakViolation,ok,mechOK]=oriented_branch( ...
    dp,branch,opening,piston,leak,pressure,angle,torque,rate,Xm,Ym)
contRes=1;contCoeff=NaN;signs=nan(1,4);torqueRes=1;
torqueCoeff=nan(3,1);tauSign=NaN;powerRes=1;mechRes=1;
mechCoeff=nan(size(Xm,2),1);leakViolation=1;ok=false;mechOK=false;best=Inf;
for sP=[-1 1]
    for sValve=[-1 1]
        for sPiston=[-1 1]
            for sLeak=[-1 1]
                qnet=sValve*sign(opening).*branch-sPiston*piston-sLeak*leak;
                [rc,bc,contOK]=fit_model(qnet,sP*dp,1e-8);
                if ~(contOK&&bc(1)>0),continue;end
                p=sP*pressure;X=[p,p.*sin(angle),p.*cos(angle)];
                lp=p.*(sLeak*leak);
                leakV=sum(max(-lp,0))/max(sum(abs(lp)),1e-8);
                for candidateTau=[-1 1]
                    [rt,bt,torqueOK]=heldout_fit(X,candidateTau*torque,50);
                    if ~torqueOK,continue;end
                    predicted=X*bt;gain=predicted.*p./max(p.^2,1e10);
                    if local_quantile(gain,.01)<=0,continue;end
                    pPower=p.*(sPiston*piston);
                    mPower=(candidateTau*torque).*rate;
                    rp=rms(pPower-mPower)/max(rms([pPower;mPower]),25);
                    [rm,bm,mechFitOK]=mechanical_candidates(Xm,candidateTau*Ym,50);
                    objective=rc+rt+rp+rm+leakV+10*double(~mechFitOK);
                    if objective<best
                        best=objective;contRes=rc;contCoeff=bc(1);
                        signs=[sP sValve sPiston sLeak];torqueRes=rt;
                        torqueCoeff=bt;tauSign=candidateTau;powerRes=rp;
                        mechRes=rm;mechCoeff=bm;leakViolation=leakV;
                        ok=true;mechOK=mechFitOK;
                    end
                end
            end
        end
    end
end
end

function [bestRes,bestCoeff,ok]=mechanical_candidates(X,y,floorValue)
% Fit torque = positive effective inertia * acceleration + an optional
% articulated-load family.  Choosing the best held-out candidate avoids
% prescribing one golden gravity, coupling, or friction equation.  Every
% candidate retains all three acceleration columns.  Physical positivity
% is checked jointly across the three fitted rows after sign inference.
sets={ ...
    [1:3 27], ...
    [1:6 27], ...
    [1:6 7 8 10 27], ...
    [1:6 7:12 27], ...
    [1:6 7 8 10 13 14 16:21 27], ...
    [1:6 7:27]};
bestRes=1;bestCoeff=nan(size(X,2),1);ok=false;bestObjective=Inf;
for i=1:numel(sets)
    cols=sets{i};[res,b,fitOK]=heldout_fit(X(:,cols),y,floorValue);
    if ~fitOK,continue;end
    objective=res+2e-4*numel(cols);
    if objective<bestObjective
        bestObjective=objective;bestRes=res;bestCoeff(:)=NaN;
        bestCoeff(cols)=b;ok=true;
    end
end
end

function ok=coupled_inertia_physical(coefficients,payloadRange)
% Generalized joint torques and logged joint coordinates must imply one
% positive-definite coupled inertia matrix throughout the observed payload
% range.  Mild regression asymmetry is tolerated, but an active/negative
% inertia or independently signed per-axis fit is not.
M0=zeros(3);Mp=zeros(3);
for k=1:3
    b=coefficients{k};
    if numel(b)<6||any(~isfinite(b(1:3))),ok=false;return;end
    M0(k,:)=b(1:3);
    bp=b(4:6);bp(~isfinite(bp))=0;Mp(k,:)=bp;
end
ok=true;
for p=[payloadRange(1),mean(payloadRange),payloadRange(2)]
    M=M0+p*Mp;S=(M+M')/2;
    asymmetry=norm(M-M','fro')/max(norm(S,'fro'),eps);
    ev=eig(S);scale=max(max(abs(ev)),1);
    ok=ok&&all(isfinite(ev))&&min(ev)>1e-7*scale&&asymmetry<.40;
end
end

function [representation,res,coeff,exponent,ok]=opening_candidates(opening,head,deadband,future)
representation="";res=ones(1,3);coeff=nan(1,3);exponent=nan(1,3);ok=false;best=Inf;
for rep=1:2
    rr=ones(1,3);bb=nan(1,3);aa=nan(1,3);allOK=true;
    for k=1:3
        if rep==1
            effective=abs(opening{k});
        else
            effective=max(abs(opening{k})-deadband{k},0)./max(1-deadband{k},eps);
        end
        localBest=Inf;
        for alpha=[0 .5 1]
            predictor=effective.*head{k}.^alpha;
            [candidate,bc,fitOK]=heldout_positive_fit(predictor,future{k},1e-7);
            if fitOK&&candidate<localBest
                localBest=candidate;rr(k)=candidate;bb(k)=bc;aa(k)=alpha;
            end
        end
        allOK=allOK&&isfinite(localBest);
    end
    objective=sum(rr)+3*double(~allOK);
    if objective<best
        best=objective;res=rr;coeff=bb;exponent=aa;ok=allOK;
        if rep==1,representation="effective_opening";else,representation="raw_spool";end
    end
end
end

function ratio=closed_valve_ratio(opening,deadband,branch,representation)
closedFlow=0;totalFlow=0;
for k=1:3
    if representation=="raw_spool"
        effective=max(abs(opening{k})-deadband{k},0)./max(1-deadband{k},eps);
    else
        effective=abs(opening{k});
    end
    closedFlow=closedFlow+sum(branch{k}(effective<=5e-4));
    totalFlow=totalFlow+sum(branch{k});
end
ratio=closedFlow/max(totalFlow,1e-9);
end

function v=monotonic_violation(runs,rows)
mult=zeros(numel(runs),1);gain=zeros(numel(runs),1);
for i=1:numel(runs),mult(i)=double(runs(i).inputs.leakage_multiplier);gain(i)=rows(i).leak_conductance_gain;end
bad=0;total=0;
for i=1:numel(mult)
    for j=i+1:numel(mult)
        if abs(mult(i)-mult(j))<.08,continue;end
        total=total+abs(mult(i)-mult(j));
        if (gain(i)-gain(j))*(mult(i)-mult(j))<=0,bad=bad+abs(mult(i)-mult(j));end
    end
end
v=bad/max(total,eps);
end

function [valid,effect,openingDiff,flowDiff,performanceGood]=deadband_pair(runs,rows)
valid=false;effect=NaN;openingDiff=NaN;flowDiff=NaN;performanceGood=false;
names=string({runs.scenario});iLo=find(names=="deadband_probe_low",1);iHi=find(names=="deadband_probe_high",1);
if isempty(iLo)||isempty(iHi),return;end
[tL,fL,ok1]=xp9_series(runs(iLo),'hydraulic_flow',10);[tH,fH,ok2]=xp9_series(runs(iHi),'hydraulic_flow',10);
[t2,aL,ok3]=xp9_series(runs(iLo),'actuation',6);[t3,aH,ok4]=xp9_series(runs(iHi),'actuation',6);
if ~(ok1&&ok2&&ok3&&ok4&&isequal(tL,tH)&&isequal(tL,t2)&&isequal(tL,t3)),return;end
event=min(double(runs(iLo).inputs.leak_event_time),double(runs(iHi).inputs.leak_event_time));fit=tL>.25&tL<event-.1;
if nnz(fit)<100,return;end
capacity=double(runs(iLo).inputs.pump_flow_capacity);
openingDiff=rms(aL(fit,1:3)-aH(fit,1:3),'all');
flowDiff=rms(fL(fit,1:3)-fH(fit,1:3),'all')/max(capacity,1e-6);
performanceGood=rows(iLo).valid&&rows(iHi).valid&& ...
    max(rows(iLo).max_angle_error,rows(iHi).max_angle_error)<=1.2&& ...
    max(rows(iLo).tail_velocity,rows(iHi).tail_velocity)<=.75&& ...
    max(rows(iLo).pump_flow_residual,rows(iHi).pump_flow_residual)<=.05;
effect=max(openingDiff,flowDiff);valid=all(isfinite([effect openingDiff flowDiff]));
end

function [res,b,ok]=heldout_positive_fit(x,y,floorValue)
res=1;b=NaN;ok=false;good=isfinite(x)&isfinite(y)&x>=0&y>=0;x=x(good);y=y(good);
if numel(x)<100||rms(x)<1e-8||rms(y)<1e-10,return;end
test=mod((1:numel(x))',5)==0;train=~test;
b=max((x(train)'*y(train))/max(x(train)'*x(train),eps),0);
res=rms(y(test)-x(test)*b)/max(rms(y(test)),floorValue);ok=isfinite(b)&&isfinite(res)&&b>0;
end

function [res,b,ok]=heldout_fit(X,y,floorValue)
res=1;b=nan(size(X,2),1);ok=false;good=all(isfinite(X),2)&isfinite(y);X=X(good,:);y=y(good);
if size(X,1)<max(100,12*size(X,2))||rank(X)<size(X,2),return;end
test=mod((1:size(X,1))',5)==0;train=~test;
if rank(X(train,:))<size(X,2),return;end
b=X(train,:)\y(train);res=rms(y(test)-X(test,:)*b)/max(rms(y(test)),floorValue);
ok=all(isfinite(b))&&isfinite(res);
end

function [res,b,ok]=fit_model(X,y,floorValue)
res=1;b=nan(size(X,2),1);ok=false;
good=all(isfinite(X),2)&isfinite(y);X=X(good,:);y=y(good);
if size(X,1)<max(20,5*size(X,2))||rank(X)<size(X,2)||rms(y)<1e-12,return;end
b=X\y;res=rms(y-X*b)/max(rms(y),floorValue);ok=all(isfinite(b))&&isfinite(res);
end
function dx=backward_rate(x,t)
dx=zeros(size(x));dx(2:end)=diff(x)./diff(t);dx(1)=dx(2);
end
function q=local_quantile(x,p)
x=sort(double(x(:)));n=numel(x);q=x(max(1,min(n,ceil(p*n))));
end
function dt=local_recovery(t,e,eventEnd,tolerance)
dt=Inf;start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(.30/median(diff(t))));good=e<=tolerance;
for k=start:max(start,numel(t)-window+1)
    if k+window-1<=numel(t)&&all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
end
function r=empty_row()
r=struct('scenario',"",'valid',false,'max_angle_error',NaN, ...
    'angle_error_by_axis',nan(1,3),'tail_velocity',NaN, ...
    'tail_velocity_by_axis',nan(1,3),'pump_ripple',NaN,'valve_ripple',NaN, ...
    'valve_ripple_by_axis',nan(1,3),'flow_utilization',NaN, ...
    'min_pressure_ratio',NaN,'pump_flow_residual',NaN,'hydraulic_activity',NaN, ...
    'supply_pressure_upper_violation',NaN,'negative_supply_pressure_violation',NaN, ...
    'branch_pressure_envelope_violation',NaN,'negative_branch_flow_violation',NaN, ...
    'negative_pump_flow_violation',NaN,'pump_capacity_exceedance',NaN, ...
    'valve_bound_violation',NaN, ...
    'state_rate_residual',NaN,'zero_valve_flow_ratio',NaN, ...
    'leak_conductance_gain',NaN,'event_leak_flow_change',NaN, ...
    'leak_passivity_violation',NaN, ...
    'event_compensation',NaN,'event_motion_response',NaN,'recovery_time',NaN);
end
function s=empty_suite()
s=struct('valid',false,'continuity_residual',ones(1,3), ...
    'continuity_coefficients',nan(1,3),'continuity_signs',nan(3,4), ...
    'opening_representation',"",'opening_flow_residual',ones(1,3), ...
    'opening_flow_coefficients',nan(1,3),'opening_head_exponent',nan(1,3), ...
    'opening_flow_positive',false,'zero_valve_flow_ratio',NaN, ...
    'pressure_torque_residual',ones(1,3),'pressure_torque_coefficients',{cell(1,3)}, ...
    'torque_sign',nan(1,3),'pressure_torque_positive',false, ...
    'hydraulic_power_residual',ones(1,3), ...
    'hydraulic_coefficients_physical',false,'mechanical_residual',ones(1,3), ...
    'mechanical_coefficients',{cell(1,3)},'mechanical_coefficients_physical',false, ...
    'hydraulic_branch_present',false(1,3),'mechanical_branch_present',false(1,3), ...
    'pressure_activity_by_axis',zeros(1,3),'flow_activity_by_axis',zeros(1,3), ...
    'torque_activity_by_axis',zeros(1,3),'motion_activity_by_axis',zeros(1,3), ...
    'branch_activity_present',false(1,3), ...
    'leak_passivity_by_branch',ones(1,3),'leak_passivity_violation',1, ...
    'state_rate_residual',1,'leak_monotonic_violation',1, ...
    'deadband_valid',false,'deadband_effect_strength',NaN, ...
    'deadband_opening_difference',NaN,'deadband_flow_difference',NaN, ...
    'deadband_pair_performance_good',false,'deadband_compensation_credit',false, ...
    'core_hydraulic_path',false,'core_leak_event',false);
end
function out=empty_out()
out=struct('schema',"simuverity.xp9-score.v1",'policy_id',"simuverity-101-v1:p9-xfluid01:scoring", ...
    'formula',"G*100*A^.20*Q^.10*M^.30*R^.20*D^.20", ...
    'score_inputs_valid',false,'diagnostics_valid',false,'G',false, ...
    'gate_reasons',strings(0,1),'A',0,'Q',0,'M',0,'R',0,'D',0,'score',0, ...
    'raw_metrics',struct(),'utility_metrics',struct(),'scenario_rows',struct([]), ...
    'suite_metrics',struct(),'diagnostic_scope', ...
    "public nonnegative pump ledger, globally consistent branch-sign inference, raw/effective opening and head-law candidates, positive-inertia mechanical load-family candidates, state/power closure, passive leakage, and representation-aware deadband evidence that accepts fully compensated effective opening");
end
