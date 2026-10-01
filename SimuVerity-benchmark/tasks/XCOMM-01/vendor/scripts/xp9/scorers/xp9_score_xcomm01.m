function out=xp9_score_xcomm01(runs,spec)
%XP9_SCORE_XCOMM01 Dedicated FMCW echo, detection and reacquisition score.
out=empty_out();convention=select_spectral_convention(runs);
rows=repmat(empty_row(),numel(runs),1);allValid=true;
for i=1:numel(runs)
    rows(i)=measure_run(runs(i),convention);allValid=allValid&&rows(i).valid;
end
suite=interference_suite(rows);rcsProbe=rcs_probe_suite(rows);inputProbe=input_probe_suite(rows);
reportSuite=report_consistency_suite(rows);
suite.rcs_probe=rcsProbe;suite.input_probe=inputProbe;suite.report_consistency=reportSuite;
suite.spectral_convention=convention;
out.score_inputs_valid=allValid&&numel(runs)==1+numel(spec.scenarios);
out.diagnostics_valid=allValid;out.G=out.score_inputs_valid;
if ~out.G
    out.gate_reasons=dependency_gate_reasons(runs);
    if isempty(out.gate_reasons)
        out.gate_reasons="SCENARIO_OR_RADAR_OUTPUT_CONTRACT_INVALID";
    end
end
out.scenario_rows=rows;

if ~isempty(rows)
    n=rows(1);
    qRange=xp9_utility(n.range_error,[0 .18 .45 1.2 3.5 8],[1 1 .94 .72 .25 0]);
    qVelocity=xp9_utility(n.velocity_error,[0 .10 .30 .8 2.4 6],[1 1 .94 .72 .25 0]);
    qCoverage=xp9_utility(n.two_target_report_fraction,[0 .20 .50 .80 .98 1], ...
        [0 .18 .48 .76 .96 1]);
    out.A=xp9_group([qCoverage qRange qVelocity],[.24 .42 .34],false);
    if n.two_target_report_fraction<=0
        out.A=0;
    end

    qImpair=xp9_utility(n.impairment_ratio_error,[0 .08 .18 .38 .75 1.4],[1 1 .94 .72 .25 0]);
    qConfOrder=xp9_utility(reportSuite.confidence_order_typical,[0 .20 .40 .50 .65 .80 1],[0 .12 .45 .68 .90 .98 1]);
    qLockOrder=xp9_utility(reportSuite.lock_order_typical,[0 .20 .40 .50 .65 .80 1],[0 .12 .45 .68 .90 .98 1]);
    qFaOrder=xp9_utility(reportSuite.false_alarm_order_typical,[0 .20 .40 .50 .65 .80 1],[0 .12 .45 .68 .90 .98 1]);
    qConfVariation=xp9_utility(reportSuite.confidence_variation_worst,[0 .002 .01 .04 .15 .50],[0 .15 .45 .72 .94 1]);
    qLockVariation=xp9_utility(reportSuite.lock_variation_worst,[0 .002 .01 .04 .15 .50],[0 .15 .45 .72 .94 1]);
    qFaVariation=xp9_utility(reportSuite.false_alarm_variation_worst,[0 .002 .01 .04 .12 .40],[0 .15 .45 .72 .94 1]);
    qReportVariation=xp9_group([qConfVariation qLockVariation qFaVariation],[.38 .32 .30],true);
    out.Q=xp9_group([qImpair qConfOrder qLockOrder qFaOrder qReportVariation], ...
        [.28 .20 .18 .16 .18],false);

    qTarget=xp9_utility(n.target_spectral_prominence,[0 2 5 15 50 200],[0 .18 .48 .76 .94 1]);
    qOrder=xp9_utility(n.order_violation,[0 .001 .01 .04 .15 .5],[1 1 .94 .74 .30 0]);
    qDetect=xp9_utility(n.interference_detection,[0 .20 .50 .75 .92 1],[0 .15 .45 .72 .93 1]);
    qEvent=xp9_utility(n.event_spectral_evidence,[0 .03 .08 .16 .28 .45],[0 .18 .48 .76 .94 1]);
    qIQRange=xp9_utility(n.iq_detection_range_error,[0 .25 .60 1.5 4 10],[1 1 .94 .72 .25 0]);
    qIQVelocity=xp9_utility(n.iq_detection_velocity_error,[0 .15 .40 1.0 3 7],[1 1 .94 .72 .25 0]);
    qStatus=xp9_utility(n.status_spectral_alignment,[0 .25 .50 .72 .90 1],[0 .15 .45 .72 .93 1]);
    qParity=xp9_utility(n.parity_leakage,[0 .02 .06 .15 .35 .70],[1 1 .94 .72 .25 0]);
    qRcs=xp9_utility(max(rcsProbe.min_log_response,0),[0 .01 .035 .08 .16 .30], ...
        [.15 .30 .52 .75 .93 1]);
    qSnr=xp9_utility(max(inputProbe.snr_log_response,0),[0 .01 .035 .08 .16 .30], ...
        [.15 .30 .52 .75 .93 1]);
    qClutter=xp9_utility(max(inputProbe.clutter_log_response,0),[0 .01 .035 .08 .16 .30], ...
        [.15 .30 .52 .75 .93 1]);
    qInputProbe=xp9_group([qSnr qClutter],[.50 .50],true);
    out.M=xp9_group([qTarget qOrder qDetect qEvent qIQRange qIQVelocity qStatus ...
        qParity qRcs qInputProbe], ...
        [.084 .049 .063 .063 .161 .154 .126 .10 .10 .10],false);
    waveformSupported=qTarget>0;
    reportSupported=n.two_target_report_fraction>0;
    iqReportAligned=qIQRange>0||qIQVelocity>0;
    if ~waveformSupported&&~reportSupported
        % Neither a received two-target waveform nor a two-target report
        % path is present: the complete radar mechanism is absent.
        out.M=0;
    elseif ~waveformSupported||~reportSupported||~iqReportAligned
        % A useful waveform-only or report-only partial implementation is
        % not a technical failure.  Preserve its evidence, but cap the
        % mechanism group because the public waveform-to-report chain is
        % incomplete or causally inconsistent.
        out.M=min(out.M,.25);
    end
else
    out.A=0;out.Q=0;out.M=0;
end

names=string({rows.scenario});primary=~(startsWith(names,"rcs_")|startsWith(names,"snr_")| ...
    startsWith(names,"clutter_")|startsWith(names,"interference_probe_"));
primaryRows=rows(primary);rq=zeros(numel(primaryRows),1);dq=zeros(numel(primaryRows),1);
for i=1:numel(primaryRows)
    r=primaryRows(i);
    qr=xp9_utility(r.range_error,[0 .30 .75 1.8 5 11],[1 1 .93 .68 .22 0]);
    qv=xp9_utility(r.velocity_error,[0 .18 .50 1.3 3.8 8],[1 1 .93 .68 .22 0]);
    qir=xp9_utility(r.iq_detection_range_error,[0 .35 .85 2.0 5 12],[1 1 .93 .68 .22 0]);
    qiv=xp9_utility(r.iq_detection_velocity_error,[0 .22 .55 1.4 3.8 9],[1 1 .93 .68 .22 0]);
    rq(i)=xp9_group([qr qv qir qiv],[.28 .25 .25 .22],true);
    qRec=xp9_utility(r.recovery_time,[0 .004 .010 .022 .045 .09],[1 1 .93 .70 .25 0]);
    qDrop=xp9_utility(r.event_signature,[0 .05 .12 .25 .45 .75],[.18 .38 .68 .92 1 1]);
    qEventRange=xp9_utility(r.event_range_error,[0 .35 .85 2 5 12],[1 1 .93 .68 .22 0]);
    qEventVelocity=xp9_utility(r.event_velocity_error,[0 .22 .55 1.4 3.8 9],[1 1 .93 .68 .22 0]);
    qContinuity=xp9_group([qEventRange qEventVelocity],[.55 .45],true);
    qResponse=max(qDrop,qContinuity);
    qDetect=xp9_utility(r.interference_detection,[0 .20 .50 .75 .92 1],[0 .15 .45 .72 .93 1]);
    qSpecific=xp9_utility(r.interference_false_positive,[0 .005 .02 .06 .16 .40],[1 1 .93 .70 .25 0]);
    qWave=xp9_utility(r.event_spectral_evidence,[0 .03 .08 .16 .28 .45],[0 .18 .48 .76 .94 1]);
    qRatio=xp9_utility(r.event_ratio_error,[0 .10 .25 .50 .90 1.5],[1 1 .94 .72 .25 0]);
    qAlign=xp9_utility(r.status_spectral_alignment,[0 .25 .50 .72 .90 1],[0 .15 .45 .72 .93 1]);
    dq(i)=xp9_group([qRec qResponse qDetect qSpecific qWave qRatio qAlign], ...
        [.25 .15 .10 .10 .12 .13 .15],true);
end
if isempty(rq)
    out.R=0;out.D=0;
else
    out.R=xp9_tail(rq);
    qMono=xp9_utility(suite.event_monotonic_fraction,[0 .25 .50 .75 .99 1],[0 .12 .42 .72 .94 1]);
    qScale=xp9_utility(suite.event_scale_residual,[0 .08 .18 .35 .60 1],[1 1 .94 .72 .25 0]);
    qSuite=xp9_group([qMono qScale],[.55 .45],true);
    out.D=xp9_group([xp9_tail(dq) qSuite],[.75 .25],false);
    if ~any([primaryRows.event_spectral_evidence]>0)
        out.D=0;
    end
end
out.utility_metrics=struct('nominal_accuracy',out.A,'nominal_quality',out.Q, ...
    'mechanism',out.M,'spectral_convention',convention, ...
    'rcs_causal_probe',rcsProbe,'isolated_input_probe',inputProbe, ...
    'strategy_neutral_report_consistency',reportSuite, ...
    'worst_range',out.R,'worst_dynamic',out.D);
out.raw_metrics=rows;w=spec.groups.weights;
out.cross_scenario_metrics=suite;
out.score=xp9_total(out.G,[out.A out.Q out.M out.R out.D],[w.A w.Q w.M w.R w.D]);
end

function r=measure_run(run,convention)
r=empty_row();r.scenario=string(run.scenario);
if string(run.stage)~="simulated",return;end
[t,b,okB]=xp9_series(run,'beat_signal',2);
[t2,d,okD]=xp9_series(run,'detections',6);
[t3,s,okS]=xp9_series(run,'receiver_status',3);
if ~(okB&&okD&&okS&&isequal(t,t2)&&isequal(t,t3)),return;end
% Finite but physically wrong range reports are accuracy failures, not an
% unreadable output contract.  Confidence and receiver-status channels are
% explicitly normalized and remain binding interface domains.
if any(abs(b)>100,'all')||any(abs(d(:,[1 4]))>300,'all')|| ...
        any(abs(d(:,[2 5]))>100,'all')||any(d(:,[3 6])<-.001,'all')|| ...
        any(d(:,[3 6])>1.001,'all')||any(s<-.001,'all')||any(s>1.001,'all')
    return
end
event=double(run.inputs.interference_time);dur=double(run.inputs.interference_duration);eventEnd=event+dur;
tail=t>=max(.125,eventEnd+.022);pre=t>=event-.012&t<=event-.002;
evt=t>=event+.001&t<=eventEnd-.001;outside=t>.008&~(t>=event-.001&t<=eventEnd+.003);
if nnz(tail)<1000||nnz(pre)<300||nnz(evt)<300||nnz(outside)<4000,return;end
r.range_error=max(median(abs(d(tail,1)-double(run.inputs.target1_range))), ...
    median(abs(d(tail,4)-double(run.inputs.target2_range))));
r.velocity_error=max(median(abs(d(tail,2)-double(run.inputs.target1_velocity))), ...
    median(abs(d(tail,5)-double(run.inputs.target2_velocity))));
r.two_target_report_fraction=mean(d(tail,1)>.1&d(tail,4)>d(tail,1)+.5);
r.min_confidence=min(median(d(tail,3)),median(d(tail,6)));
r.reported_lock=median(s(tail,1));r.false_alarm=median(s(tail,2));
r.interference_detection=mean(s(evt,3)>.5);
r.interference_false_positive=mean(s(outside,3)>.5);
obs=complex(b(:,1),b(:,2));reported=[median(d(tail,1)) median(d(tail,2)) median(d(tail,4)) median(d(tail,5))];
[r.target_spectral_prominence,r.impairment_ratio_error,r.event_spectral_evidence, ...
    r.event_ratio_error,r.iq_detection_range_error,r.iq_detection_velocity_error, ...
    r.status_spectral_alignment,r.target_strength_balance,r.independent_quality, ...
    r.target1_peak_amplitude,r.target2_peak_amplitude, ...
    r.independent_false_alarm_risk,r.out_of_target_peak_ratio,r.parity_leakage, ...
    r.normalized_noise_floor,r.normalized_stationary_clutter]= ...
    spectral_evidence(t,obs,s(:,3),reported,run.inputs,event,eventEnd,convention);
r.interference_ratio=double(run.inputs.interference_ratio);
[iqQualitySeries,okTimeline]=independent_iq_quality_series(t,obs,run.inputs,convention);
rangeErrorSeries=max(abs(d(:,1)-double(run.inputs.target1_range)), ...
    abs(d(:,4)-double(run.inputs.target2_range)));
velocityErrorSeries=max(abs(d(:,2)-double(run.inputs.target1_velocity)), ...
    abs(d(:,5)-double(run.inputs.target2_velocity)));
detectionQualitySeries=1./(1+(rangeErrorSeries/1.5).^2+(velocityErrorSeries/1.0).^2);
    objectiveQuality=sqrt(max(detectionQualitySeries,0).*max(iqQualitySeries,0));
    reportRows=t>.004&okTimeline;
    % Do not count the unlocked/start-up 0/0 placeholder as a target-order
    % error.  Ordering is meaningful only after the independent I/Q path is
    % valid and the reported detections themselves are accurate.  The I/Q
    % cutoff is scenario-relative so long-range/high-Doppler cases are not
    % rejected merely because their absolute spectral scale is lower.
    iqOrderThreshold=local_quantile(iqQualitySeries(reportRows),.60);
    orderRows=reportRows&detectionQualitySeries>=.80& ...
        iqQualitySeries>=iqOrderThreshold;
    if nnz(orderRows)>=200
        r.order_violation=mean(d(orderRows,1)>=d(orderRows,4));
    else
        r.order_violation=1;
    end
[r.confidence_order_consistency,r.confidence_variation]= ...
    directional_report_consistency(min(d(reportRows,3),d(reportRows,6)),objectiveQuality(reportRows));
[r.lock_order_consistency,r.lock_variation]= ...
    directional_report_consistency(s(reportRows,1),objectiveQuality(reportRows));
[r.false_alarm_order_consistency,r.false_alarm_variation]= ...
    directional_report_consistency(s(reportRows,2),1-objectiveQuality(reportRows));
preConf=min(median(d(pre,3)),median(d(pre,6)));evtConf=min(d(evt,[3 6]),[],'all');
r.event_signature=max(0,preConf-evtConf);
r.event_range_error=max(median(abs(d(evt,1)-double(run.inputs.target1_range))), ...
    median(abs(d(evt,4)-double(run.inputs.target2_range))));
r.event_velocity_error=max(median(abs(d(evt,2)-double(run.inputs.target1_velocity))), ...
    median(abs(d(evt,5)-double(run.inputs.target2_velocity))));
    r.event_min_confidence=min(median(d(evt,3)),median(d(evt,6)));
    [r.recovery_time,r.recovery_objective_ratio,r.recovery_report_direction, ...
        r.recovery_report_variation,r.recovery_objective_fraction, ...
        r.recovery_report_fraction,r.recovery_joint_fraction]= ...
        recovery_time(t,d,s,event,eventEnd, ...
        objectiveQuality,okTimeline,run.inputs);
r.valid=all(isfinite([r.range_error r.velocity_error r.two_target_report_fraction ...
    r.min_confidence r.false_alarm ...
    r.order_violation r.interference_detection r.interference_false_positive ...
    r.target_spectral_prominence r.impairment_ratio_error r.event_spectral_evidence ...
    r.event_ratio_error r.iq_detection_range_error r.iq_detection_velocity_error ...
    r.status_spectral_alignment r.target_strength_balance r.independent_quality ...
    r.target1_peak_amplitude r.target2_peak_amplitude ...
    r.parity_leakage r.normalized_noise_floor r.normalized_stationary_clutter ...
    r.independent_false_alarm_risk r.out_of_target_peak_ratio r.reported_lock ...
    r.confidence_order_consistency r.lock_order_consistency r.false_alarm_order_consistency ...
    r.confidence_variation r.lock_variation r.false_alarm_variation ...
    r.interference_ratio r.event_signature r.event_range_error r.event_velocity_error ...
    r.event_min_confidence r.recovery_time r.recovery_objective_ratio ...
    r.recovery_report_direction r.recovery_report_variation ...
    r.recovery_objective_fraction r.recovery_report_fraction ...
    r.recovery_joint_fraction]));
end

function [prominence,ratioError,eventEvidence,eventRatioError,iqRangeError,iqVelocityError, ...
        statusAlignment,strengthBalance,independentQuality,target1Amplitude,target2Amplitude, ...
        falseAlarmRisk,outsidePeakRatio,parityLeakage,normalizedNoiseFloor, ...
        normalizedStationaryClutter]= ...
        spectral_evidence(t,z,status,reported,in,event,eventEnd,convention)
prominence=NaN;ratioError=NaN;eventEvidence=NaN;eventRatioError=NaN;
iqRangeError=NaN;iqVelocityError=NaN;statusAlignment=NaN;strengthBalance=NaN;
independentQuality=NaN;target1Amplitude=NaN;target2Amplitude=NaN;
falseAlarmRisk=NaN;outsidePeakRatio=NaN;parityLeakage=NaN;
normalizedNoiseFloor=NaN;normalizedStationaryClutter=NaN;
dt=median(diff(t));Fs=1/dt;N=round(.004/dt);
offset=max(0,min(N-1,round(convention.sample_offset)));
nChirp=floor((numel(t)-offset)/N);
if N<32||nChirp<8||~convention.valid,return;end
window=(.5-.5*cos(2*pi*(0:N-1)/(N-1)))';spectra=zeros(nChirp,N);mid=zeros(nChirp,1);statusChirp=zeros(nChirp,1);
for c=1:nChirp
    idx=offset+(c-1)*N+(1:N);F=fft(z(idx).*window)/sum(window);
    spectra(c,:)=abs(F(:)).^2;mid(c)=mean(t(idx));statusChirp(c)=median(status(idx));
end
parity=mod((1:nChirp)',2);f=(0:N-1)*Fs/N;f(f>Fs/2)=f(f>Fs/2)-Fs;
c0=299792458;fc=77e9;slope=3.5e10;
fb1=2*slope*double(in.target1_range)/c0;fd1=2*double(in.target1_velocity)*fc/c0;
fb2=2*slope*double(in.target2_range)/c0;fd2=2*double(in.target2_velocity)*fc/c0;
upCenters=convention.orientation*[fb1+fd1,fb2+fd2];
downCenters=convention.orientation*[-fb1+fd1,-fb2+fd2];
baseRows=mid>.008&~(mid>=event-.004&mid<=eventEnd+.004);
eventRows=mid>=event+.002&mid<=eventEnd-.002;
upRows=baseRows&parity==convention.up_parity;downRows=baseRows&parity~=convention.up_parity;
if nnz(upRows)<2||nnz(downRows)<2||nnz(eventRows)<1,return;end
upSpectrum=mean(spectra(upRows,:),1);downSpectrum=mean(spectra(downRows,:),1);
m1u=component_mask(f,upCenters,1,900);m2u=component_mask(f,upCenters,2,900);
m1d=component_mask(f,downCenters,1,900);m2d=component_mask(f,downCenters,2,900);
targetMask=m1u|m2u|m1d|m2d;
if ~all([any(m1u),any(m2u),any(m1d),any(m2d),any(~targetMask)]),return;end
[f1u,p1u]=spectral_peak(upSpectrum,f,m1u);[f2u,p2u]=spectral_peak(upSpectrum,f,m2u);
[f1d,p1d]=spectral_peak(downSpectrum,f,m1d);[f2d,p2d]=spectral_peak(downSpectrum,f,m2d);
[~,l1u]=spectral_peak(downSpectrum,f,m1u);[~,l2u]=spectral_peak(downSpectrum,f,m2u);
[~,l1d]=spectral_peak(upSpectrum,f,m1d);[~,l2d]=spectral_peak(upSpectrum,f,m2d);
correct=[p1u p1d p2u p2d];leak=[l1u l1d l2u l2d];
parityLeakage=median(sqrt(max(leak,eps)./max(correct,eps)));
f1u=convention.orientation*f1u;f1d=convention.orientation*f1d;
f2u=convention.orientation*f2u;f2d=convention.orientation*f2d;
iqRange=[abs(f1u-f1d) abs(f2u-f2d)]*c0/(4*slope);
iqVelocity=[f1u+f1d f2u+f2d]*c0/(4*fc);
iqRangeError=max(abs(iqRange-reported([1 3])));
iqVelocityError=max(abs(iqVelocity-reported([2 4])));
baseSpectrum=.5*(upSpectrum+downSpectrum);noiseFloor=max(median(baseSpectrum(~targetMask)),eps);
prominence=min(correct)/noiseFloor;
outsidePeakRatio=sqrt(max(baseSpectrum(~targetMask))/max(min(correct),eps));
targetEnergy=max(sum(baseSpectrum(targetMask)),eps);
impairmentRatio=sqrt(sum(baseSpectrum(~targetMask))/targetEnergy);
expectedRatio=hypot(double(in.clutter_ratio),10^(-double(in.snr_db)/20));
ratioError=abs(log(max(impairmentRatio,eps)/max(expectedRatio,eps)));
evidence=[];
for p=0:1
    br=baseRows&parity==p;er=eventRows&parity==p;
    if any(br)&&any(er)
        bp=median(spectra(br,:),1);ep=median(spectra(er,:),1);
        evidence(end+1)=sqrt(sum(max(ep-bp,0))/max(sum(bp(targetMask)),eps)); %#ok<AGROW>
    end
end
if isempty(evidence),return;else,eventEvidence=median(evidence);end
eventRatioError=abs(log(max(eventEvidence,eps)/max(double(in.interference_ratio),eps)));
statusAlignment=status_spectral_alignment(spectra,statusChirp,targetMask,mid,parity);
target1Amplitude=(max(p1u,eps)*max(p1d,eps))^.25;
target2Amplitude=(max(p2u,eps)*max(p2d,eps))^.25;
strengthBalance=min(target1Amplitude,target2Amplitude)/max(target1Amplitude,target2Amplitude);
targetScale=max(sqrt(target1Amplitude*target2Amplitude),eps);
normalizedNoiseFloor=sqrt(noiseFloor)/targetScale;
clutterAmplitude=stationary_clutter_amplitude(upSpectrum,downSpectrum,f,targetMask);
normalizedStationaryClutter=clutterAmplitude/targetScale;
peakQuality=min(max(log10(max(prominence,1))/4,0),1);
detectionQuality=exp(-(iqRangeError/1.5)^2-(iqVelocityError/1.0)^2);
independentQuality=sqrt(peakQuality*detectionQuality);
outsideSeverity=min(max((outsidePeakRatio-.35)/1.5,0),1);
falseAlarmRisk=(1-detectionQuality)*(.55+.45*outsideSeverity);
end

function convention=select_spectral_convention(runs)
convention=struct('valid',false,'orientation',1,'up_parity',0, ...
    'sample_offset',0,'selection_score',-Inf);
dt=NaN;
for k=1:numel(runs)
    [t,~,ok]=xp9_series(runs(k),'beat_signal',2);
    if ok&&numel(t)>32,dt=median(diff(t));break;end
end
if ~isfinite(dt),return;end
N=round(.004/dt);if N<32,return;end
coarseStep=max(1,round(N/10));coarse=unique([0:coarseStep:N-1,N-1]);
convention=best_global_convention(runs,coarse,convention);
if ~convention.valid,return;end
refineStep=max(1,round(coarseStep/20));
refine=max(0,convention.sample_offset-coarseStep):refineStep: ...
    min(N-1,convention.sample_offset+coarseStep);
convention=best_global_convention(runs,unique(refine),convention);
finalOffsets=max(0,convention.sample_offset-refineStep): ...
    min(N-1,convention.sample_offset+refineStep);
convention=best_global_convention(runs,unique(finalOffsets),convention);
end

function bestConvention=best_global_convention(runs,offsets,seed)
bestConvention=seed;orientations=[1 -1];
names=string({runs.scenario});anchors=~(startsWith(names,"rcs_")| ...
    startsWith(names,"snr_")|startsWith(names,"clutter_"));
anchorIndex=find(anchors);if isempty(anchorIndex),anchorIndex=1:numel(runs);end
for offset=offsets
    for oi=1:2
        for pi=1:2
            candidate=struct('valid',true,'orientation',orientations(oi), ...
                'up_parity',pi-1,'sample_offset',offset,'selection_score',-Inf);
            values=[];
            for kk=1:numel(anchorIndex)
                run=runs(anchorIndex(kk));[t,b,okB]=xp9_series(run,'beat_signal',2);
                [t2,s,okS]=xp9_series(run,'receiver_status',3);
                if ~(okB&&okS&&isequal(t,t2)),continue;end
                event=double(run.inputs.interference_time);
                eventEnd=event+double(run.inputs.interference_duration);
                z=complex(b(:,1),b(:,2));reported=[double(run.inputs.target1_range), ...
                    double(run.inputs.target1_velocity),double(run.inputs.target2_range), ...
                    double(run.inputs.target2_velocity)];
                [prom,~,~,~,~,~,~,~,~,~,~,~,~,leak]= ...
                    spectral_evidence(t,z,s(:,3),reported,run.inputs,event,eventEnd,candidate);
                if isfinite(prom)&&isfinite(leak)
                    values(end+1)=log10(max(prom,1))-2*log1p(4*leak); %#ok<AGROW>
                end
            end
            if ~isempty(values)
                candidate.selection_score=median(values);
                if candidate.selection_score>bestConvention.selection_score
                    bestConvention=candidate;
                end
            end
        end
    end
end
end

function amplitude=stationary_clutter_amplitude(upSpectrum,downSpectrum,f,targetMask)
amplitude=0;positive=find(f>300&f<.45*max(abs(f))&~targetMask);
for k=1:numel(positive)
    ip=positive(k);[~,in]=min(abs(f+f(ip)));
    if targetMask(in),continue;end
    a=(max(upSpectrum(ip),eps)*max(downSpectrum(in),eps))^.25;
    b=(max(upSpectrum(in),eps)*max(downSpectrum(ip),eps))^.25;
    amplitude=max([amplitude,a,b]);
end
end

function [quality,valid]=independent_iq_quality_series(t,z,in,convention)
quality=NaN(size(t));valid=false(size(t));
dt=median(diff(t));Fs=1/dt;N=round(.004/dt);
if N<32||~convention.valid,return;end
offset=max(0,min(N-1,round(convention.sample_offset)));
nChirp=floor((numel(t)-offset)/N);if nChirp<4,return;end
window=(.5-.5*cos(2*pi*(0:N-1)/(N-1)))';
f=(0:N-1)*Fs/N;f(f>Fs/2)=f(f>Fs/2)-Fs;
c0=299792458;fc=77e9;slope=3.5e10;
fb1=2*slope*double(in.target1_range)/c0;fd1=2*double(in.target1_velocity)*fc/c0;
fb2=2*slope*double(in.target2_range)/c0;fd2=2*double(in.target2_velocity)*fc/c0;
upCenters=convention.orientation*[fb1+fd1,fb2+fd2];
downCenters=convention.orientation*[-fb1+fd1,-fb2+fd2];
q=zeros(nChirp,1);
for c=1:nChirp
    idx=offset+(c-1)*N+(1:N);power=abs(fft(z(idx).*window)/sum(window)).^2;
    if mod(c,2)==convention.up_parity,centers=upCenters;else,centers=downCenters;end
    targetMask=component_mask(f,centers,1,900)|component_mask(f,centers,2,900);
    targetPower=sum(power(targetMask));outsidePower=sum(power(~targetMask));
    q(c)=1/(1+sqrt(max(outsidePower,0)/max(targetPower,eps)));
    quality(idx)=q(c);valid(idx)=true;
end
first=find(valid,1,'first');last=find(valid,1,'last');
if ~isempty(first)
    quality(1:first-1)=q(1);quality(last+1:end)=q(end);valid(:)=true;
end
end

function [agreement,variation]=directional_report_consistency(report,evidence)
agreement=0;variation=0;report=double(report(:));evidence=double(evidence(:));
keep=isfinite(report)&isfinite(evidence);report=report(keep);evidence=evidence(keep);
if numel(report)<40,return;end
variation=max(local_quantile(report,.99)-local_quantile(report,.01),0);
elo=local_quantile(evidence,.25);ehi=local_quantile(evidence,.75);
low=evidence<=elo;high=evidence>=ehi;
if ~any(low)||~any(high)||ehi-elo<=1e-8||variation<=1e-8,return;end
direction=median(report(high))-median(report(low));
normalizedDirection=max(min(direction/max(variation,eps),1),-1);
% A flat ordering is neutral (0.5), not automatically wrong. Constant reports
% are still rejected above through zero variation; only an actual inversion is
% scored below neutral. This accepts binary and continuous reporting policies.
agreement=.5+.5*normalizedDirection;
end

function mask=component_mask(f,centers,k,tolerance)
distance=abs(centers(:)-f(:)');[~,nearest]=min(distance,[],1);
mask=nearest==k&distance(k,:)<=tolerance;
end

function [fp,pp]=spectral_peak(power,f,mask)
idx=find(mask);[pp,k]=max(power(idx));k=idx(k);df=abs(f(2)-f(1));delta=0;
if k>1&&k<numel(power)
    yl=log(max(power(k-1),eps));yc=log(max(power(k),eps));yr=log(max(power(k+1),eps));den=yl-2*yc+yr;
    if abs(den)>1e-12,delta=max(min(.5*(yl-yr)/den,.5),-.5);end
end
fp=f(k)+delta*df;
end

function score=status_spectral_alignment(spectra,status,targetMask,mid,parity)
usable=mid>.008;spectra=spectra(usable,:);status=status(usable);parity=parity(usable);n=size(spectra,1);
a=zeros(n,1);
for p=0:1
    rows=parity==p;base=median(spectra(rows,:),1);den=max(sum(base(targetMask)),eps);
    idx=find(rows);for k=1:numel(idx),a(idx(k))=sqrt(sum(max(spectra(idx(k),:)-base,0))/den);end
end
center=median(a);spread=median(abs(a-center));anomaly=a>center+max(4*spread,.05);reported=status>.5;
if ~any(anomaly)||all(anomaly),score=0;return;end
score=0;
for lag=0:min(2,n-1)
    truth=anomaly(1:n-lag);pred=reported(1+lag:n);
    tp=sum(truth&pred);fn=sum(truth&~pred);tn=sum(~truth&~pred);fp=sum(~truth&pred);
    sensitivity=tp/max(tp+fn,1);specificity=tn/max(tn+fp,1);
    score=max(score,sqrt(sensitivity*specificity));
end
end

function s=interference_suite(rows)
s=struct('event_monotonic_fraction',0,'event_scale_residual',Inf);
if isempty(rows)||any(~[rows.valid]),return;end
names=string({rows.scenario});lo=find(names=="interference_probe_low",1);
hi=find(names=="interference_probe_high",1);
if isempty(lo)||isempty(hi),return;end
rows=rows([lo hi]);
x=[rows.interference_ratio]';y=[rows.event_spectral_evidence]';
if any(~isfinite([x;y]))||any(x<=0),return;end
ok=0;total=0;
for i=1:numel(x)-1
    for j=i+1:numel(x)
        if abs(x(i)-x(j))>.015,total=total+1;ok=ok+double((x(i)-x(j))*(y(i)-y(j))>0);end
    end
end
s.event_monotonic_fraction=ok/max(total,1);b=sum(x.*y)/max(sum(x.^2),eps);
s.event_scale_residual=rms(y-b*x)/max(rms(y),eps);
end
function s=rcs_probe_suite(rows)
s=struct('valid',false,'target1_log_response',-Inf,'target2_log_response',-Inf, ...
    'min_log_response',-Inf,'target1_raw_growth',NaN,'target2_raw_growth',NaN, ...
    'direction_fraction',0);
if isempty(rows)||any(~[rows.valid]),return;end
names=string({rows.scenario});i1l=find(names=="rcs_target1_low",1);i1h=find(names=="rcs_target1_high",1);
i2l=find(names=="rcs_target2_low",1);i2h=find(names=="rcs_target2_high",1);
if any(cellfun(@isempty,{i1l,i1h,i2l,i2h})),return;end
a1l=max(rows(i1l).target1_peak_amplitude,eps);c1l=max(rows(i1l).target2_peak_amplitude,eps);
a1h=max(rows(i1h).target1_peak_amplitude,eps);c1h=max(rows(i1h).target2_peak_amplitude,eps);
a2l=max(rows(i2l).target2_peak_amplitude,eps);c2l=max(rows(i2l).target1_peak_amplitude,eps);
a2h=max(rows(i2h).target2_peak_amplitude,eps);c2h=max(rows(i2h).target1_peak_amplitude,eps);
s.target1_log_response=log((a1h/c1h)/(a1l/c1l));
s.target2_log_response=log((a2h/c2h)/(a2l/c2l));
s.min_log_response=min(s.target1_log_response,s.target2_log_response);
s.target1_raw_growth=a1h/a1l;s.target2_raw_growth=a2h/a2l;
s.direction_fraction=mean([s.target1_log_response>0,s.target2_log_response>0]);
s.valid=all(isfinite([s.target1_log_response,s.target2_log_response])) ...
    &&s.target1_raw_growth>0&&s.target2_raw_growth>0;
end
function s=input_probe_suite(rows)
s=struct('valid',false,'snr_log_response',-Inf,'clutter_log_response',-Inf, ...
    'min_log_response',-Inf,'snr_noise_ratio',NaN,'clutter_amplitude_ratio',NaN, ...
    'direction_fraction',0);
if isempty(rows)||any(~[rows.valid]),return;end
names=string({rows.scenario});sl=find(names=="snr_probe_low",1);sh=find(names=="snr_probe_high",1);
cl=find(names=="clutter_probe_low",1);ch=find(names=="clutter_probe_high",1);
if any(cellfun(@isempty,{sl,sh,cl,ch})),return;end
s.snr_noise_ratio=max(rows(sl).normalized_noise_floor,eps)/max(rows(sh).normalized_noise_floor,eps);
s.clutter_amplitude_ratio=max(rows(ch).normalized_stationary_clutter,eps)/ ...
    max(rows(cl).normalized_stationary_clutter,eps);
s.snr_log_response=log(s.snr_noise_ratio);s.clutter_log_response=log(s.clutter_amplitude_ratio);
s.min_log_response=min(s.snr_log_response,s.clutter_log_response);
s.direction_fraction=mean([s.snr_log_response>0,s.clutter_log_response>0]);
s.valid=all(isfinite([s.snr_log_response,s.clutter_log_response]));
end
function s=report_consistency_suite(rows)
s=struct('confidence_order_typical',0,'lock_order_typical',0, ...
    'false_alarm_order_typical',0,'confidence_variation_worst',0, ...
    'lock_variation_worst',0,'false_alarm_variation_worst',0);
if isempty(rows)||any(~[rows.valid]),return;end
names=string({rows.scenario});primary=~(startsWith(names,"rcs_")| ...
    startsWith(names,"snr_")|startsWith(names,"clutter_")| ...
    startsWith(names,"interference_probe_"));
primaryRows=rows(primary);if isempty(primaryRows),primaryRows=rows;end
s.confidence_order_typical=median([primaryRows.confidence_order_consistency]);
s.lock_order_typical=median([primaryRows.lock_order_consistency]);
s.false_alarm_order_typical=median([primaryRows.false_alarm_order_consistency]);
s.confidence_variation_worst=min([primaryRows.confidence_variation]);
s.lock_variation_worst=min([primaryRows.lock_variation]);
s.false_alarm_variation_worst=min([primaryRows.false_alarm_variation]);
end
function [dt,objectiveRatio,reportDirection,reportVariation, ...
        objectiveFraction,reportFraction,jointFraction]= ...
        recovery_time(t,d,s,eventStart,eventEnd,objectiveQuality,validTimeline,in)
dt=max(t(end)-eventEnd,0)+.05;objectiveRatio=0;reportDirection=0;reportVariation=0;
objectiveFraction=0;reportFraction=0;jointFraction=0;
start=find(t>=eventEnd,1);if isempty(start),return;end
pre=t>=eventStart-.012&t<=eventStart-.002&validTimeline;
evt=t>=eventStart+.001&t<=eventEnd-.001&validTimeline;
usable=t>.004&validTimeline;
if nnz(pre)<100||nnz(evt)<100||nnz(usable)<500,return;end
preQuality=median(objectiveQuality(pre));
% Recovery is relative to the receiver's own valid pre-event baseline.  An
% absolute confidence/lock or spectral-quality floor would prescribe an
% implementation strategy and unfairly reject valid long-range receivers.
qualityTarget=max(.85*preQuality,eps);
er=max(abs(d(:,1)-double(in.target1_range)),abs(d(:,4)-double(in.target2_range)));
ev=max(abs(d(:,2)-double(in.target1_velocity)),abs(d(:,5)-double(in.target2_velocity)));
objectiveGood=validTimeline&er<=1.5&ev<=1.0&objectiveQuality>=qualityTarget;

reports=[min(d(:,3),d(:,6)) s(:,1)];reportGood=false(size(t));responsive=false;
for j=1:size(reports,2)
    report=reports(:,j);[agreement,variation]=directional_report_consistency( ...
        report(usable),objectiveQuality(usable));
    reportDirection=max(reportDirection,agreement);reportVariation=max(reportVariation,variation);
    preLevel=median(report(pre));eventLevel=median(report(evt));drop=preLevel-eventLevel;
    if variation>.002&&agreement>=.48&&drop>max(.01,.05*variation)
        % Calibration-free recovery: the report must move back in the same
        % direction as objective I/Q plus detection quality, but no absolute
        % confidence or lock value is prescribed.
        reportGood=reportGood|(report>=eventLevel+.45*drop);
        responsive=true;
    end
end
post=t>=eventEnd&validTimeline;
if any(post),objectiveRatio=local_quantile(objectiveQuality(post),.90)/max(preQuality,eps);end
objectiveFraction=mean(objectiveGood(post));reportFraction=mean(reportGood(post));
if ~responsive,return;end
window=max(5,round(.0025/median(diff(t))));good=objectiveGood&reportGood;
jointFraction=mean(good(post));
for k=start:max(start,numel(t)-window+1)
    w=k:k+window-1;validW=validTimeline(w);
    % A chirp/block receiver updates detections discretely.  Judge a complete
    % short window by its robust central behaviour rather than demanding that
    % every sample cross the same instant threshold.
    objectiveWindow=mean(validW)>=.90&&median(er(w(validW)))<=1.5&& ...
        median(ev(w(validW)))<=1.0&&median(objectiveQuality(w(validW)))>=qualityTarget;
    reportWindow=mean(reportGood(w(validW)))>=.80;
    if objectiveWindow&&reportWindow
        dt=t(k)-eventEnd;
        objectiveRatio=median(objectiveQuality(w(validW)))/max(preQuality,eps);
        return
    end
end
end
function q=local_quantile(x,p)
x=sort(double(x(:)));n=numel(x);q=x(max(1,min(n,ceil(p*n))));
end
function r=empty_row()
r=struct('scenario',"",'valid',false,'range_error',NaN,'velocity_error',NaN, ...
    'two_target_report_fraction',NaN,'min_confidence',NaN, ...
    'false_alarm',NaN,'order_violation',NaN, ...
    'interference_detection',NaN,'interference_false_positive',NaN, ...
    'target_spectral_prominence',NaN,'impairment_ratio_error',NaN,'event_spectral_evidence',NaN, ...
    'event_ratio_error',NaN,'iq_detection_range_error',NaN,'iq_detection_velocity_error',NaN, ...
    'status_spectral_alignment',NaN,'target_strength_balance',NaN, ...
    'target1_peak_amplitude',NaN,'target2_peak_amplitude',NaN, ...
    'parity_leakage',NaN,'normalized_noise_floor',NaN, ...
    'normalized_stationary_clutter',NaN, ...
    'independent_quality',NaN,'independent_false_alarm_risk',NaN, ...
    'out_of_target_peak_ratio',NaN,'reported_lock',NaN, ...
    'confidence_order_consistency',NaN,'lock_order_consistency',NaN, ...
    'false_alarm_order_consistency',NaN,'confidence_variation',NaN, ...
    'lock_variation',NaN,'false_alarm_variation',NaN,'interference_ratio',NaN, ...
    'event_signature',NaN,'event_range_error',NaN,'event_velocity_error',NaN, ...
    'event_min_confidence',NaN,'recovery_time',NaN, ...
    'recovery_objective_ratio',NaN,'recovery_report_direction',NaN, ...
    'recovery_report_variation',NaN,'recovery_objective_fraction',NaN, ...
    'recovery_report_fraction',NaN,'recovery_joint_fraction',NaN);
end
function out=empty_out()
out=struct('schema',"simuverity.xp9-score.v1",'policy_id',"simuverity-101-v1:p9-xcomm01:scoring", ...
    'formula',"G*100*A^.20*Q^.10*M^.30*R^.20*D^.20", ...
    'score_inputs_valid',false,'diagnostics_valid',false,'G',false, ...
    'gate_reasons',strings(0,1),'A',0,'Q',0,'M',0,'R',0,'D',0,'score',0, ...
    'raw_metrics',struct(),'utility_metrics',struct(),'scenario_rows',struct([]), ...
    'cross_scenario_metrics',struct(), ...
    'diagnostic_scope',"one cross-scenario chirp-boundary offset/parity/I-Q convention, parity-resolved target tones, calibration-free report ordering and relative reacquisition against independent I/Q plus actual detection quality, true in-run interference response, and isolated target-wise RCS, broadband-noise/SNR, stationary-clutter and interference-strength probes");
end

function reasons=dependency_gate_reasons(runs)
% Surface clean-submission dependency failures without searching an Agent's
% temporary workspace.  The runner remains responsible for isolation; this
% function only turns an otherwise generic invalid receipt into an auditable
% dependency-closure diagnosis.
reasons=strings(0,1);
for i=1:numel(runs)
    if string(runs(i).stage)=="simulated"||~isfield(runs(i),'error'),continue;end
    message=string(runs(i).error);
    if ~(contains(message,"S-Function",'IgnoreCase',true)&& ...
            (contains(message,"不存在")||contains(message,"not found",'IgnoreCase',true)))
        continue
    end
    token=regexp(char(message),'S-Function [''"]([^''"]+)[''"]','tokens','once');
    if isempty(token),name="UNKNOWN";else,name=string(token{1});end
    reasons(end+1,1)="SUBMISSION_DEPENDENCY_CLOSURE_INVALID"; %#ok<AGROW>
    reasons(end+1,1)="MISSING_SFUNCTION:"+name; %#ok<AGROW>
    break
end
end
