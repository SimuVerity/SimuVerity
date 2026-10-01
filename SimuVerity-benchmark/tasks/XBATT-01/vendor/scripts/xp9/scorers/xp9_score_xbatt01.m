function out=xp9_score_xbatt01(runs,spec)
%XP9_SCORE_XBATT01 Dedicated electro-thermal pack and cooling-fault score.
out=empty_out();
rows=repmat(empty_row(),numel(runs),1);allValid=true;
for i=1:numel(runs)
    rows(i)=measure_run(runs(i));allValid=allValid&&rows(i).valid;
end
out.score_inputs_valid=allValid&&numel(runs)==1+numel(spec.scenarios);
out.diagnostics_valid=allValid;out.G=out.score_inputs_valid;
if ~out.G,out.gate_reasons="SCENARIO_OR_ELECTRO_THERMAL_OUTPUT_CONTRACT_INVALID";end
out.scenario_rows=rows;
[spreadEvidence,coolingEvidence]=shared_pack_evidence(runs,rows);
faultEvidence=fault_pair_evidence(runs,"nominal","fault_pair_none");
controlEvidence=fault_pair_evidence(runs,"warm_spread", ...
    "warm_spread_fault_pair_none");

if ~isempty(rows)
    n=rows(1);
    qTemp=xp9_utility(n.peak_temperature,[260 307.5 310.5 313.5 316.5 321],[1 1 .94 .74 .30 0]);
    qSpread=xp9_utility(n.peak_spread,[0 .35 .75 1.45 2.6 4.5],[1 1 .94 .73 .28 0]);
    qVolt=xp9_utility(max(40.0-n.min_module_voltage,0),[0 .20 .55 1.2 2.5 5],[1 1 .94 .73 .28 0]);
    qSoc=xp9_utility(max(.30-n.min_soc,0),[0 .01 .03 .07 .13 .25],[1 1 .94 .74 .30 0]);
    out.A=xp9_group([qTemp qSpread qVolt qSoc],[.32 .28 .22 .18],true);

    qSafety=xp9_utility(n.safety_violation,[0 .02 .08 .22 .60 1.5],[1 1 .93 .70 .24 0]);
    qAux=xp9_utility(n.aux_energy_Wh,[0 .20 .50 1.2 3.0 6.5],[1 1 .94 .74 .30 0]);
    qAlarm=xp9_utility(n.alarm_mismatch,[0 .002 .01 .04 .15 .45],[1 1 .94 .72 .25 0]);
    qRated=xp9_utility(max([rows.cooling_rating_violation]), ...
        [0 .002 .01 .04 .15 .45],[1 1 .94 .72 .25 0]);
    out.Q=xp9_group([qSafety qAux qAlarm qRated],[.40 .22 .22 .16],true);

else
    out.A=0;out.Q=0;
end

if isempty(rows)
    out.M=0;qProfile=0;
else
    qPack=xp9_utility(max([rows.series_voltage_residual]),[0 1e-6 2e-5 2e-4 2e-3 .02],[1 1 .95 .75 .30 0]);
    qCharge=xp9_utility(max([rows.charge_residual]),[0 2e-4 8e-4 .003 .012 .05],[1 1 .95 .74 .28 0]);
    qThermal=xp9_utility(max([rows.thermal_residual]),[0 .004 .015 .05 .16 .45],[1 1 .94 .73 .27 0]);
    qFaultEvent=xp9_utility(max([rows.fault_event_deficit]),[0 .01 .04 .12 .35 .80],[1 1 .95 .74 .28 0]);
    qFaultPair=xp9_utility(faultEvidence.response_deficit,[0 .01 .04 .12 .35 .80],[1 1 .95 .74 .28 0]);
    qCurrent=xp9_utility(max([rows.current_profile_error]),[0 .06 .10 .16 .28 .50],[1 1 .95 .74 .28 0]);
    qElectrical=xp9_utility(max([rows.electrical_coupling_error]),[0 .05 .12 .24 .45 .85],[1 1 .95 .74 .28 0]);
    qInitialSoc=xp9_utility(max([rows.initial_soc_error]), ...
        [0 1e-4 6e-4 .003 .015 .08],[1 1 .95 .75 .30 0]);
    % initial_soc is a declared initial condition.  ambient_temperature is
    % the cooling-loop boundary condition, not a declared module initial
    % temperature.  Temperature initialization is therefore diagnostic;
    % the thermal ledger below checks that whatever finite, safe initial
    % state is used evolves causally.
    qInitial=qInitialSoc;
    qHeatTotal=xp9_utility(max([rows.total_heat_residual]), ...
        [0 2e-5 2e-4 .002 .02 .15],[1 1 .95 .75 .30 0]);
    qSpread=xp9_utility(spreadEvidence.error,[0 .035 .09 .20 .42 .80],[1 1 .95 .75 .30 0]);
    qTransport=xp9_utility(coolingEvidence.transport_error,[0 .015 .045 .12 .30 .70],[1 1 .95 .75 .30 0]);
    qHydraulic=xp9_utility(coolingEvidence.hydraulic_error,[0 .02 .06 .15 .35 .75],[1 1 .95 .75 .30 0]);
    qAuxMech=xp9_utility(coolingEvidence.auxiliary_error,[0 .02 .06 .15 .35 .75],[1 1 .95 .75 .30 0]);
    % The public task explicitly requires a repeatable multi-level current
    % profile.  Without real within-run excitation, terminal resistance and
    % heat/current coupling are not identifiable; this is a deficient model,
    % not an invalid artifact.  Keep a separate evidence utility instead of
    % letting unrelated thermal quality hide the missing experiment design.
    profileExcitation=mean(double([rows.electrical_step_evidence]));
    qProfile=qCurrent*profileExcitation;
    qElectricalGroup=xp9_group([qPack qCharge qElectrical qInitial], ...
        [.17 .23 .36 .24],true);
    qExchange=xp9_utility(max([rows.thermal_exchange_direction_error]), ...
        [0 .001 .01 .04 .15 .50],[1 1 .95 .75 .30 0]);
    qThermalGroup=xp9_group([qThermal qHeatTotal qSpread qExchange], ...
        [.35 .22 .28 .15],true);
    qCoolingGroup=xp9_group([qFaultEvent qFaultPair qTransport qHydraulic qAuxMech], ...
        [.20 .18 .24 .21 .17],true);
    out.M=xp9_group([qElectricalGroup qThermalGroup qCoolingGroup qProfile], ...
        [.29 .25 .23 .23],true);
    % Missing excitation bounds the strength of any mechanism claim.  The
    % cap remains nonzero because useful thermal/cooling behavior may still
    % be present, but a static-current trace cannot receive near-complete M.
    out.M=min(out.M,.45+.55*qProfile);
    % "Actively regulated liquid cooling" is a public task requirement.
    % A fixed pump command may still produce a physically consistent
    % passive thermal trace, but it cannot support a complete controlled
    % cooling mechanism claim.  Retain credit for the pack electrical and
    % thermal ledgers while bounding M when the scenario matrix never
    % elicits a settled, non-fault command change.
    if ~coolingEvidence.active_regulation_supported
        out.M=min(out.M,.55);
    end
    % module_parameter_spread is explicitly a fractional spread in both
    % resistance and heat transfer.  Electrical spread alone cannot support
    % a complete electro-thermal mechanism claim.
    if ~spreadEvidence.thermal_spread_supported
        out.M=min(out.M,.55);
    end
    % cooling_state(:,5) is the declared total coolant heat removal and must
    % close against the eight module-to-coolant heat-removal channels.
    if max([rows.total_heat_residual])>.15
        out.M=min(out.M,.45);
    end
    % thermal_flux is a required physical output, not an optional
    % diagnostic. If the reported qGen/qCool channels cannot reproduce the
    % logged module-temperature state equation even to the severe-residual
    % band, the electro-thermal mechanism is internally disconnected.
    % Other well-formed outputs must not average that shortcut back to a
    % near-reference M score.
    if max([rows.thermal_residual])>.15
        out.M=min(out.M,.45);
    end
    % A logged coolant outlet is not an unconstrained diagnostic signal.
    % The two branch heat-removal totals must be transportable by the
    % declared delivered mass flow and their measured outlet rises, and an
    % outlet cannot be hotter than the corresponding four-module branch.
    % These are finite physical failures rather than malformed-log gates,
    % so retain a score but cap the mechanism claim.
    if max([rows.coolant_enthalpy_capacity_error])>1e-8|| ...
            max([rows.coolant_outlet_passivity_error])>1e-8
        out.M=min(out.M,.45);
    end
end

rq=zeros(numel(rows),1);dq=zeros(numel(rows),1);
for i=1:numel(rows)
    r=rows(i);
    qt=xp9_utility(r.peak_temperature,[260 313.5 315.5 317.5 320 324],[1 1 .92 .68 .22 0]);
    qs=xp9_utility(r.peak_spread,[0 .55 1.15 2.1 3.4 5.5],[1 1 .92 .69 .23 0]);
    qv=xp9_utility(max(36-r.min_module_voltage,0),[0 .10 .35 .9 2.0 4.5],[1 1 .92 .69 .23 0]);
    qsoc=xp9_utility(max(.15-r.min_soc,0),[0 .005 .02 .055 .12 .25],[1 1 .92 .68 .22 0]);
    qsafe=xp9_utility(r.safety_violation,[0 .03 .10 .28 .75 1.8],[1 1 .92 .68 .22 0]);
    rq(i)=xp9_group([qt qs qv qsoc qsafe],[.28 .24 .18 .12 .18],true);
    qSlope=xp9_utility(r.thermal_recovery_margin,[-.05 -.025 -.012 -.004 .002 .02],[0 .20 .55 .82 .96 1]);
    qRecover=xp9_utility(r.recovery_time,[0 3 8 17 35 65],[1 1 .92 .70 .26 0]);
    if r.fault_severity<=.001
        dq(i)=1;
    else
        qFault=xp9_utility(max(r.fault_event_deficit,r.event_physical_response_deficit), ...
            [0 .01 .04 .12 .35 .80],[1 1 .93 .71 .25 0]);
        dq(i)=xp9_group([qRecover qSlope qFault],[.38 .32 .30],true);
    end
end
if isempty(rq)
    out.R=0;out.D=0;
else
    out.R=xp9_tail(rq,ones(size(rq)));qPairDynamic=xp9_utility(faultEvidence.response_deficit, ...
        [0 .01 .04 .12 .35 .80],[1 1 .93 .71 .25 0]);
    scenarioDynamic=xp9_tail(dq,ones(size(dq)));
    % scenarioDynamic is the worst score over the required scenarios.
    % The paired-fault and profile terms are heterogeneous evidence, so the
    % outer combination is an ordinary weighted group rather than a second
    % application of worst-case pressure.
    out.D=xp9_group([scenarioDynamic qPairDynamic qProfile],[.60 .25 .15],true);
    % The same missing profile also limits transient identifiability.
    out.D=min(out.D,.55+.45*qProfile);
    % Passive flow loss and temperature drift prove that the injected fault
    % occurred, not that an active cooling controller responded.  Without
    % observable regulation, retain only partial dynamic credit.
    if ~coolingEvidence.active_regulation_supported
        out.D=min(out.D,.35);
    end
    % A passive flow loss or temperature rise proves that the fault was
    % injected, but not that the active cooling controller responded.
    if ~controlEvidence.active_control_response_supported
        out.D=min(out.D,.40);
    end
end
out.utility_metrics=struct('nominal_accuracy',out.A,'nominal_quality',out.Q, ...
    'mechanism',out.M,'shared_spread_evidence',spreadEvidence, ...
    'shared_cooling_evidence',coolingEvidence, ...
    'paired_fault_evidence',faultEvidence, ...
    'paired_active_control_evidence',controlEvidence, ...
    'multilevel_profile_evidence',qProfile, ...
    'worst_range',out.R,'worst_dynamic',out.D);
out.raw_metrics=rows;w=spec.groups.weights;
out.cross_scenario_metrics=struct('spread',spreadEvidence,'cooling',coolingEvidence, ...
    'paired_fault',faultEvidence,'paired_active_control',controlEvidence);
out.score=xp9_total(out.G,[out.A out.Q out.M out.R out.D],[w.A w.Q w.M w.R w.D]);
end

function r=measure_run(run)
r=empty_row();r.scenario=string(run.scenario);
if string(run.stage)~="simulated",return;end
[t,b,okB]=xp9_series(run,'battery_state',18);
[t2,th,okT]=xp9_series(run,'thermal_state',10);
[t3,c,okC]=xp9_series(run,'cooling_state',6);
[t4,q,okQ]=xp9_series(run,'thermal_flux',16);
if ~(okB&&okT&&okC&&okQ&&isequal(t,t2)&&isequal(t,t3)&&isequal(t,t4)),return;end
% xp9_series handles non-finite/malformed logs.  Keep only gross numerical
% explosion and the declared boolean alarm channel in G; finite electrical,
% thermal, pump and hydraulic rating failures are scored continuously.
bad=any(abs(b)>1e9,'all')||any(abs(th)>1e6,'all')|| ...
        any(abs(c(:,1:5))>1e9,'all')||any(abs(q)>1e9,'all')|| ...
        any(c(:,6)<-1e-4)||any(c(:,6)>1.001);
if bad,return;end

temp=th(:,1:8);voltage=b(:,3:10);soc=b(:,11:18);current=b(:,1);
r.initial_soc_error=max(abs(soc(1,:)-double(run.inputs.initial_soc)));
r.initial_temperature_error=max(abs(temp(1,:)-double(run.inputs.ambient_temperature)));
r.peak_temperature=max(temp,[],'all');
r.peak_spread=max(max(temp,[],2)-min(temp,[],2));
r.min_module_voltage=min(voltage,[],'all');r.min_soc=min(soc,[],'all');
r.aux_energy_Wh=trapz(t,c(:,4))/3600;
r.coolant_outlet_imbalance=max(abs(th(:,9)-th(:,10)));
tempEx=max(max(temp,[],2)-318,0);spreadEx=max(max(temp,[],2)-min(temp,[],2)-3,0);
voltEx=max(36-min(voltage,[],2),0);socEx=max(.15-min(soc,[],2),0);
socHighEx=max(max(soc,[],2)-1,0);
r.safety_violation=max([max(tempEx),max(spreadEx),max(voltEx)/4, ...
    max(socEx)*10,max(socHighEx)*10]);
unsafe=tempEx>0|spreadEx>0|voltEx>0|socEx>0;alarm=c(:,6)>.5;
comfort=max(temp,[],2)<=316.5&(max(temp,[],2)-min(temp,[],2))<=2.5& ...
    min(voltage,[],2)>=37&min(soc,[],2)>=.17;
missed=0;if any(unsafe),missed=mean(~alarm(unsafe));end
falseAlarm=0;if any(comfort),falseAlarm=mean(alarm(comfort));end
r.alarm_mismatch=max(missed,falseAlarm);
r.alarm_missed_unsafe=missed;r.alarm_false_safe=falseAlarm;
r.pump_command_rating_violation=max([max(max(c(:,1)-1,0)),max(max(-c(:,1),0))]);
r.flow_rating_violation=max([max(max(c(:,2)-.30,0)),max(max(-c(:,2),0))])/.30;
r.pressure_rating_violation=max([max(max(c(:,3)-100,0)),max(max(-c(:,3),0))])/100;
r.aux_power_rating_violation=max([max(max(c(:,4)-120,0)),max(max(-c(:,4),0))])/120;
r.cooling_rating_violation=max([r.pump_command_rating_violation, ...
    r.flow_rating_violation,r.pressure_rating_violation,r.aux_power_rating_violation]);

currentScale=double(run.inputs.discharge_current);
normalizedCurrent=current/max(currentScale,1);
scaleError=abs(mean(normalizedCurrent)-1);
profileSpan=prctile(normalizedCurrent,90)-prctile(normalizedCurrent,10);
spanDeficit=max(0,.18-profileSpan);
firstHalf=t<=.5*t(end);secondHalf=~firstHalf;
repeatError=abs(mean(normalizedCurrent(firstHalf))-mean(normalizedCurrent(secondHalf)))+ ...
    abs((prctile(normalizedCurrent(firstHalf),90)-prctile(normalizedCurrent(firstHalf),10))- ...
    (prctile(normalizedCurrent(secondHalf),90)-prctile(normalizedCurrent(secondHalf),10)));
r.current_profile_error=max([scaleError,spanDeficit,repeatError]);

r.series_voltage_residual=sqrt(mean((b(:,2)-sum(voltage,2)).^2))/max(mean(abs(b(:,2))),1);
socPred=soc(1,:)-cumtrapz(t,current)/(60*3600);
r.charge_residual=sqrt(mean((soc-socPred).^2,'all'))/max(abs(mean(soc(end,:)-soc(1,:))),1e-5);
tempPred=temp(1,:)+cumtrapz(t,(q(:,1:8)-q(:,9:16))/18000);
r.thermal_residual=sqrt(mean((temp-tempPred).^2,'all'))/max(max(temp,[],'all')-min(temp,[],'all'),.5);

transition=find(abs(diff(current))>.10*currentScale);
stepResistance=NaN(numel(transition),8);
for k=1:numel(transition)
    j=transition(k);
    if j>=2&&j+2<=numel(t)
        deltaCurrent=current(j+2)-current(j-1);
        if abs(deltaCurrent)>.05*currentScale
            stepResistance(k,:)=-(voltage(j+2,:)-voltage(j-1,:))/deltaCurrent;
        end
    end
end
validSteps=all(isfinite(stepResistance),2);stepResistance=stepResistance(validSteps,:);
heatResistance=q(:,1:8)./max(current.^2,1);
if isempty(stepResistance)
    % A runnable pack with a constant current trace is a deficient answer,
    % not an invalid artifact.  Keep the missing step-response evidence
    % explicit and finite so the current-profile/mechanism utilities can
    % penalise it without turning the whole run into NaN/G=false.
    r.electrical_step_evidence=false;
    r.module_heat_resistance=median(heatResistance,1);
    heatCorrelation=zeros(1,8);
    for j=1:8
        heatCorrelation(j)=positive_correlation(current.^2,q(:,j));
    end
    r.heat_current_correlation=median(heatCorrelation);
    r.heat_to_step_resistance_ratio=0;
    r.resistance_dispersion=0;
    r.electrical_coupling_error=1;
else
    r.electrical_step_evidence=true;
    r.module_step_resistance=median(stepResistance,1);
    r.module_heat_resistance=median(heatResistance,1);
    resistanceScale=median(r.module_step_resistance);
    scaleRatio=resistanceScale/.014;
    scaleError=max([0,(.50-scaleRatio)/.50,(scaleRatio-2.0)/2.0]);
    % Terminal step resistance is not generally identical to qGen/I^2:
    % reversible/reaction heat and RC-polarization losses are legal.  Keep
    % the public resistance-scale and positive terminal response checks,
    % then verify that reported heat is non-degenerate and causally follows
    % the deliberately multi-level electrical loading.  The separate
    % thermal ledger prevents a decorative heat trace from receiving credit.
    heatScale=median(r.module_heat_resistance);
    heatScaleRatio=heatScale/.014;
    heatScaleError=max([0,(.15-heatScaleRatio)/.15,(heatScaleRatio-8)/8]);
    heatCorrelation=zeros(1,8);
    for j=1:8
        heatCorrelation(j)=positive_correlation(current.^2,q(:,j));
    end
    r.heat_current_correlation=median(heatCorrelation);
    heatCausalityError=max(0,(.45-r.heat_current_correlation)/.45);
    badDirection=mean(r.module_step_resistance<=0)+mean(r.module_heat_resistance<=0);
    r.heat_to_step_resistance_ratio=heatScale/max(resistanceScale,1e-4);
    r.electrical_coupling_error=max([scaleError,heatScaleError, ...
        heatCausalityError,badDirection]);
    r.resistance_dispersion=(max(r.module_step_resistance)-min(r.module_step_resistance)) / ...
        max(2*abs(median(r.module_step_resistance)),1e-5);
end

deltaT=temp-double(run.inputs.ambient_temperature);r.module_thermal_conductance=NaN(1,8);
for j=1:8
    thermalMask=deltaT(:,j)>.02&q(:,8+j)>=0;
    if nnz(thermalMask)>=40
        r.module_thermal_conductance(j)=median(q(thermalMask,8+j)./deltaT(thermalMask,j));
    end
end
finiteConductance=isfinite(r.module_thermal_conductance);
if all(finiteConductance)
    r.thermal_conductance_dispersion= ...
        (max(r.module_thermal_conductance)-min(r.module_thermal_conductance)) / ...
        max(2*abs(median(r.module_thermal_conductance)),1e-5);
    r.thermal_spread_assessed=true;
elseif max(abs(deltaT),[],'all')<=.02
    % A high-conductance pack may remain too close to the coolant boundary
    % for qCool/deltaT to be identifiable.  Lack of excitation is neutral,
    % not invalid evidence; passivity and the full heat ledger remain live.
    r.thermal_conductance_dispersion=0;
    r.thermal_spread_assessed=false;
elseif nnz(finiteConductance)>=4
    k=r.module_thermal_conductance(finiteConductance);
    r.thermal_conductance_dispersion=(max(k)-min(k))/ ...
        max(2*abs(median(k)),1e-5);
    r.thermal_spread_assessed=true;
else
    r.thermal_conductance_dispersion=0;
    r.thermal_spread_assessed=false;
end
r.max_temperature_offset=max(abs(deltaT),[],'all');
exchangeActive=abs(deltaT)>.02|abs(q(:,9:16))>20;
wrongDirection=exchangeActive&q(:,9:16)>1&deltaT<-.02;
r.thermal_exchange_direction_error=nnz(wrongDirection)/max(nnz(exchangeActive),1);
r.public_parameter_spread=double(run.inputs.module_parameter_spread);
r.total_heat_residual=sqrt(mean((c(:,5)-sum(q(:,9:16),2)).^2)) / ...
    max(sqrt(mean(sum(q(:,9:16),2).^2)),1);
% Per-sample coolant enthalpy ledger. Only total delivered flow is public,
% so infer the minimum flow required by each measured branch outlet and
% require the two nonnegative branch flows together not to exceed that
% delivered total. The individual total-flow bounds are kept as a
% redundant guard. A 1e-6 K tolerance is numerical only.
cpCoolant=4180;ambient=double(run.inputs.ambient_temperature);
qLeft=sum(q(:,9:12),2);qRight=sum(q(:,13:16),2);
riseLeft=th(:,9)-ambient;riseRight=th(:,10)-ambient;
delivered=max(c(:,2),0);tolT=1e-6;
requiredLeft=zeros(size(qLeft));requiredRight=zeros(size(qRight));
leftActive=qLeft>1e-6;rightActive=qRight>1e-6;
leftGood=leftActive&riseLeft>tolT;rightGood=rightActive&riseRight>tolT;
requiredLeft(leftGood)=qLeft(leftGood)./(cpCoolant*riseLeft(leftGood));
requiredRight(rightGood)=qRight(rightGood)./(cpCoolant*riseRight(rightGood));
badLeft=leftActive&~leftGood;badRight=rightActive&~rightGood;
requiredLeft(badLeft)=delivered(badLeft)+1;
requiredRight(badRight)=delivered(badRight)+1;
singleLeft=max((qLeft-delivered.*cpCoolant.*max(riseLeft,0))./max(abs(qLeft),1),0);
singleRight=max((qRight-delivered.*cpCoolant.*max(riseRight,0))./max(abs(qRight),1),0);
sumFlowExcess=max((requiredLeft+requiredRight-delivered)./max(delivered,.02),0);
negativeRemoval=max(max(-q(:,9:16),0),[],'all')/ ...
    max(max(abs(q(:,9:16)),[],'all'),1);
r.coolant_enthalpy_capacity_error=max([singleLeft;singleRight;sumFlowExcess],[],'all');
r.coolant_enthalpy_capacity_error=max(r.coolant_enthalpy_capacity_error,negativeRemoval);
leftOutletExcess=th(:,9)-max(temp(:,1:4),[],2)-tolT;
rightOutletExcess=th(:,10)-max(temp(:,5:8),[],2)-tolT;
% Normalize the excess by 0.02 K after the numerical tolerance. The
% dimensional Kelvin margin remains in the separate physical audit.
r.coolant_outlet_passivity_error=max([leftOutletExcess;rightOutletExcess;0],[],'all')/.02;

event=double(run.inputs.cooling_fault_time);eventEnd=event+30;
pre=t>=event-12&t<=event-3;evt=t>=event+6&t<=event+24;post=t>=eventEnd+5&t<=eventEnd+25;
if nnz(pre)<40||nnz(evt)<80||nnz(post)<80,return;end
r.fault_severity=double(run.inputs.cooling_fault_fraction);
baselineFlow=mean([median(c(pre,2)),median(c(post,2))]);eventFlow=median(c(evt,2));
r.event_flow_reduction=max((baselineFlow-eventFlow)/max(baselineFlow,.02),0);
r.fault_flow_fraction_error=0;
r.pump_response=max([median(c(evt,1))-median(c(pre,1)),median(c(evt,1))-.25,0]);
r.event_aux_increase=max((median(c(evt,4))-median(c(pre,4)))/max(median(c(pre,4)),5),0);
maxT=max(temp,[],2);slope=gradient(maxT,t);
r.thermal_margin=318-max(maxT);
netRate=mean((q(:,1:8)-q(:,9:16))/18000,2);
r.thermal_recovery_margin=median(netRate(evt))-median(netRate(post));
r.cooling_response_change=abs(median(sum(q(evt,9:16),2))- ...
    median(sum(q(pre,9:16),2)))/max(abs(median(sum(q(pre,9:16),2))),50);
r.event_physical_response_deficit=max(0,1-max([ ...
    r.cooling_response_change/.08, ...
    abs(median(netRate(evt))-median(netRate(pre)))/.005, ...
    abs(median(slope(evt))-median(slope(pre)))/.005, ...
    r.event_aux_increase/.05]));
if r.fault_severity<=.001
    r.fault_event_deficit=0;
else
    % cooling_fault_fraction is a public severity, not merely a Boolean
    % event flag. Closed-loop compensation may reduce the observed loss,
    % hence the 25% relative tolerance, but a decorative ~3% dip cannot
    % receive full fault-strength credit for a 36--70% declared fault.
    faultTolerance=max(.03,.25*r.fault_severity);
    r.fault_flow_fraction_error=min(max( ...
        abs(r.event_flow_reduction-r.fault_severity)-faultTolerance,0) / ...
        max(r.fault_severity-faultTolerance,.05),1);
    presenceStrength=min(r.event_flow_reduction/ ...
        max(.25*r.fault_severity,.03),1);
    flowStrength=presenceStrength*(1-r.fault_flow_fraction_error);
    physicalStrength=min(max([r.cooling_response_change/.05, ...
        abs(median(netRate(evt))-median(netRate(pre)))/.003, ...
        abs(median(slope(evt))-median(slope(pre)))/.003, ...
        r.event_aux_increase/.05]),1);
    r.fault_event_deficit=max(r.fault_flow_fraction_error, ...
        1-sqrt(max(flowStrength,0)*max(physicalStrength,0)));
end
r.recovery_time=local_recovery(t,slope,eventEnd,median(slope(pre)));
r.valid=all(isfinite([r.peak_temperature r.peak_spread r.min_module_voltage r.min_soc ...
    r.initial_soc_error r.initial_temperature_error ...
    r.aux_energy_Wh r.coolant_outlet_imbalance r.safety_violation r.alarm_mismatch ...
    r.alarm_missed_unsafe r.alarm_false_safe r.cooling_rating_violation ...
    r.pump_command_rating_violation r.flow_rating_violation ...
    r.pressure_rating_violation r.aux_power_rating_violation ...
    r.current_profile_error r.series_voltage_residual r.charge_residual ...
    r.thermal_residual r.electrical_coupling_error r.resistance_dispersion ...
    r.heat_current_correlation r.heat_to_step_resistance_ratio ...
    r.thermal_conductance_dispersion r.total_heat_residual ...
    r.coolant_enthalpy_capacity_error r.coolant_outlet_passivity_error ...
    r.fault_severity ...
    r.max_temperature_offset r.thermal_exchange_direction_error ...
    r.event_flow_reduction r.fault_flow_fraction_error ...
    r.fault_event_deficit r.event_aux_increase ...
    r.pump_response r.thermal_margin r.thermal_recovery_margin r.cooling_response_change ...
    r.event_physical_response_deficit r.recovery_time]));
end

function out=fault_pair_evidence(runs,faultName,noneName)
out=struct('valid',false,'flow_reduction',0,'cooling_reduction',0, ...
    'net_heat_rate_increase',0,'temperature_slope_increase',0, ...
    'auxiliary_increase',0,'pump_command_increase',0, ...
    'fault_severity',0,'flow_fraction_error',1, ...
    'direction_fraction',0,'causal_strength',0,'response_deficit',1, ...
    'active_control_strength',0,'active_control_response_supported',false);
names=string({runs.scenario});
fault=find(names==string(faultName),1);none=find(names==string(noneName),1);
if isempty(fault)||isempty(none)||string(runs(fault).stage)~="simulated"|| ...
        string(runs(none).stage)~="simulated",return;end
pairedFields=["ambient_temperature","initial_soc","discharge_current", ...
    "module_parameter_spread","cooling_fault_time"];
for k=1:numel(pairedFields)
    f=char(pairedFields(k));
    if abs(double(runs(fault).inputs.(f))-double(runs(none).inputs.(f)))>1e-12,return;end
end
if double(runs(fault).inputs.cooling_fault_fraction)<=0|| ...
        abs(double(runs(none).inputs.cooling_fault_fraction))>1e-12,return;end
[tF,thF,okTF]=xp9_series(runs(fault),'thermal_state',10);
[tN,thN,okTN]=xp9_series(runs(none),'thermal_state',10);
[tFC,cF,okCF]=xp9_series(runs(fault),'cooling_state',6);
[tNC,cN,okCN]=xp9_series(runs(none),'cooling_state',6);
[tFQ,qF,okQF]=xp9_series(runs(fault),'thermal_flux',16);
[tNQ,qN,okQN]=xp9_series(runs(none),'thermal_flux',16);
if ~(okTF&&okTN&&okCF&&okCN&&okQF&&okQN),return;end
event=double(runs(fault).inputs.cooling_fault_time);
[t,pair,okPair]=local_align_series( ...
    {tF,tN,tFC,tNC,tFQ,tNQ},{thF,thN,cF,cN,qF,qN}, ...
    [event+6 event+24]);
if ~okPair,return;end
thF=pair{1};thN=pair{2};cF=pair{3};cN=pair{4};qF=pair{5};qN=pair{6};
evt=t>=event+6&t<=event+24;
if nnz(evt)<80,return;end
flowF=median(cF(evt,2));flowN=median(cN(evt,2));
coolF=median(sum(qF(evt,9:16),2));coolN=median(sum(qN(evt,9:16),2));
rateF=median(mean((qF(evt,1:8)-qF(evt,9:16))/18000,2));
rateN=median(mean((qN(evt,1:8)-qN(evt,9:16))/18000,2));
slopeF=median(gradient(max(thF,[],2),t));slopeN=median(gradient(max(thN,[],2),t));
auxF=median(cF(evt,4));auxN=median(cN(evt,4));
pumpF=median(cF(evt,1));pumpN=median(cN(evt,1));
out.flow_reduction=(flowN-flowF)/max(flowN,.02);
out.fault_severity=double(runs(fault).inputs.cooling_fault_fraction);
faultTolerance=max(.03,.25*out.fault_severity);
out.flow_fraction_error=min(max( ...
    abs(out.flow_reduction-out.fault_severity)-faultTolerance,0) / ...
    max(out.fault_severity-faultTolerance,.05),1);
out.cooling_reduction=(coolN-coolF)/max(abs(coolN),50);
out.net_heat_rate_increase=rateF-rateN;
out.temperature_slope_increase=slopeF-slopeN;
out.auxiliary_increase=(auxF-auxN)/max(auxN,5);
out.pump_command_increase=pumpF-pumpN;
directions=[out.flow_reduction>0,out.cooling_reduction>0, ...
    out.net_heat_rate_increase>0,out.temperature_slope_increase>0,out.auxiliary_increase>0];
out.direction_fraction=mean(directions);
presenceStrength=min(max(out.flow_reduction,0)/ ...
    max(.25*out.fault_severity,.03),1);
flowStrength=presenceStrength*(1-out.flow_fraction_error);
physicalStrength=min(max([out.cooling_reduction/.04, ...
    out.net_heat_rate_increase/.003,out.temperature_slope_increase/.003, ...
    out.auxiliary_increase/.05,0]),1);
out.causal_strength=sqrt(flowStrength*physicalStrength);
out.response_deficit=max(out.flow_fraction_error,1-out.causal_strength);
out.active_control_strength=max([max(out.pump_command_increase,0)/.03, ...
    max(out.auxiliary_increase,0)/.08]);
out.active_control_strength=min(out.active_control_strength,1);
out.active_control_response_supported=out.active_control_strength>=.65;
out.valid=true;
end

function [spread,cooling]=shared_pack_evidence(runs,rows)
x=[rows.public_parameter_spread]';re=[rows.resistance_dispersion]';rt=[rows.thermal_conductance_dispersion]';
[eErr,eSlope,eMono]=proportional_spread(x,re);
thermalAssessed=logical([rows.thermal_spread_assessed]');
if nnz(thermalAssessed)>=3&& ...
        max(x(thermalAssessed))-min(x(thermalAssessed))>.005
    [tErr,tSlope,tMono]=proportional_spread(x(thermalAssessed),rt(thermalAssessed));
    thermalEvidenceAvailable=true;
else
    tErr=0;tSlope=NaN;tMono=0;thermalEvidenceAvailable=false;
end
spread=struct('error',max(eErr,tErr),'electrical_slope',eSlope, ...
    'thermal_slope',tSlope,'electrical_monotonic_error',eMono, ...
    'thermal_monotonic_error',tMono,'electrical_residual',eErr, ...
    'thermal_residual',tErr,'thermal_evidence_available',thermalEvidenceAvailable, ...
    'thermal_assessed_scenarios',nnz(thermalAssessed), ...
    'thermal_spread_supported',logical(~thermalEvidenceAvailable|| ...
        (isfinite(tSlope)&&tSlope>0&&tErr<=.42&&tMono<=.25)));

heat=[];outletTransport=[];transportDirection=[];pump=[];flow=[];head=[];aux=[];
flowBase=[];headBase=[];auxBase=[];pumpBase=[];
regulationPump=[];regulationScenarioMedian=[];
for i=1:numel(runs)
    run=runs(i);[t,th,okT]=xp9_series(run,'thermal_state',10);
    [t2,c,okC]=xp9_series(run,'cooling_state',6);[t3,q,okQ]=xp9_series(run,'thermal_flux',16);
    if ~(okT&&okC&&okQ&&isequal(t,t2)&&isequal(t,t3)),continue;end
    amb=double(run.inputs.ambient_temperature);idx=find(t>.5);
    stride=max(1,round(.5/median(diff(t))));idx=idx(1:stride:end);
    oneHeat=sum(q(idx,9:16),2);rise=max(mean(th(idx,9:10),2)-amb,0);
    heat=[heat;oneHeat];outletTransport=[outletTransport;c(idx,2).*rise]; %#ok<AGROW>
    transportDirection=[transportDirection;double(oneHeat>20&max(th(idx,9:10),[],2)<amb-.2)]; %#ok<AGROW>
    pump=[pump;c(idx,1)];flow=[flow;c(idx,2)];head=[head;c(idx,3)];aux=[aux;c(idx,4)]; %#ok<AGROW>
    fault=double(run.inputs.cooling_fault_time);baseIdx=idx(~(t(idx)>=fault&t(idx)<fault+30));
    flowBase=[flowBase;c(baseIdx,2)];headBase=[headBase;c(baseIdx,3)]; %#ok<AGROW>
    auxBase=[auxBase;c(baseIdx,4)];pumpBase=[pumpBase;c(baseIdx,1)]; %#ok<AGROW>
    % Ignore initialization and the imposed hydraulic degradation. Across
    % this broad public operating matrix, a genuinely regulated actuator
    % should not remain at one indistinguishable command in every settled
    % regime. This is deliberately agnostic to PI, bang-bang or feedforward
    % control and to the detailed pump/fault characteristic.
    regulationIdx=idx(t(idx)>=8&~(t(idx)>=fault&t(idx)<fault+30));
    if ~isempty(regulationIdx)
        onePump=c(regulationIdx,1);
        regulationPump=[regulationPump;onePump]; %#ok<AGROW>
        regulationScenarioMedian=[regulationScenarioMedian;median(onePump)]; %#ok<AGROW>
    end
end
transportCorr=positive_correlation(outletTransport,heat);
transportDirectionError=1;if ~isempty(transportDirection),transportDirectionError=mean(transportDirection);end
transportError=max(transportDirectionError,(1-transportCorr)/2);
active=pump>.03;zeroFraction=1;if any(active),zeroFraction=mean(aux(active)<=.01);end
hydraulicPower=flow.*head;hydraulicShortfall=1;
if any(active)
    hydraulicShortfall=max(max(hydraulicPower(active)-.85*aux(active),0)./max(hydraulicPower(active),1));
end
[pumpCorr,pumpAuxActive]=signed_causal_correlation(pumpBase,auxBase,1,120);
[flowCorr,pumpFlowActive]=signed_causal_correlation(pumpBase,flowBase,1,.30);
[headCorr,flowHeadActive]=signed_causal_correlation(flowBase,headBase,.30,100);
[flowAuxCorr,flowAuxActive]=signed_causal_correlation(flowBase,auxBase,.30,120);
% Pump curves may be system curves (positive flow/head association) or
% fixed-speed pump curves (negative association).  Score non-degenerate
% causal coupling and hydraulic energy consistency, not a prescribed sign.
headSpan=0;headMedian=0;
if ~isempty(headBase)
    headSpan=prctile(headBase,95)-prctile(headBase,5);
    carryingFlow=flowBase>.02;
    if any(carryingFlow),headMedian=median(headBase(carryingFlow));end
end
constantHeadCredit=double(pumpFlowActive&&headSpan<=.5&&headMedian>=.5);
headRelationEvidence=max(flowHeadActive*abs(headCorr),constantHeadCredit);
hydraulicError=max([hydraulicShortfall,1-pumpFlowActive*abs(flowCorr), ...
    1-headRelationEvidence]);
auxiliaryError=max([zeroFraction,1-pumpAuxActive*abs(pumpCorr), ...
    1-flowAuxActive*abs(flowAuxCorr)]);
regulationCommandSpan=0;regulationScenarioSpan=0;
if ~isempty(regulationPump)
    regulationCommandSpan=prctile(regulationPump,95)-prctile(regulationPump,5);
end
if numel(regulationScenarioMedian)>=2
    regulationScenarioSpan=max(regulationScenarioMedian)-min(regulationScenarioMedian);
end
activeRegulationSpan=max(regulationCommandSpan,regulationScenarioSpan);
activeRegulationSupported=activeRegulationSpan>.02;
enthalpyCapacityError=max([rows.coolant_enthalpy_capacity_error]);
outletPassivityError=max([rows.coolant_outlet_passivity_error]);
transportError=max([transportError,enthalpyCapacityError,outletPassivityError]);
cooling=struct('transport_error',transportError,'outlet_transport_correlation',transportCorr, ...
    'transport_direction_error',transportDirectionError, ...
    'enthalpy_capacity_error',enthalpyCapacityError, ...
    'outlet_passivity_error',outletPassivityError, ...
    'hydraulic_error',hydraulicError,'hydraulic_power_shortfall',hydraulicShortfall, ...
    'auxiliary_error',auxiliaryError,'aux_zero_fraction',zeroFraction, ...
    'pump_aux_correlation',pumpCorr,'pump_flow_correlation_outside_fault',flowCorr, ...
    'flow_head_correlation_outside_fault',headCorr, ...
    'flow_aux_correlation_outside_fault',flowAuxCorr, ...
    'pump_aux_nondegenerate',pumpAuxActive, ...
    'pump_flow_nondegenerate',pumpFlowActive, ...
    'flow_head_nondegenerate',flowHeadActive, ...
    'flow_aux_nondegenerate',flowAuxActive, ...
    'constant_head_credit',logical(constantHeadCredit), ...
    'active_regulation_supported',logical(activeRegulationSupported), ...
    'active_regulation_span',activeRegulationSpan, ...
    'active_regulation_command_span',regulationCommandSpan, ...
    'active_regulation_scenario_span',regulationScenarioSpan, ...
    'head_span_kPa',headSpan,'head_median_under_flow_kPa',headMedian, ...
    'inferred_flow_head_direction',sign(headCorr));
end

function [err,slope,monotonic]=proportional_spread(x,y)
err=1;slope=NaN;monotonic=1;if numel(x)<3||any(~isfinite(x))||any(~isfinite(y)),return;end
slope=(x'*y)/max(x'*x,eps);residual=sqrt(mean((y-slope*x).^2))/max(sqrt(mean(y.^2)),.01);
[xs,order]=sort(x);ys=y(order); %#ok<ASGLU>
monotonic=sum(max(-diff(ys),0))/max(max(ys)-min(ys),.01);
signError=double(slope<=0);scaleError=max([0,(.20-slope)/.20,(slope-5)/5]);
err=max([residual,monotonic,signError,scaleError]);
end

function [grid,aligned,ok]=local_align_series(times,values,requiredWindow)
% Align independent variable-step simulations on a common legal grid.
ok=false;grid=[];aligned=cell(size(values));
if isempty(times)||numel(times)~=numel(values),return;end
lo=-Inf;hi=Inf;steps=[];
for k=1:numel(times)
    t=double(times{k}(:));v=double(values{k});
    if numel(t)<3||size(v,1)~=numel(t)||any(~isfinite(t))|| ...
            any(~isfinite(v),'all')||any(diff(t)<=0)
        return
    end
    lo=max(lo,t(1));hi=min(hi,t(end));
    steps(end+1)=median(diff(t)); %#ok<AGROW>
end
if ~isempty(requiredWindow)
    lo=max(lo,double(requiredWindow(1)));
    hi=min(hi,double(requiredWindow(2)));
end
step=max(steps);
if ~isfinite(step)||step<=0||hi-lo<2*step,return;end
grid=(lo:step:hi)';
if grid(end)<hi-.25*step,grid(end+1,1)=hi;end
if numel(grid)<3,return;end
for k=1:numel(values)
    aligned{k}=interp1(double(times{k}(:)),double(values{k}),grid,'linear');
    if any(~isfinite(aligned{k}),'all'),return;end
end
ok=true;
end

function c=positive_correlation(x,y)
x=double(x(:));y=double(y(:));c=-1;if numel(x)<20,return;end
x=x-mean(x);y=y-mean(y);den=sqrt(sum(x.^2)*sum(y.^2));if den>eps,c=sum(x.*y)/den;end
c=min(max(c,-1),1);
end

function [c,active]=signed_causal_correlation(x,y,xRating,yRating)
x=double(x(:));y=double(y(:));c=0;active=0;
if numel(x)<20||any(~isfinite(x))||any(~isfinite(y)),return;end
xSpan=prctile(x,95)-prctile(x,5);
ySpan=prctile(y,95)-prctile(y,5);
active=double(xSpan>max(1e-4,2e-3*xRating)&& ...
    ySpan>max(1e-4,2e-3*yRating));
if ~active,return;end
xc=x-mean(x);yc=y-mean(y);den=sqrt(sum(xc.^2)*sum(yc.^2));
if den>eps,c=sum(xc.*yc)/den;end
c=min(max(c,-1),1);
end

function dt=local_recovery(t,slope,eventEnd,baseline)
dt=max(t(end)-eventEnd+1,0);start=find(t>=eventEnd,1);if isempty(start),return;end
window=max(3,round(8/median(diff(t))));good=slope<=baseline+.018;
for k=start:max(start,numel(t)-window+1)
    if all(good(k:k+window-1)),dt=t(k)-eventEnd;return;end
end
end

function r=empty_row()
r=struct('scenario',"",'valid',false,'peak_temperature',NaN,'peak_spread',NaN, ...
    'min_module_voltage',NaN,'min_soc',NaN,'aux_energy_Wh',NaN, ...
    'coolant_outlet_imbalance',NaN,'safety_violation',NaN,'alarm_mismatch',NaN, ...
    'alarm_missed_unsafe',NaN,'alarm_false_safe',NaN,'cooling_rating_violation',NaN, ...
    'pump_command_rating_violation',NaN,'flow_rating_violation',NaN, ...
    'pressure_rating_violation',NaN,'aux_power_rating_violation',NaN, ...
    'initial_soc_error',NaN,'initial_temperature_error',NaN, ...
    'current_profile_error',NaN,'series_voltage_residual',NaN,'charge_residual',NaN, ...
    'thermal_residual',NaN,'electrical_coupling_error',NaN, ...
    'electrical_step_evidence',false, ...
    'heat_current_correlation',NaN,'heat_to_step_resistance_ratio',NaN, ...
    'module_step_resistance',NaN(1,8),'module_heat_resistance',NaN(1,8), ...
    'module_thermal_conductance',NaN(1,8),'resistance_dispersion',NaN, ...
    'thermal_conductance_dispersion',NaN,'thermal_spread_assessed',false, ...
    'max_temperature_offset',NaN,'thermal_exchange_direction_error',NaN, ...
    'public_parameter_spread',NaN, ...
    'total_heat_residual',NaN,'coolant_enthalpy_capacity_error',NaN, ...
    'coolant_outlet_passivity_error',NaN, ...
    'fault_severity',NaN,'event_flow_reduction',NaN, ...
    'fault_flow_fraction_error',NaN, ...
    'fault_event_deficit',NaN,'event_aux_increase',NaN, ...
    'pump_response',NaN,'thermal_margin',NaN,'thermal_recovery_margin',NaN, ...
    'cooling_response_change',NaN, ...
    'event_physical_response_deficit',NaN,'recovery_time',NaN);
end
function out=empty_out()
out=struct('schema',"simuverity.xp9-score.v1",'policy_id',"simuverity-101-v1:p9-xbatt01:scoring", ...
    'formula',"G*100*A^.20*Q^.10*M^.30*R^.20*D^.20", ...
    'score_inputs_valid',false,'diagnostics_valid',false,'G',false, ...
    'gate_reasons',strings(0,1),'A',0,'Q',0,'M',0,'R',0,'D',0,'score',0, ...
    'raw_metrics',struct(),'utility_metrics',struct(),'scenario_rows',struct([]), ...
    'diagnostic_scope',"public SOC initialization, causal nonnegative electro-thermal loss and conservation, resistance-and-heat-transfer parameter spread, total coolant heat-removal ledger closure, per-sample two-branch coolant enthalpy capacity and passive outlet bounds, cooling-fault amplitude consistency with the declared public severity, constant-head or varying-head rated hydraulic feasibility, strategy-neutral alarm coverage, and paired no-fault/fault passive consequence plus active controller response");
end
