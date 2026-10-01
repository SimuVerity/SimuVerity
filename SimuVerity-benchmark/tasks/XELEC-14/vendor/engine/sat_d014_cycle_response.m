function out = sat_d014_cycle_response(v,targetRms,fundamentalHz)
%SAT_D014_CYCLE_RESPONSE Cycle-RMS startup/recovery evidence for D014.
% The metric uses the physical A-phase voltage, matching D014's existing
% official robustness convention.  It does not mistake raw sinusoidal peaks
% for a voltage-regulation transient.

if nargin<2||isempty(targetRms),targetRms=222;end
if nargin<3||isempty(fundamentalHz),fundamentalHz=50;end
out=empty_result(targetRms,fundamentalHz);
if ~isstruct(v)||~isfield(v,'t')||~isfield(v,'Y')||size(v.Y,2)<3
    out.detail="VABC_INVALID";return;
end
t=double(v.t(:));y=double(v.Y(:,1:3));
if numel(t)<16||size(y,1)~=numel(t)||any(~isfinite(t))|| ...
        any(~isfinite(y),'all')||any(diff(t)<=0)||targetRms<=0||fundamentalHz<=0
    out.detail="VABC_INVALID";return;
end

period=1/fundamentalHz;
nCycles=floor((t(end)-t(1))/period+1e-9);
if nCycles<3,out.detail="INSUFFICIENT_COMPLETE_CYCLES";return;end
edges=t(1)+(0:nCycles)*period;
cycleRms=nan(nCycles,3);
for k=1:nCycles
    lo=edges(k);hi=edges(k+1);inside=t>lo&t<hi;
    tt=[lo;t(inside);hi];
    yy=[interp1(t,y,lo,'linear','extrap');y(inside,:); ...
        interp1(t,y,hi,'linear','extrap')];
    cycleRms(k,:)=sqrt(trapz(tt,yy.^2,1)/(hi-lo));
end

aError=abs(cycleRms(:,1)-targetRms)/targetRms;
settlingBand=0.02; % conventional 2% settling band around the regulated RMS target
settleIndex=NaN;
for k=1:nCycles
    if all(aError(k:end)<=settlingBand),settleIndex=k;break;end
end
duration=edges(end)-edges(1);
if isfinite(settleIndex)
    settlingTime=edges(settleIndex+1)-edges(1);
else
    settlingTime=duration;
end
iaeFrac=mean(min(aError,1));
% Keep the conventional 2%% settling time as an interpretable diagnostic,
% but do not turn a miss at that boundary into a second hard zero gate.
% The time utility leaves 0.1 credit when the whole observation window is
% consumed without settling.  The error utility leaves 0.1 credit at a 5%%
% cycle-mean normalized error.  Both penalties are continuous; structural
% or signal invalidity is still handled by the declared semantic gate.
timeFraction=min(max(settlingTime/max(duration,eps),0),1);
lambdaTime=log(10);
lambdaError=log(10)/.05;
qSettling=exp(-lambdaTime*timeFraction);
qIae=exp(-lambdaError*iaeFrac);

out.valid=true;out.detail="OK";
out.cycle_time=edges(2:end).';
out.cycle_rms=cycleRms;
out.A_phase_error_frac=aError;
out.settling_band_frac=settlingBand;
out.settling_cycle=settleIndex;
out.settling_time_s=settlingTime;
out.settling_time_fraction=timeFraction;
out.normalized_iae=iaeFrac;
out.time_decay_lambda=lambdaTime;
out.error_decay_lambda=lambdaError;
out.q_settling=qSettling;
out.q_iae=qIae;
out.q=qSettling*qIae;
end

function out=empty_result(targetRms,fundamentalHz)
out=struct('schema',"simuverity.d014-cycle-response.v1", ...
    'valid',false,'detail',"UNINITIALIZED",'target_rms',double(targetRms), ...
    'fundamental_hz',double(fundamentalHz),'cycle_time',zeros(0,1), ...
    'cycle_rms',zeros(0,3),'A_phase_error_frac',zeros(0,1), ...
    'settling_band_frac',0.02,'settling_cycle',NaN,'settling_time_s',NaN, ...
    'settling_time_fraction',NaN,'normalized_iae',NaN, ...
    'time_decay_lambda',log(10),'error_decay_lambda',log(10)/.05, ...
    'q_settling',0,'q_iae',0,'q',0);
end
