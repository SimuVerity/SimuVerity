function out=xp9_score_xmed01(runs,spec)
%XP9_SCORE_XMED01 Dedicated ventilator-patient physics and safety score.
out=empty_out();
rows=repmat(empty_row(),numel(runs),1);allValid=true;
for i=1:numel(runs)
    rows(i)=measure_run(runs(i));allValid=allValid&&rows(i).valid;
end
out.score_inputs_valid=allValid&&numel(runs)==1+numel(spec.scenarios);
out.diagnostics_valid=allValid;out.G=out.score_inputs_valid;
if ~out.G,out.gate_reasons="SCENARIO_OR_OUTPUT_CONTRACT_INVALID";end
out.scenario_rows=rows;
[causalError,causalFit]=future_valve_causality(runs);
leakEvidence=shared_leak_evidence(rows);
airwayEvidence=shared_airway_evidence(runs);
alignedActuatorMargin=NaN;
causalMechanismCap=NaN;

if ~isempty(rows)
    nom=rows(1);
    qP=xp9_utility(nom.plateau_error,[0 .35 .75 1.5 4 8],[1 1 .92 .72 .25 0]);
    qPeep=xp9_utility(nom.peep_error,[0 .2 .5 1 2.5 5],[1 1 .93 .75 .30 0]);
    out.A=xp9_group([qP qPeep],[.65 .35],true);
    if ~nom.breath_cycle_present
        % A flat finite trace is evaluable, but it implements none of the
        % requested pressure-controlled breath cycle.
        out.A=0;
    end

    qTv=xp9_utility(nom.tidal_volume_ratio_error,[0 .04 .10 .22 .45 .90], ...
        [1 1 .94 .72 .25 0]);
    qRipple=xp9_utility(nom.plateau_std,[0 .25 .6 1.5 4],[1 1 .92 .65 0]);
    qSafe=ceiling_utility(nom.max_pressure);
    % Lung-volume non-negativity is a range-wide physical requirement, not
    % merely a nominal-case quality check.
    qVolumeFloor=xp9_utility(max([rows.negative_volume_ratio]),[0 .005 .015 .04 .10 .25], ...
        [1 .99 .94 .72 .25 0]);
    out.Q=xp9_group([qTv qRipple qSafe qVolumeFloor],[.30 .18 .42 .10],false);

    qMass=xp9_utility(nom.mass_residual,[0 .015 .04 .10 .30],[1 1 .9 .55 0]);
    qCircuit=xp9_utility(max([rows.circuit_flow_residual]), ...
        [0 .003 .012 .04 .14 .45],[1 1 .94 .72 .25 0]);
    qAlv=xp9_utility(nom.alveolar_residual,[0 .002 .01 .04 .15 .50],[1 1 .94 .72 .25 0]);
    qAirway=xp9_utility(airwayEvidence.error,[0 .004 .015 .05 .18 .55],[1 1 .94 .72 .25 0]);
    qPhysiology=xp9_group([qMass qCircuit qAlv qAirway],[.24 .28 .22 .26],false);

    alignedActuatorMargin=aligned_actuator_role_margin(runs(1),causalFit.selected_delay_seconds);
    qAct=xp9_utility(alignedActuatorMargin,[-.3 0 .15 .35 .7],[0 .25 .65 1 1]);
    qAlarm=xp9_utility(max([rows.alarm_strategy_error]), ...
        [0 .03 .09 .20 .42 .80],[1 1 .94 .72 .25 0]);
    qLeak=xp9_utility(leakEvidence.error,[0 .025 .07 .16 .36 .75],[1 1 .94 .72 .25 0]);
    qCausal=xp9_utility(causalError,[0 .22 .40 .65 1.0 1.5],[1 1 .94 .72 .25 0]);
    qCycle=xp9_utility(max([[rows.cycle_period_error],[rows.ie_ratio_error]]), ...
        [0 .015 .04 .10 .25 .60],[1 1 .94 .72 .25 0]);
    qDevice=xp9_group([qAct qAlarm qLeak qCausal qCycle],[.16 .18 .22 .27 .17],false);
    out.M=xp9_group([qPhysiology qDevice],[.48 .52],false);
    % This cap represents completion of the public core causal chain
    % actuator -> delivered flow -> patient state.  A reported actuator
    % channel with no prospective physical influence is not a cosmetic
    % submetric.  Retain valid-low partial credit for the remaining
    % physiology instead of zeroing the whole M group.  A single legal leak
    % representation failure deliberately does not trigger this cap.
    causalMechanismCap=.25+.75*qCausal;
    out.M=min(out.M,causalMechanismCap);
    if ~nom.breath_cycle_present
        % Preserve any genuine mass-balance or passive-lung evidence, but
        % do not let it stand in for the missing cyclic ventilator chain.
        out.M=min(out.M,.25);
    end
    if qPhysiology<=0&&qDevice<=0
        out.M=0;
    end
else
    out.A=0;out.Q=0;out.M=0;
end

rq=zeros(numel(rows),1);dq=zeros(numel(rows),1);
for i=1:numel(rows)
    r=rows(i);
    if ~r.breath_cycle_present
        rq(i)=0;dq(i)=0;
        continue
    end
    qp=xp9_utility(r.plateau_error,[0 .5 1 2.5 6 10],[1 1 .9 .65 .2 0]);
    qpe=xp9_utility(r.peep_error,[0 .3 .7 1.5 3.5 6],[1 1 .9 .7 .25 0]);
    qtv=xp9_utility(r.tidal_volume_ratio_error,[0 .06 .14 .30 .58 1.0], ...
        [1 1 .92 .69 .23 0]);
    qsafe=ceiling_utility(r.max_pressure);
    qalarm=xp9_utility(r.alarm_strategy_error,[0 .05 .13 .28 .55 .90], ...
        [1 1 .92 .68 .22 0]);
    rq(i)=xp9_group([qp qpe qtv qsafe qalarm],[.28 .17 .18 .25 .12],true);
    qRecovery=xp9_utility(r.recovery_time,[0 .4 .9 1.8 3.5 6],[1 1 .9 .68 .25 0]);
    qEvent=xp9_utility(r.obstruction_response_deficit,[0 .02 .08 .25 .70 1], ...
        [1 1 .92 .68 .22 0]);
    qResistance=xp9_utility(r.obstruction_ratio_error,[0 .04 .12 .28 .58 1.0], ...
        [1 1 .92 .68 .22 0]);
    dq(i)=xp9_group([qRecovery qEvent qResistance],[.45 .25 .30],true);
end
if isempty(rq),out.R=0;out.D=0;else,out.R=xp9_tail(rq);out.D=xp9_tail(dq);end
maxPressure=max([rows.max_pressure]);ceilingCap=ceiling_utility(maxPressure);
out.utility_metrics=struct('nominal_accuracy',out.A,'nominal_quality',out.Q, ...
    'mechanism',out.M,'future_valve_causality',causalFit, ...
    'causal_mechanism_cap',causalMechanismCap, ...
    'delay_aligned_actuator_role_margin',alignedActuatorMargin, ...
    'shared_leak_path',leakEvidence,'shared_airway_law',airwayEvidence, ...
    'worst_range',out.R, ...
    'worst_dynamic',out.D,'safety_ceiling_utility',ceilingCap);
out.raw_metrics=rows;w=spec.groups.weights;
baseScore=xp9_total(out.G,[out.A out.Q out.M out.R out.D],[w.A w.Q w.M w.R w.D]);
out.score=baseScore;
end

function r=measure_run(run)
r=empty_row();r.scenario=string(run.scenario);
if string(run.stage)~="simulated",return;end
[t,a,okA]=xp9_series(run,'airway',3);
[t2,g,okG]=xp9_series(run,'lung_state',1);
[t3,c,okC]=xp9_series(run,'circuit_flow',2);
[t4,u,okU]=xp9_series(run,'actuator',3);
if ~(okA&&okG&&okC&&okU&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
P=a(:,1);flow=a(:,2);V=a(:,3);Palv=g(:,1);delivered=c(:,1);leakFlow=c(:,2);
uin=u(:,1);uout=u(:,2);alarm=u(:,3);
targetInput=double(run.inputs.target_insp_pressure);
expectedVolumeScale=max(double(run.inputs.patient_compliance)*(targetInput-5),.02);
volumeTolerance=max(.005,.02*expectedVolumeScale);
r.min_lung_volume=min(V);r.volume_numeric_tolerance=volumeTolerance;
r.negative_volume_ratio=max(-r.min_lung_volume,0)/expectedVolumeScale;
% Finite physical errors belong to Q/M/R/D.  G is reserved for an output
% contract failure or a gross numerical explosion.  In particular, the
% negative-volume utility below must remain reachable beyond mere floating
% point undershoot.  The public prompt does not prescribe a normalization
% or engineering unit for the two valve-command channels, so any finite
% command magnitude remains technically evaluable.  Whether those commands
% genuinely actuate the patient path is assessed by M/R/D.  The alarm
% channel is still a public Boolean state and remains binding here.
grossScale=max([max(abs(P))/80,max(abs(flow))/8,max(abs(V))/expectedVolumeScale, ...
    max(abs(Palv))/80,max(abs(delivered))/10,max(abs(leakFlow))/8]);
outsideContract=grossScale>1e4 ...
    ||any(alarm<-.001)||any(alarm>1.001) ...
    ||any(min(abs(alarm),abs(alarm-1))>1e-6);
if outsideContract,return;end

target=double(run.inputs.target_insp_pressure);event=double(run.inputs.obstruction_time);
cycle=detect_breath_cycle(t,P,flow,u(:,1:2),target);
if ~cycle.valid
    r=finite_no_cycle_row(r,t,P,flow,V,Palv,delivered,leakFlow,uin,uout, ...
        targetInput,run.inputs);
    return
end
r.breath_cycle_present=true;
r.cycle_period_error=abs(cycle.period-3)/3;
r.ie_ratio_error=abs(cycle.duty-1/3)/(1/3);
stable=t>max(2*cycle.period,3);relativePhase=mod(t-cycle.phase0,cycle.period)/cycle.period;
plateau=stable&relativePhase>=.55*cycle.duty&relativePhase<=.90*cycle.duty ...
    &~(t>=event-.1&t<=event+1.6);
peepStart=cycle.duty+.62*(1-cycle.duty);peepEnd=cycle.duty+.90*(1-cycle.duty);
peep=stable&relativePhase>=peepStart&relativePhase<=peepEnd ...
    &~(t>=event-.1&t<=event+1.6);
if nnz(plateau)<20||nnz(peep)<20
    r=finite_no_cycle_row(r,t,P,flow,V,Palv,delivered,leakFlow,uin,uout, ...
        targetInput,run.inputs);
    return
end
r.plateau_error=median(abs(P(plateau)-target));r.mean_plateau_pressure=median(P(plateau));
r.peep_error=median(abs(P(peep)-5));r.plateau_std=std(P(plateau));r.max_pressure=max(P);

cycleNumber=floor((t-cycle.phase0)/cycle.period);ids=unique(cycleNumber(stable));tv=[];
for k=1:numel(ids)
    ix=cycleNumber==ids(k)&stable&~(t>=event-.1&t<=event+1.2);
    if nnz(ix)>20,tv(end+1)=max(V(ix))-min(V(ix));end %#ok<AGROW>
end
if isempty(tv)
    r=finite_no_cycle_row(r,t,P,flow,V,Palv,delivered,leakFlow,uin,uout, ...
        targetInput,run.inputs);
    return
end
r.tidal_volume=median(tv);expectedVolume=double(run.inputs.patient_compliance)*(target-5);
r.tidal_volume_ratio_error=abs(r.tidal_volume/max(expectedVolume,.02)-1);

dv=local_derivative(V,t);r.mass_residual=rms(dv-flow)/max(rms(flow),.05);
r.circuit_flow_residual=rms(delivered-flow-leakFlow)/max(rms(delivered),.05);
r.alveolar_residual=rms(Palv(stable)-(5+V(stable)/double(run.inputs.patient_compliance))) / ...
    max(rms(5+V(stable)/double(run.inputs.patient_compliance)),1);
reff=double(run.inputs.airway_resistance)*ones(size(t));
obs=t>=event&t<event+1;reff(obs)=reff(obs)*double(run.inputs.obstruction_factor);
r.airway_residual=rms((P(stable)-Palv(stable))-flow(stable).*reff(stable)) / ...
    max(rms(P(stable)-Palv(stable)),1);
insp=stable&cycle.inspiration;expir=stable&~cycle.inspiration;
r.mean_insp_valve=mean(uin(insp));r.mean_exp_valve=mean(uout(expir));
r.mean_abs_flow=mean(abs(flow(stable)));r.mean_delivered_flow=mean(delivered(stable));
r.mean_abs_delivered_flow=mean(abs(delivered(stable)));
r.mean_leak_flow=mean(leakFlow(stable));r.mean_abs_leak_flow=mean(abs(leakFlow(stable)));
r.leak_conductance=median(leakFlow(stable)./max(P(stable),1));
r.leak_orifice_index=median(leakFlow(stable)./sqrt(max(P(stable),1)));
activeLeak=stable&abs(delivered)>.02&leakFlow>=0;
if any(activeLeak)
    r.leak_flow_fraction_index=median(leakFlow(activeLeak)./abs(delivered(activeLeak)));
else
    r.leak_flow_fraction_index=0;
end
r.actuator_role_margin=.5*((mean(uin(insp))-mean(uin(expir)))+ ...
    (mean(uout(expir))-mean(uout(insp))));
targetTrace=5*ones(size(t));targetTrace(cycle.inspiration)=target;
r.alarm_strategy_error=alarm_strategy_error(t,P,uin,uout,alarm,targetTrace);
r.recovery_time=recovery_time(t,P,targetTrace,event+1.0);
[r.obstruction_response_deficit,r.obstruction_ratio_error]= ...
    obstruction_evidence(t,P,Palv,flow,u(:,1:2),event,cycle.period, ...
    double(run.inputs.obstruction_factor),r.recovery_time);
r.public_leak_fraction=double(run.inputs.leak_fraction);
r.valid=finite_row_metrics(r);
end

function r=finite_no_cycle_row(r,t,P,flow,V,Palv,delivered,leakFlow,uin,uout,target,in)
% Produce finite worst-capability metrics for a runnable but non-breathing
% model.  This keeps technical validity separate from task completion.
use=t>max(t(1)+.5,.15*t(end));
if nnz(use)<20,use=true(size(t));end
expectedVolume=max(double(in.patient_compliance)*(target-5),.02);
r.breath_cycle_present=false;
r.plateau_error=median(abs(P(use)-target));
r.peep_error=median(abs(P(use)-5));
r.mean_plateau_pressure=median(P(use));
r.plateau_std=std(P(use));r.max_pressure=max(P);
r.tidal_volume=max(V(use))-min(V(use));
r.tidal_volume_ratio_error=abs(r.tidal_volume/expectedVolume-1);
dv=local_derivative(V,t);
r.mass_residual=rms(dv(use)-flow(use))/max(rms(flow(use)),.05);
r.circuit_flow_residual=rms(delivered(use)-flow(use)-leakFlow(use))/ ...
    max(rms(delivered(use)),.05);
r.alveolar_residual=rms(Palv(use)-(5+V(use)/double(in.patient_compliance))) / ...
    max(rms(5+V(use)/double(in.patient_compliance)),1);
reff=double(in.airway_resistance)*ones(size(t));
event=double(in.obstruction_time);inside=t>=event&t<event+1;
reff(inside)=reff(inside)*double(in.obstruction_factor);
r.airway_residual=rms((P(use)-Palv(use))-flow(use).*reff(use)) / ...
    max(rms(P(use)-Palv(use)),1);
r.mean_insp_valve=mean(uin(use));r.mean_exp_valve=mean(uout(use));
r.mean_abs_flow=mean(abs(flow(use)));r.mean_delivered_flow=mean(delivered(use));
r.mean_abs_delivered_flow=mean(abs(delivered(use)));
r.mean_leak_flow=mean(leakFlow(use));r.mean_abs_leak_flow=mean(abs(leakFlow(use)));
r.leak_conductance=median(leakFlow(use)./max(P(use),1));
r.leak_orifice_index=median(leakFlow(use)./sqrt(max(P(use),1)));
activeLeak=use&abs(delivered)>.02&leakFlow>=0;
if any(activeLeak)
    r.leak_flow_fraction_index=median(leakFlow(activeLeak)./abs(delivered(activeLeak)));
else
    r.leak_flow_fraction_index=0;
end
r.actuator_role_margin=0;r.alarm_strategy_error=1;
r.cycle_period_error=1;r.ie_ratio_error=1;
r.obstruction_response_deficit=1;r.obstruction_ratio_error=1;
r.recovery_time=max(t(end)-event-1,0)+1;
r.public_leak_fraction=double(in.leak_fraction);
r.valid=finite_row_metrics(r);
end

function ok=finite_row_metrics(r)
ok=true;names=fieldnames(r);
for i=1:numel(names)
    name=string(names{i});
    if name=="scenario"||name=="valid",continue;end
    value=r.(names{i});
    if ~(isnumeric(value)||islogical(value))||isempty(value)||any(~isfinite(double(value)),'all')
        ok=false;return
    end
end
end

function cycle=detect_breath_cycle(t,P,flow,valves,target)
dt=median(diff(t));base=t>.5;flowScale=prctile(abs(flow(base)),90);
pHigh=P>5+.45*(target-5);fHigh=flow>max(.08*flowScale,.002);
vHigh=valves(:,1)>valves(:,2);
raw=(double(pHigh)+double(fHigh)+double(vHigh))>=2;
smoothWindow=max(3,round(.06/dt));inspiration=movmean(double(raw),smoothWindow)>=.5;
rises=find(diff([false;inspiration])==1&t>.5);
if numel(rises)>=2
    keep=[true;diff(t(rises))>.8];rises=rises(keep);
end
cycle=struct('valid',false,'period',NaN,'duty',NaN,'phase0',NaN, ...
    'inspiration',false(size(t)),'detected_rises',numel(rises));
if numel(rises)<3,return;end
period=median(diff(t(rises)));duties=[];
for k=1:numel(rises)-1
    ix=rises(k):rises(k+1)-1;duties(end+1)=mean(inspiration(ix)); %#ok<AGROW>
end
duty=median(duties);phase0=t(rises(1));
if ~isfinite(period)||~isfinite(duty)||period<=0||duty<=0||duty>=1,return;end
cycle=struct('valid',true,'period',period,'duty',duty,'phase0',phase0, ...
    'inspiration',logical(inspiration),'detected_rises',numel(rises));
end

function err=alarm_strategy_error(t,P,uin,uout,alarm,targetTrace)
isAlarm=alarm>.5;dP=local_derivative(P,t);dt=median(diff(t));
breach=P>35.05;pressureFalling=dP<-.02;
hardProtection=isAlarm|uin<.05|uout>.50|pressureFalling;
unprotected=0;if any(breach),unprotected=mean(~hardProtection(breach));end
largeError=abs(P-targetTrace)>max(6,.30*(max(targetTrace)-5));
window=max(3,round(.40/dt));persistentRisk=movmean(double(largeError),window)>=.80;
towardTarget=dP.*(targetTrace-P)>.05;
response=isAlarm|uin<.05|uout>.50|towardTarget;
unresponded=0;if any(persistentRisk),unresponded=mean(~response(persistentRisk));end
comfort=abs(P-targetTrace)<=2&P<32;
safeAlarm=0;if any(comfort),safeAlarm=mean(isAlarm(comfort));end
alwaysOn=max(0,(safeAlarm-.80)/.20);
err=min(max([unprotected,unresponded,alwaysOn]),1);
end

function evidence=shared_leak_evidence(rows)
x=[rows.public_leak_fraction]';linear=[rows.leak_conductance]';
orifice=[rows.leak_orifice_index]';
flowFraction=[rows.leak_flow_fraction_index]';
[linearError,linearDirection]=monotonic_leak_index(x,linear);
[orificeError,orificeDirection]=monotonic_leak_index(x,orifice);
[fractionError,fractionDirection]=monotonic_leak_index(x,flowFraction);
if linearError<=orificeError&&linearError<=fractionError
    selected="pressure-linear";monotonic=linearError;direction=linearDirection;
elseif orificeError<=fractionError
    selected="pressure-square-root";monotonic=orificeError;direction=orificeDirection;
else
    % A dimensionless public leak_fraction may legally describe the share
    % of delivered circuit flow lost through the leak branch.  Accept that
    % representation when it preserves the same measured downstream mass
    % balance and responds monotonically to the public input.
    selected="delivered-flow-fraction";monotonic=fractionError;direction=fractionDirection;
end
responseDeficit=1;leakRatio=NaN;
nom=find([rows.scenario]=="nominal",1);probe=find([rows.scenario]=="leak_probe",1);
if ~isempty(nom)&&~isempty(probe)&&rows(nom).mean_abs_leak_flow>1e-5
    leakRatio=rows(probe).mean_abs_leak_flow/rows(nom).mean_abs_leak_flow;
    responseDeficit=max(0,(1.10-leakRatio)/.10);
end
err=max([monotonic,direction,responseDeficit]);
evidence=struct('error',err,'selected_flow_law',selected, ...
    'linear_index_monotonic_error',linearError,'orifice_index_monotonic_error',orificeError, ...
    'flow_fraction_index_monotonic_error',fractionError, ...
    'selected_monotonic_error',monotonic,'direction_error',direction, ...
    'paired_leak_flow_ratio',leakRatio,'paired_response_deficit',responseDeficit);
end

function [err,direction]=monotonic_leak_index(x,y)
err=1;direction=1;
if numel(x)<3||any(~isfinite(x))||any(~isfinite(y)),return;end
viol=[];positive=[];scale=max(max(y)-min(y),1e-6);
for i=1:numel(x)
    for j=1:numel(x)
        if x(j)>x(i)
            viol(end+1)=max(y(i)-y(j),0)/scale; %#ok<AGROW>
            positive(end+1)=y(j)-y(i); %#ok<AGROW>
        end
    end
end
if isempty(viol),return;end
err=max(viol);direction=double(median(positive)<=0);
end

function evidence=shared_airway_evidence(runs)
% Accept one globally selected passive airway family.  The public
% airway_resistance remains the linear coefficient; a legal Rohrer airway
% may additionally contain one nonnegative q*abs(q) coefficient shared by
% all scenarios.  The obstruction multiplier may legally act on R1 alone
% or on the whole Rohrer drop; both candidates retain the public linear
% resistance and cannot refit the input independently per run.
y=[];linearTerm=[];quadraticTerm=[];scaledQuadraticTerm=[];passiveViolation=[];
for i=1:numel(runs)
    run=runs(i);[t,a,okA]=xp9_series(run,'airway',3);
    [t2,g,okG]=xp9_series(run,'lung_state',1);
    if ~(okA&&okG&&isequal(t,t2)),continue;end
    pressureDrop=a(:,1)-g(:,1);flow=a(:,2);
    event=double(run.inputs.obstruction_time);mult=ones(size(t));
    inside=t>=event&t<event+1;
    mult(inside)=double(run.inputs.obstruction_factor);
    resistance=double(run.inputs.airway_resistance).*mult;
    use=t>3&abs(flow)>.002&isfinite(pressureDrop)&isfinite(flow);
    y=[y;pressureDrop(use)]; %#ok<AGROW>
    linearTerm=[linearTerm;resistance(use).*flow(use)]; %#ok<AGROW>
    quadraticTerm=[quadraticTerm;flow(use).*abs(flow(use))]; %#ok<AGROW>
    scaledQuadraticTerm=[scaledQuadraticTerm;mult(use).*flow(use).*abs(flow(use))]; %#ok<AGROW>
    localScale=max(abs(pressureDrop(use)),.05);
    passiveViolation=[passiveViolation;(pressureDrop(use).*flow(use)<-.002.*localScale)]; %#ok<AGROW>
end
linearResidual=1;rohrerR1Residual=1;rohrerWholeResidual=1;
rohrerR1Coefficient=NaN;rohrerWholeCoefficient=NaN;passiveError=1;
if numel(y)>=500&&all(isfinite([y;linearTerm;quadraticTerm;scaledQuadraticTerm]))
    scale=max(rms(y),1);
    linearResidual=rms(y-linearTerm)/scale;
    z=quadraticTerm;rohrerR1Coefficient=max(0,(z'*(y-linearTerm))/max(z'*z,eps));
    rohrerR1Residual=rms(y-linearTerm-rohrerR1Coefficient*z)/scale;
    zScaled=scaledQuadraticTerm;
    rohrerWholeCoefficient=max(0,(zScaled'*(y-linearTerm))/max(zScaled'*zScaled,eps));
    rohrerWholeResidual=rms(y-linearTerm-rohrerWholeCoefficient*zScaled)/scale;
    passiveError=mean(passiveViolation);
end
if linearResidual<=min(rohrerR1Residual,rohrerWholeResidual)+1e-8
    k=1;selectedResidual=linearResidual;
elseif rohrerR1Residual<=rohrerWholeResidual+1e-8
    k=2;selectedResidual=rohrerR1Residual;
else
    k=3;selectedResidual=rohrerWholeResidual;
end
if k==1
    selected="linear R*q";rohrerCoefficient=0;
elseif k==2
    selected="Rohrer: factor multiplies R1 only";rohrerCoefficient=rohrerR1Coefficient;
else
    selected="Rohrer: factor multiplies whole pressure drop";rohrerCoefficient=rohrerWholeCoefficient;
end
evidence=struct('error',max(selectedResidual,passiveError), ...
    'selected_law',selected,'selected_residual',selectedResidual, ...
    'linear_residual',linearResidual, ...
    'rohrer_r1_only_residual',rohrerR1Residual, ...
    'rohrer_whole_drop_residual',rohrerWholeResidual, ...
    'rohrer_quadratic_coefficient',rohrerCoefficient, ...
    'passive_pressure_drop_violation',passiveError, ...
    'selection_scope',"single global law and coefficient across all runs");
end

function [err,detail]=future_valve_causality(runs)
% A valve command may reach the pneumatic state through a fast valve, a
% deliberately slow valve, or a transport-dominated gas path.  Therefore
% causality is evaluated prospectively at several public-cycle-compatible
% time scales instead of imposing one reference-specific actuator delay.
% Models are fit on the first 40% and candidate scale is selected on the
% next 22%; the chosen scale is then scored on the untouched final 38%.
delays=[0 .04 .08 .16 .24 .36 .52 .72 .96];horizons=[.04 .08 .16 .24];
template=empty_causal_candidate();candidates=repmat(template,numel(delays)*numel(horizons),1);
n=0;
for i=1:numel(delays)
    for j=1:numel(horizons)
        n=n+1;candidates(n)=fit_causal_candidate(runs,delays(i),horizons(j));
    end
end
trainScore=-Inf(size(candidates));
for i=1:numel(candidates)
    if candidates(i).valid&&candidates(i).sign_violation<=.50
        % This is deliberately a pre-held-out model-selection quantity.
        % Physical direction comes from fit coefficients; predictive gain
        % is measured on the disjoint middle selection partition.
        trainScore(i)=candidates(i).train_gain;
    end
end
[~,selected]=max(trainScore);if isempty(selected),selected=1;end
best=candidates(selected);

fitResidual=best.test_residual;baselineResidual=best.test_baseline_residual;
predictiveGain=best.test_gain;gainDeficit=max(0,.01-predictiveGain)/.01;
signViolation=best.sign_violation;responseDeficit=max(0,.08-best.response_strength)/.08;
if best.valid
    err=max([gainDeficit,signViolation,responseDeficit]);
    % The causal term is a witness, not a soft style preference.  A valve
    % trace that has no held-out forward predictive value, has predominantly
    % reversed physical direction, or has degenerate effect must not retain
    % partial credit merely because the remaining plant outputs look good.
    if predictiveGain<.01||signViolation>.50||best.response_strength<.08
        err=max(err,1.5);
    end
else
    err=1;
end
detail=struct('error',err,'heldout_pressure_residual',fitResidual(1), ...
    'heldout_delivered_flow_residual',fitResidual(2),'sign_violation',signViolation, ...
    'state_only_pressure_residual',baselineResidual(1), ...
    'state_only_delivered_flow_residual',baselineResidual(2), ...
    'incremental_predictive_gain',predictiveGain,'predictive_gain_deficit',gainDeficit, ...
    'past_valve_response_deficit',responseDeficit,'coefficients',best.coefficients, ...
    'feature_mean',best.feature_mean,'feature_scale',best.feature_scale, ...
    'selected_global_valve_signs',[1 -1], ...
    'candidate_delays_seconds',delays,'candidate_horizons_seconds',horizons, ...
    'selected_delay_seconds',best.delay,'selected_horizon_seconds',best.horizon, ...
    'fit_partition',"first 40% of every run", ...
    'selection_partition',"middle 22% of every run", ...
    'verification_partition',"final 38% of every run", ...
    'candidate_train_gain',reshape([candidates.train_gain],numel(horizons),numel(delays))', ...
    'candidate_heldout_gain',reshape([candidates.test_gain],numel(horizons),numel(delays))');
end

function result=fit_causal_candidate(runs,delay,horizon)
result=empty_causal_candidate();result.delay=delay;result.horizon=horizon;
fitX=[];fitY=[];selectX=[];selectY=[];testX=[];testY=[];
for i=1:numel(runs)
    run=runs(i);[t,a,okA]=xp9_series(run,'airway',3);
    [t2,c,okC]=xp9_series(run,'circuit_flow',2);[t3,u,okU]=xp9_series(run,'actuator',3);
    if ~(okA&&okC&&okU&&isequal(t,t2)&&isequal(t,t3)),continue;end
    dt=median(diff(t));lag=max(0,round(delay/dt));span=max(1,round(horizon/dt));
    idx=(find(t>.35&t<t(end)-delay-horizon-.02))';
    stride=max(1,round(.02/dt));idx=idx(1:stride:end);
    responseStart=idx+lag;responseEnd=responseStart+span;
    keep=responseEnd<=numel(t);idx=idx(keep);responseStart=responseStart(keep);
    responseEnd=responseEnd(keep);if isempty(idx),continue;end
    P=a(:,1);flow=a(:,2);delivered=c(:,1);leakFlow=c(:,2);
    phase=2*pi*t(idx)/3;
    X=[ones(numel(idx),1),u(idx,1),u(idx,2),P(idx),flow(idx),delivered(idx), ...
        leakFlow(idx),sin(phase),cos(phase),double(mod(t(idx),3)<1)];
    elapsed=t(responseEnd)-t(responseStart);
    Y=[(P(responseEnd)-P(responseStart))./elapsed, ...
        (delivered(responseEnd)-delivered(responseStart))./elapsed];
    fit=t(idx)<=.40*t(end);select=t(idx)>.40*t(end)&t(idx)<=.62*t(end);
    test=t(idx)>.62*t(end);
    fitX=[fitX;X(fit,:)];fitY=[fitY;Y(fit,:)]; %#ok<AGROW>
    selectX=[selectX;X(select,:)];selectY=[selectY;Y(select,:)]; %#ok<AGROW>
    testX=[testX;X(test,:)];testY=[testY;Y(test,:)]; %#ok<AGROW>
end
if size(fitX,1)<150||size(selectX,1)<100||size(testX,1)<100,return;end
mu=mean(fitX(:,2:end),1);sd=max(std(fitX(:,2:end),0,1),1e-6);
fitX(:,2:end)=(fitX(:,2:end)-mu)./sd;
selectX(:,2:end)=(selectX(:,2:end)-mu)./sd;
testX(:,2:end)=(testX(:,2:end)-mu)./sd;
if rank(fitX)<7,return;end
baselineColumns=[1 4:size(fitX,2)];
beta=pinv(fitX)*fitY;baseBeta=pinv(fitX(:,baselineColumns))*fitY;
trainPrediction=selectX*beta;testPrediction=testX*beta;
trainBasePrediction=selectX(:,baselineColumns)*baseBeta;
testBasePrediction=testX(:,baselineColumns)*baseBeta;
trainScale=max(std(selectY,0,1),[.10 .02]);testScale=max(std(testY,0,1),[.10 .02]);
trainResidual=sqrt(mean((selectY-trainPrediction).^2,1))./trainScale;
trainBaseResidual=sqrt(mean((selectY-trainBasePrediction).^2,1))./trainScale;
testResidual=sqrt(mean((testY-testPrediction).^2,1))./testScale;
testBaseResidual=sqrt(mean((testY-testBasePrediction).^2,1))./testScale;
trainGain=mean((trainBaseResidual-trainResidual)./max(trainBaseResidual,.05));
testGain=mean((testBaseResidual-testResidual)./max(testBaseResidual,.05));
expectedSigns=[1 1;-1 -1];rawValveBeta=beta(2:3,:);
signViolation=sum(max(-rawValveBeta.*expectedSigns,0),'all')/max(sum(abs(rawValveBeta),'all'),eps);
response=sqrt(mean((testX(:,2:3)*rawValveBeta).^2,'all'))/max(mean(testScale),.02);
result=struct('valid',all(isfinite([trainGain testGain signViolation response])), ...
    'delay',delay,'horizon',horizon,'train_gain',trainGain,'test_gain',testGain, ...
    'train_residual',trainResidual,'train_baseline_residual',trainBaseResidual, ...
    'test_residual',testResidual,'test_baseline_residual',testBaseResidual, ...
    'sign_violation',signViolation,'response_strength',response, ...
    'coefficients',beta,'feature_mean',mu,'feature_scale',sd);
end

function c=empty_causal_candidate()
c=struct('valid',false,'delay',NaN,'horizon',NaN,'train_gain',-Inf,'test_gain',-Inf, ...
    'train_residual',[1 1],'train_baseline_residual',[1 1], ...
    'test_residual',[1 1],'test_baseline_residual',[1 1], ...
    'sign_violation',1,'response_strength',0,'coefficients',NaN(10,2), ...
    'feature_mean',zeros(1,9),'feature_scale',ones(1,9));
end

function margin=aligned_actuator_role_margin(run,delay)
margin=-1;[t,a,okA]=xp9_series(run,'airway',3);
[t2,u,okU]=xp9_series(run,'actuator',3);
if ~(okA&&okU&&isequal(t,t2)),return;end
target=double(run.inputs.target_insp_pressure);
cycle=detect_breath_cycle(t,a(:,1),a(:,2),u(:,1:2),target);
if ~cycle.valid,return;end
dt=median(diff(t));lag=max(0,round(delay/dt));idx=(1+lag:numel(t))';
stable=t(idx)>max(2*cycle.period,3);idx=idx(stable);if isempty(idx),return;end
causeIdx=idx-lag;insp=cycle.inspiration(idx);expir=~insp;
if nnz(insp)<20||nnz(expir)<20,return;end
margin=.5*((mean(u(causeIdx(insp),1))-mean(u(causeIdx(expir),1)))+ ...
    (mean(u(causeIdx(expir),2))-mean(u(causeIdx(insp),2))));
end

function [deficit,ratioError]=obstruction_evidence(t,P,Palv,flow,valves,event,period,factor,recovery)
deficit=1;ratioError=1;eventMask=t>=event+.10&t<=event+.80;
if nnz(eventMask)<20||event-period<t(1),return;end
baselineTime=t(eventMask)-period;baseP=interp1(t,P,baselineTime);
basePalv=interp1(t,Palv,baselineTime);baseFlow=interp1(t,flow,baselineTime);
baseValves=interp1(t,valves,baselineTime);
eventFlow=flow(eventMask);eventR=(P(eventMask)-Palv(eventMask))./eventFlow;
baseR=(baseP-basePalv)./baseFlow;valid=abs(eventFlow)>.02&abs(baseFlow)>.02 ...
    &isfinite(eventR)&isfinite(baseR)&baseR>0;
if nnz(valid)>=12
    measuredRatio=median(eventR(valid))/max(median(baseR(valid)),.1);
    ratioError=abs(measuredRatio-factor)/max(factor,.2);
end
physicalStrength=max([median(abs(P(eventMask)-baseP))/.02, ...
    median(abs(eventFlow-baseFlow))/.004]);
actuatorStrength=median(vecnorm(valves(eventMask,:)-baseValves,2,2))/.001;
recoveryStrength=max(0,1-recovery/max(period,.5));
multiSignalStrength=min(physicalStrength,max(actuatorStrength,recoveryStrength));
deficit=max(0,1-multiSignalStrength);
end

function dt=recovery_time(t,P,targetTrace,eventEnd)
dt=max(t(end)-eventEnd,0)+1;good=abs(P-targetTrace)<=2;
start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(2,round(.20/median(diff(t))));
for i=start:max(start,numel(t)-window)
    if all(good(i:min(i+window-1,numel(t)))),dt=t(i)-eventEnd;return;end
end
end

function q=ceiling_utility(maxPressure)
excess=max(maxPressure-35,0);
q=xp9_utility(excess,[0 .05 .15 .30 .75 1.0],[1 1 .90 .55 .10 0]);
end

function dy=local_derivative(y,t)
dy=zeros(size(y));dy(1,:)=(y(2,:)-y(1,:))/(t(2)-t(1));
dy(end,:)=(y(end,:)-y(end-1,:))/(t(end)-t(end-1));
dy(2:end-1,:)=(y(3:end,:)-y(1:end-2,:))./(t(3:end)-t(1:end-2));
end

function r=empty_row()
r=struct('scenario',"",'valid',false,'plateau_error',NaN,'peep_error',NaN, ...
    'tidal_volume',NaN,'tidal_volume_ratio_error',NaN,'plateau_std',NaN, ...
    'max_pressure',NaN,'mass_residual',NaN,'circuit_flow_residual',NaN, ...
    'alveolar_residual',NaN,'airway_residual',NaN,'mean_insp_valve',NaN, ...
    'mean_exp_valve',NaN,'mean_plateau_pressure',NaN,'mean_abs_flow',NaN, ...
    'mean_delivered_flow',NaN,'mean_abs_delivered_flow',NaN, ...
    'mean_leak_flow',NaN,'mean_abs_leak_flow',NaN, ...
    'leak_conductance',NaN,'leak_orifice_index',NaN, ...
    'leak_flow_fraction_index',NaN,'min_lung_volume',NaN, ...
    'volume_numeric_tolerance',NaN,'negative_volume_ratio',NaN, ...
    'breath_cycle_present',false, ...
    'public_leak_fraction',NaN,'actuator_role_margin',NaN,'alarm_strategy_error',NaN, ...
    'cycle_period_error',NaN,'ie_ratio_error',NaN,'obstruction_response_deficit',NaN, ...
    'obstruction_ratio_error',NaN,'recovery_time',NaN);
end

function out=empty_out()
out=struct('schema',"simuverity.xp9-score.v1",'policy_id',"simuverity-101-v1:p9-xmed01:scoring", ...
    'formula',"G*100*A^.20*Q^.15*M^.30*R^.15*D^.20", ...
    'score_inputs_valid',false,'diagnostics_valid',false,'G',false, ...
    'gate_reasons',strings(0,1),'A',0,'Q',0,'M',0,'R',0,'D',0,'score',0, ...
    'raw_metrics',struct(),'utility_metrics',struct(),'scenario_rows',struct([]), ...
    'diagnostic_scope',"fail-closed phase-independent breath timing, public-unit-neutral finite valve commands, Boolean alarm state, scale-aware small-negative lung-volume tolerance, downstream delivered/patient/leak balance, training-selected multiscale prospective held-out valve causality, globally selected passive linear-or-Rohrer airway law, monotone paired leak evidence accepting pressure-linear, pressure-square-root, or delivered-flow-fraction laws, strategy-neutral alarm/protection, explicit 35 cmH2O cap, and obstruction evidence");
end
