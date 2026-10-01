function out = sat_d007_cycle_response(i,fundamentalHz)
%SAT_D007_CYCLE_RESPONSE Cold-start cycle-RMS evidence for D007.
% This bounded D007 cold-start utility is score-bearing.  Convergence
% is measured against the final two-cycle physical current RMS rather than
% against a hidden golden transient or a prescribed controller structure.

if nargin<2||isempty(fundamentalHz),fundamentalHz=50;end
out=empty_result(fundamentalHz);
if ~isstruct(i)||~isfield(i,'t')||~isfield(i,'Y')||size(i.Y,2)<3
    out.detail="IGRID_INVALID";return;
end
t=double(i.t(:));y=double(i.Y(:,1:3));
if numel(t)<16||size(y,1)~=numel(t)||any(~isfinite(t))|| ...
        any(~isfinite(y),'all')||any(diff(t)<=0)||fundamentalHz<=0
    out.detail="IGRID_INVALID";return;
end

period=1/fundamentalHz;
nCycles=floor((t(end)-t(1))/period+1e-9);
if nCycles<4,out.detail="INSUFFICIENT_COMPLETE_CYCLES";return;end
edges=t(1)+(0:nCycles)*period;
cycleRms=nan(nCycles,3);
for k=1:nCycles
    lo=edges(k);hi=edges(k+1);inside=t>lo&t<hi;
    tt=[lo;t(inside);hi];
    yy=[interp1(t,y,lo,'linear','extrap');y(inside,:); ...
        interp1(t,y,hi,'linear','extrap')];
    cycleRms(k,:)=sqrt(trapz(tt,yy.^2,1)/(hi-lo));
end

target=mean(cycleRms(end-1:end,:),1);
scale=max(abs(target),max(1e-9,.01*max(abs(cycleRms),[],'all')));
relError=max(abs(cycleRms-target)./scale,[],2);
settlingBand=.10;
settleIndex=NaN;
for k=1:nCycles
    if all(relError(k:end)<=settlingBand),settleIndex=k;break;end
end
duration=edges(end)-edges(1);
if isfinite(settleIndex)
    settlingTime=edges(settleIndex+1)-edges(1);
else
    settlingTime=duration;
end
timeFraction=min(max(settlingTime/max(duration,eps),0),1);
iaeFrac=mean(min(relError,2));
% The bounded utility distinguishes prompt establishment quality without
% introducing a separate pass/fail threshold.
qSettling=exp(-log(10)*timeFraction);
qIae=exp(-(log(10)/.20)*iaeFrac);

out.valid=true;out.detail="OK";
out.cycle_time=edges(2:end).';out.cycle_rms=cycleRms;
out.final_rms_target=target;out.worst_relative_error=relError;
out.settling_band_frac=settlingBand;out.settling_cycle=settleIndex;
out.settling_time_s=settlingTime;out.settling_time_fraction=timeFraction;
out.normalized_iae=iaeFrac;out.q_settling=qSettling;out.q_iae=qIae;
out.q=qSettling*qIae;
end

function out=empty_result(fundamentalHz)
out=struct('schema',"simuverity.d007-cycle-response.v1", ...
    'valid',false,'detail',"UNINITIALIZED", ...
    'fundamental_hz',double(fundamentalHz),'cycle_time',zeros(0,1), ...
    'cycle_rms',zeros(0,3),'final_rms_target',nan(1,3), ...
    'worst_relative_error',zeros(0,1),'settling_band_frac',.10, ...
    'settling_cycle',NaN,'settling_time_s',NaN, ...
    'settling_time_fraction',NaN,'normalized_iae',NaN, ...
    'q_settling',0,'q_iae',0,'q',0);
end
