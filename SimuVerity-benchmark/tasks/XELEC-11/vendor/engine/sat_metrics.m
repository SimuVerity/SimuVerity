function [val, ok, detail] = sat_metrics(metricName, signals, band)
%SAT_METRICS Strict, inspectable metric evaluator for the public schema.
% signals: cell array of structs with fields y, t, Y. No synthetic time axes.
% band: metric configuration (steady_fraction, fundamental_hz, freq_search_hz, signs...).

if nargin < 3 || isempty(band), band=struct(); end
if ~iscell(signals), signals={signals}; end
metricName=lower(char(string(metricName)));
val=NaN; ok=false; detail='';

try
    steadyDetail='';
    if getbool(band,'require_steady',false)
        [steadyOk,steadyDetail]=steady_state_check(signals,band);
        if ~steadyOk, detail=steadyDetail; return; end
    end
    switch metricName
        case {'ss','final','mean','min','max','abs_max','pp','rms','crest', ...
              'ripple_pp_frac','overshoot','settling','rise','range_full'}
            [val,ok,detail]=single_metric(metricName,signals{1},band);
        case {'freq','fund_freq'}
            [val,ok,detail]=fundamental_frequency(signals{1},band);
        case 'thd'
            [val,ok,detail]=harmonic_distortion(signals{1},band);
        case 'imbalance'
            [val,ok,detail]=three_phase_imbalance(signals,band);
        case {'power_factor','power_factor_signed'}
            [val,ok,detail]=power_factor_signed(signals{1},signals{2},band);
        case 'power_factor_abs'
            [val,ok,detail]=power_factor_signed(signals{1},signals{2},band);
            if ok, val=abs(val); end
        case 'phase_angle_deg'
            [val,ok,detail]=phase_angle(signals{1},signals{2},band);
        case 'abs_phase_angle_deg'
            [val,ok,detail]=phase_angle(signals{1},signals{2},band);
            if ok, val=abs(val); detail=['absolute ' detail]; end
        case 'reactive_fraction'
            [ph,ok,detail]=phase_angle(signals{1},signals{2},band);
            if ok, val=sind(ph); end
        case 'tracking_rmse_frac'
            [val,ok,detail]=tracking_error(signals{1},signals{2},band,false);
        case 'tracking_mae_frac'
            [val,ok,detail]=tracking_error(signals{1},signals{2},band,true);
        case 'settling_to_reference'
            [val,ok,detail]=settling_to_reference(signals{1},signals{2},band);
        case {'sum_residual_frac','kcl_residual_frac','power_balance_frac'}
            [val,ok,detail]=sum_residual(signals,band);
        case 'correlation'
            [val,ok,detail]=signal_correlation(signals{1},signals{2},band);
        case 'channel_duplicate_corr'
            [val,ok,detail]=channel_duplicate_corr(signals{1},band);
        case 'phase_sequence_index'
            [val,ok,detail]=phase_sequence_index(signals{1},band);
        case {'channel_mean_imbalance','dc_channel_imbalance'}
            [val,ok,detail]=general_channel_imbalance(signals,band,false);
        case 'channel_rms_imbalance'
            [val,ok,detail]=general_channel_imbalance(signals,band,true);
        case 'channel_sum_ss'
            [val,ok,detail]=channel_sum_ss(signals,band);
        case 'channel_count'
            [val,ok,detail]=channel_count(signals{1});
        case {'level_count','multilevel_count'}
            [val,ok,detail]=level_metric(signals{1},band,true);
        case {'plateau_coverage','level_occupancy'}
            [val,ok,detail]=level_metric(signals{1},band,false);
        case 'thd_ratio'
            [h1,o1,d1]=harmonic_distortion(signals{1},band);
            [h2,o2,d2]=harmonic_distortion(signals{2},band);
            ok=o1&&o2&&h2>eps; if ok, val=h1/h2; detail=sprintf('numerator={%s} denominator={%s}',d1,d2); else, detail='THD_RATIO_INVALID'; end
        otherwise
            detail=['UNKNOWN_METRIC:' metricName];
    end
    if ok && ~isempty(steadyDetail), detail=[detail ' | ' steadyDetail]; end
catch e
    val=NaN; ok=false; detail=['METRIC_ERROR:' strtrim(e.message)];
end

if ok && (~isscalar(val) || ~isfinite(val))
    ok=false; detail='NONFINITE_METRIC'; val=NaN;
end
end

function [val,ok,detail]=single_metric(m,s,b)
[y,t,ok,detail]=valid_series(s); val=NaN; if ~ok, return; end
[ys,tss]=steady_window(y,t,getnum(b,'steady_fraction',0.2));
ssv=mean(ys);
switch m
    case 'ss', val=ssv;
    case 'final', val=y(end);
    case 'mean', val=mean(y);
    case 'min', val=min(y);
    case 'max', val=max(y);
    case 'abs_max', val=max(abs(y));
    case 'pp', val=max(ys)-min(ys);
    case 'rms', val=sqrt(mean(ys.^2));
    case 'crest', val=max(abs(ys))/max(sqrt(mean(ys.^2)),eps);
    case 'ripple_pp_frac', val=(max(ys)-min(ys))/max(abs(ssv),eps);
    case 'overshoot', val=(max(y)-ssv)/max(abs(ssv),eps);
    case 'range_full', val=max(y)-min(y);
    case 'settling'
        bandFrac=getnum(b,'settling_band_frac',0.02);
        bandAbs=max(bandFrac*max(abs(ssv),eps),getnum(b,'settling_band_abs',0));
        outside=find(abs(y-ssv)>bandAbs);
        if isempty(outside), val=t(1); else, val=t(min(outside(end)+1,numel(t))); end
    case 'rise'
        val=NaN; sgn=sign(ssv); if sgn==0, ok=false; detail='ZERO_FINAL_FOR_RISE'; return; end
        i10=find(sgn*y>=0.1*abs(ssv),1); i90=find(sgn*y>=0.9*abs(ssv),1);
        if isempty(i10)||isempty(i90)||i90<i10, ok=false; detail='RISE_NOT_OBSERVED'; return; end
        val=t(i90)-t(i10);
end
ok=isfinite(val); detail=sprintf('steady_samples=%d/%d',numel(tss),numel(t));
end

function [f,ok,detail]=fundamental_frequency(s,b)
[y,t,ok,detail]=valid_series(s); f=NaN; if ~ok, return; end
[y,t]=steady_window(y,t,getnum(b,'steady_fraction',0.2));
[f,amp,conf,ok,msg]=find_fundamental(y,t,b);
detail=sprintf('%s amp=%.4g confidence=%.4g',msg,amp,conf);
minConf=getnum(b,'min_frequency_confidence',0);
if ok && conf<minConf, ok=false; detail=[detail ' BELOW_CONFIDENCE']; f=NaN; end
end

function [thd,ok,detail]=harmonic_distortion(s,b)
[y,t,ok,detail]=valid_series(s); thd=NaN; if ~ok, return; end
[y,t]=steady_window(y,t,getnum(b,'steady_fraction',0.2));
[f0,a1,conf,ok,msg]=find_fundamental(y,t,b);
if ~ok || a1<=eps, ok=false; detail=[msg ' FUNDAMENTAL_NOT_FOUND']; return; end
dt=median(diff(t)); nyq=0.5/max(dt,eps);
maxH=floor(getnum(b,'max_harmonic',min(40,floor(nyq/f0))));
maxH=min(maxH,floor(nyq/f0));
if maxH<2, ok=false; detail='INSUFFICIENT_HARMONIC_BAND'; return; end
amps=zeros(1,maxH); amps(1)=a1;
for h=2:maxH, amps(h)=tone_amplitude(y,t,h*f0); end
thd=sqrt(sum(amps(2:end).^2))/max(amps(1),eps);
ok=isfinite(thd); detail=sprintf('f0=%.6gHz harmonics=2:%d confidence=%.4g',f0,maxH,conf);
end

function [val,ok,detail]=three_phase_imbalance(signals,b)
val=NaN; ok=false; detail='';
if numel(signals)==1
    if ~isfield(signals{1},'Y') || size(signals{1}.Y,2)<3
        detail='IMBALANCE_REQUIRES_3_CHANNELS'; return;
    end
    Y=double(signals{1}.Y(:,1:3)); t=double(signals{1}.t(:));
else
    if numel(signals)<3, detail='IMBALANCE_REQUIRES_3_SIGNALS'; return; end
    [Y,t,ok,detail]=align_many(signals(1:3)); if ~ok, return; end
end
if any(~isfinite(Y),'all'), detail='NONFINITE_CHANNEL'; return; end
frac=getnum(b,'steady_fraction',0.2); ii=t>=t(1)+(1-frac)*(t(end)-t(1)); Y=Y(ii,:);
rmss=sqrt(mean(Y.^2,1)); avg=mean(rmss);
if avg<=eps, detail='ZERO_RMS_CHANNELS'; return; end
val=max(abs(rmss-avg))/avg;
ok=isfinite(val); detail=sprintf('channels=3 rms=[%.5g %.5g %.5g]',rmss(1),rmss(2),rmss(3));
end

function [pf,ok,detail]=power_factor_signed(a,bnd,cfg)
[A,B,~,ok,detail]=align_pair(a,bnd,cfg); pf=NaN; if ~ok, return; end
S=sqrt(mean(A.^2))*sqrt(mean(B.^2));
if S<=eps, ok=false; detail='ZERO_APPARENT_POWER'; return; end
pf=mean(A.*B)/S; ok=isfinite(pf); detail=sprintf('signed_pf=%.6g',pf);
end

function [deg,ok,detail]=phase_angle(a,bnd,cfg)
[A,B,t,ok,detail]=align_pair(a,bnd,cfg); deg=NaN; if ~ok, return; end
s=struct('y',A,'t',t,'Y',A);
[f0,~,~,ok,msg]=find_fundamental(A,t,cfg); if ~ok, detail=msg; return; end
pa=tone_phasor(A,t,f0); pb=tone_phasor(B,t,f0);
deg=wrap180(rad2deg(angle(pb)-angle(pa))); ok=isfinite(deg);
detail=sprintf('f0=%.6gHz phase(second-first)=%.5gdeg',f0,deg); %#ok<NASGU>
end

function [err,ok,detail]=tracking_error(out,ref,cfg,useMae)
[A,B,~,ok,detail]=align_pair(out,ref,cfg); err=NaN; if ~ok, return; end
den=max(sqrt(mean(B.^2)),getnum(cfg,'normalization_floor',eps));
if useMae, err=mean(abs(A-B))/den; else, err=sqrt(mean((A-B).^2))/den; end
ok=isfinite(err); detail=sprintf('reference_rms=%.6g',den);
end

function [st,ok,detail]=settling_to_reference(out,ref,cfg)
[A,B,t,ok,detail]=align_pair(out,ref,cfg); st=NaN; if ~ok, return; end
tolFrac=getnum(cfg,'settling_band_frac',0.02); tolAbs=getnum(cfg,'settling_band_abs',0);
tol=max(tolFrac*max(abs(B),eps),tolAbs); outside=find(abs(A-B)>tol);
if isempty(outside), st=t(1); else, st=t(min(outside(end)+1,numel(t))); end
ok=isfinite(st); detail=sprintf('relative_to_reference band_frac=%.4g',tolFrac);
end

function [res,ok,detail]=sum_residual(signals,cfg)
[Y,~,ok,detail]=align_many(signals); res=NaN; if ~ok, return; end
signs=getarray(cfg,'signs',ones(1,size(Y,2))); signs=reshape(signs,1,[]);
if numel(signs)~=size(Y,2), ok=false; detail='SIGNS_LENGTH_MISMATCH'; return; end
r=Y*signs(:); den=sum(sqrt(mean(Y.^2,1)));
res=sqrt(mean(r.^2))/max(den,eps); ok=isfinite(res);
detail=sprintf('signals=%d signs=%s',size(Y,2),mat2str(signs));
end

function [rho,ok,detail]=signal_correlation(a,b,cfg)
[A,B,~,ok,detail]=align_pair(a,b,cfg); rho=NaN; if ~ok, return; end
C=corrcoef(A,B); if numel(C)<4||~isfinite(C(1,2)), ok=false; detail='CORRELATION_UNDEFINED'; return; end
rho=C(1,2); detail=sprintf('n=%d',numel(A));
end

function [mc,ok,detail]=channel_duplicate_corr(s,cfg)
mc=NaN; ok=false; detail='';
if ~isfield(s,'Y')||size(s.Y,2)<2, detail='REQUIRES_MULTICHANNEL'; return; end
Y=double(s.Y); t=double(s.t(:)); frac=getnum(cfg,'steady_fraction',0.2);
ii=t>=t(1)+(1-frac)*(t(end)-t(1)); Y=Y(ii,:); C=abs(corrcoef(Y)); C(1:size(C,1)+1:end)=0;
mc=max(C,[],'all'); ok=isfinite(mc); detail=sprintf('channels=%d',size(Y,2));
end

function [idx,ok,detail]=phase_sequence_index(s,cfg)
idx=NaN;ok=false;detail='';
if ~isstruct(s)||~isfield(s,'Y')||size(s.Y,2)<3||~isfield(s,'t'),detail='PHASE_SEQUENCE_REQUIRES_3_CHANNELS';return;end
Y=double(s.Y(:,1:3));t=double(s.t(:));
if size(Y,1)~=numel(t)||numel(t)<8||any(~isfinite(Y),'all')||any(~isfinite(t))||any(diff(t)<=0),detail='INVALID_THREE_PHASE_SERIES';return;end
frac=getnum(cfg,'steady_fraction',0.2);ii=t>=t(1)+(1-frac)*(t(end)-t(1));Y=Y(ii,:);t=t(ii);
probe=struct('y',Y(:,1),'t',t,'Y',Y(:,1));[f0,~,~,found,msg]=find_fundamental(Y(:,1),t,cfg);
if ~found,detail=['PHASE_SEQUENCE_FUNDAMENTAL:' msg];return;end
phasors=zeros(1,3);for k=1:3,phasors(k)=tone_phasor(Y(:,k),t,f0);end
a=exp(1i*2*pi/3);positive=(phasors(1)+a*phasors(2)+a^2*phasors(3))/3;negative=(phasors(1)+a^2*phasors(2)+a*phasors(3))/3;
p=abs(positive);n=abs(negative);den=p+n;floorAmp=getnum(cfg,'min_sequence_amplitude',1e-9);
if den<=floorAmp,detail=sprintf('DEGENERATE_SEQUENCE pos=%.5g neg=%.5g f0=%.6g',p,n,f0);return;end
idx=(p-n)/den;ok=isfinite(idx);detail=sprintf('f0=%.6gHz positive=%.5g negative=%.5g',f0,p,n); %#ok<NASGU>
end

function [val,ok,detail]=general_channel_imbalance(signals,cfg,useRms)
val=NaN; ok=false; detail=''; [Y,t,ok,detail]=signal_matrix(signals); if ~ok, return; end
frac=getnum(cfg,'steady_fraction',0.2); ii=t>=t(1)+(1-frac)*(t(end)-t(1)); Y=Y(ii,:);
if useRms, levels=sqrt(mean(Y.^2,1)); else, levels=mean(Y,1); end
den=max(mean(abs(levels)),getnum(cfg,'normalization_floor',eps));
if den<=eps, ok=false; detail='ZERO_CHANNEL_LEVELS'; return; end
val=max(abs(levels-mean(levels)))/den; ok=isfinite(val);
detail=sprintf('channels=%d values=%s',numel(levels),mat2str(levels,5));
end

function [val,ok,detail]=channel_sum_ss(signals,cfg)
val=NaN; ok=false; detail=''; [Y,t,ok,detail]=signal_matrix(signals); if ~ok, return; end
frac=getnum(cfg,'steady_fraction',0.2); ii=t>=t(1)+(1-frac)*(t(end)-t(1));
levels=mean(Y(ii,:),1); val=sum(levels); ok=isfinite(val);
detail=sprintf('channels=%d means=%s',numel(levels),mat2str(levels,5));
end

function [val,ok,detail]=channel_count(s)
val=NaN; ok=false; detail='';
if ~isstruct(s)||~isfield(s,'Y')||isempty(s.Y), detail='INVALID_SIGNAL_STRUCT'; return; end
val=size(s.Y,2); ok=true; detail=sprintf('channels=%d',val);
end

function [val,ok,detail]=level_metric(s,cfg,returnCount)
val=NaN; ok=false; detail=''; [y,t,ok,detail]=valid_series(s); if ~ok, return; end
[y,~]=steady_window(y,t,getnum(cfg,'steady_fraction',0.5));
lo=prctile_local(y,getnum(cfg,'level_range_low_pct',0.2)); hi=prctile_local(y,getnum(cfg,'level_range_high_pct',99.8));
span=hi-lo; if ~isfinite(span)||span<=max(abs([lo hi]))*1e-9, ok=false; detail='DEGENERATE_LEVEL_RANGE'; return; end
nb=max(51,round(getnum(cfg,'level_hist_bins',201))); edges=linspace(lo,hi,nb+1); h=histcounts(y,edges);
hs=conv(double(h),[1 2 3 2 1]/9,'same'); minPeak=max(3,getnum(cfg,'min_level_occupancy',0.005)*numel(y));
cand=find(hs>=minPeak & hs>=[-Inf hs(1:end-1)] & hs>=[hs(2:end) -Inf]);
centers=(edges(cand)+edges(cand+1))/2; weights=hs(cand); [centers,ord]=sort(centers); weights=weights(ord);
minSep=getnum(cfg,'min_level_separation_frac',0.06)*span; merged=[]; mergedW=[];
for i=1:numel(centers)
    if isempty(merged)||centers(i)-merged(end)>=minSep
        merged(end+1)=centers(i); mergedW(end+1)=weights(i); %#ok<AGROW>
    elseif weights(i)>mergedW(end)
        merged(end)=centers(i); mergedW(end)=weights(i);
    end
end
if isempty(merged), ok=false; detail='NO_LEVEL_PEAKS'; return; end
tol=getnum(cfg,'level_tolerance_frac',0.025)*span; dist=inf(size(y));
for i=1:numel(merged), dist=min(dist,abs(y-merged(i))); end
coverage=mean(dist<=tol); count=numel(merged); minCoverage=getnum(cfg,'min_plateau_coverage',0.55);
if returnCount
    val=count; ok=coverage>=minCoverage;
    if ~ok, detail=sprintf('CONTINUOUS_OR_UNSTABLE coverage=%.5g<%.5g count=%d centers=%s',coverage,minCoverage,count,mat2str(merged,5));
    else, detail=sprintf('count=%d coverage=%.5g centers=%s',count,coverage,mat2str(merged,5)); end
else
    val=coverage; ok=true; detail=sprintf('count=%d coverage=%.5g centers=%s',count,coverage,mat2str(merged,5));
end
end

function [Y,t,ok,detail]=signal_matrix(signals)
Y=[]; t=[]; ok=false; detail='';
if numel(signals)==1&&isstruct(signals{1})&&isfield(signals{1},'Y')&&size(signals{1}.Y,2)>=2
    Y=double(signals{1}.Y); t=double(signals{1}.t(:)); ok=size(Y,1)==numel(t)&&all(isfinite(Y),'all');
    if ok, detail='multichannel'; else, detail='INVALID_MULTICHANNEL'; end
else
    [Y,t,ok,detail]=align_many(signals);
end
end

function q=prctile_local(x,p)
x=sort(double(x(:))); p=min(max(double(p),0),100); pos=1+(numel(x)-1)*p/100; a=floor(pos); b=ceil(pos);
if a==b, q=x(a); else, q=x(a)+(pos-a)*(x(b)-x(a)); end
end

function [y,t,ok,detail]=valid_series(s)
y=[]; t=[]; ok=false; detail='';
if ~isstruct(s)||~isfield(s,'y')||~isfield(s,'t'), detail='INVALID_SIGNAL_STRUCT'; return; end
y=double(s.y(:)); t=double(s.t(:));
if numel(y)~=numel(t)||numel(y)<8, detail='INSUFFICIENT_OR_MISALIGNED_SAMPLES'; return; end
fin=isfinite(y)&isfinite(t); y=y(fin); t=t(fin);
if numel(y)<8||any(diff(t)<=0), detail='INVALID_TIME_AXIS'; return; end
ok=true;
end

function [ys,ts]=steady_window(y,t,frac)
frac=min(max(frac,0.05),1); t0=t(1)+(1-frac)*(t(end)-t(1)); ii=t>=t0; ys=y(ii); ts=t(ii);
end

function [ok,detail]=steady_state_check(signals,cfg)
% Prove that the evaluator-owned tail window is stationary before a
% steady-state metric is allowed to score.  The check is optional and is
% deliberately separate from target accuracy: a stable wrong value passes
% this gate and then fails its numeric band.
ok=false;detail='';
stat=lower(gettxt(cfg,'steady_stat','rms'));
if ~ismember(stat,{'rms','mean'})
    detail=['STEADY_CHECK_ERROR:UNKNOWN_STAT:' stat];return;
end
allChannels=getbool(cfg,'steady_all_channels',false);
frac=min(max(getnum(cfg,'steady_fraction',0.2),0.05),1);
cycleHz=getnum(cfg,'steady_cycle_hz',0);
cycles=max(2,round(getnum(cfg,'steady_cycles',5)));
bins=max(2,round(getnum(cfg,'steady_bins',5)));
rangeLimit=getnum(cfg,'steady_rel_range_max',0.10);
driftLimit=getnum(cfg,'steady_rel_drift_max',0.10);
minPerBin=max(4,round(getnum(cfg,'steady_min_samples_per_bin',8)));
normalizationFloor=max(getnum(cfg,'steady_normalization_floor',1e-9),eps);
if rangeLimit<=0||driftLimit<=0
    detail='STEADY_CHECK_ERROR:NONPOSITIVE_LIMIT';return;
end

worstRange=0;worstDrift=0;usedBins=0;usedChannels=0;lastValues=[];
for si=1:numel(signals)
    s=signals{si};
    if ~isstruct(s)||~isfield(s,'t')||~isfield(s,'y')
        detail=sprintf('STEADY_CHECK_ERROR:SIGNAL_%d_INVALID',si);return;
    end
    t=double(s.t(:));
    if allChannels&&isfield(s,'Y')&&~isempty(s.Y),Y=double(s.Y);
    else,Y=double(s.y(:));end
    if size(Y,1)~=numel(t)||numel(t)<2*minPerBin||any(~isfinite(Y),'all') ...
            ||any(~isfinite(t))||any(diff(t)<=0)
        detail=sprintf('STEADY_CHECK_ERROR:SIGNAL_%d_INVALID_SERIES',si);return;
    end
    tailStart=t(1)+(1-frac)*(t(end)-t(1));
    if cycleHz>0
        duration=cycles/cycleHz;startTime=t(end)-duration;
        sampleTol=max(median(diff(t))*1.5,1e-9);
        if startTime<tailStart-sampleTol
            detail=sprintf('STEADY_CHECK_ERROR:TAIL_TOO_SHORT need=%.6gs have=%.6gs', ...
                duration,t(end)-tailStart);return;
        end
        edges=t(end)-((cycles:-1:0)/cycleHz);nBins=cycles;
    else
        edges=linspace(tailStart,t(end),bins+1);nBins=bins;
    end
    values=zeros(nBins,size(Y,2));
    for bi=1:nBins
        if bi<nBins,ii=t>=edges(bi)&t<edges(bi+1);
        else,ii=t>=edges(bi)&t<=edges(bi+1);end
        if nnz(ii)<minPerBin
            detail=sprintf('STEADY_CHECK_ERROR:SIGNAL_%d_BIN_%d_TOO_SHORT samples=%d', ...
                si,bi,nnz(ii));return;
        end
        switch stat
            case 'rms',values(bi,:)=sqrt(mean(Y(ii,:).^2,1));
            case 'mean',values(bi,:)=mean(Y(ii,:),1);
        end
    end
    scale=max(abs(median(values,1)),normalizationFloor);
    relRange=(max(values,[],1)-min(values,[],1))./scale;
    relDrift=zeros(1,size(values,2));x=(0:nBins-1)';
    for ci=1:size(values,2)
        p=polyfit(x,values(:,ci),1);
        relDrift(ci)=abs(p(1)*(nBins-1))/scale(ci);
    end
    worstRange=max(worstRange,max(relRange));
    worstDrift=max(worstDrift,max(relDrift));
    usedBins=nBins;usedChannels=usedChannels+size(Y,2);lastValues=values;
end
if worstRange>rangeLimit||worstDrift>driftLimit
    detail=sprintf(['NOT_SETTLED:stat=%s bins=%d channels=%d rel_range=%.6g>' ...
        '%.6g_or_rel_drift=%.6g>%.6g values=%s'],stat,usedBins,usedChannels, ...
        worstRange,rangeLimit,worstDrift,driftLimit,mat2str(lastValues,5));
    return;
end
ok=true;
detail=sprintf('STEADY_OK:stat=%s bins=%d channels=%d rel_range=%.6g rel_drift=%.6g', ...
    stat,usedBins,usedChannels,worstRange,worstDrift);
end

function [f0,a1,conf,ok,msg]=find_fundamental(y,t,cfg)
f0=NaN; a1=NaN; conf=0; ok=false; msg='';
y=y(:)-mean(y); t=t(:); dur=t(end)-t(1);
if numel(y)<16||dur<=0||sqrt(mean(y.^2))<=eps, msg='INSUFFICIENT_AC_SIGNAL'; return; end
dt=median(diff(t)); Fs=1/max(dt,eps); N=max(2048,2^nextpow2(numel(y)*2));
tu=linspace(t(1),t(end),N)'; yu=interp1(t,y,tu,'linear'); yu=yu-mean(yu);
w=0.5-0.5*cos(2*pi*(0:N-1)'/max(N-1,1)); Y=abs(fft(yu.*w)); f=(0:N-1)'*(N-1)/max(dur,eps)/N;
half=f<=Fs/2; f=f(half); Y=Y(half);
if isfield(cfg,'fundamental_hz') && isnumeric(cfg.fundamental_hz) && isfinite(cfg.fundamental_hz)
    fc=double(cfg.fundamental_hz); span=getnum(cfg,'fundamental_search_frac',0.2); lo=max(fc*(1-span),1/dur); hi=min(fc*(1+span),Fs/2);
elseif isfield(cfg,'freq_search_hz') && isnumeric(cfg.freq_search_hz) && numel(cfg.freq_search_hz)>=2
    lo=max(double(cfg.freq_search_hz(1)),1/dur); hi=min(double(cfg.freq_search_hz(2)),Fs/2);
else
    lo=max(2/dur,getnum(cfg,'freq_min_hz',1)); hi=min(getnum(cfg,'freq_max_hz',Fs/4),Fs/2);
end
idx=find(f>=lo&f<=hi); if isempty(idx), msg='EMPTY_FREQUENCY_SEARCH'; return; end
[pk,j]=max(Y(idx)); k=idx(j); f0=f(k);
if k>1&&k<numel(Y)
    den=Y(k-1)-2*Y(k)+Y(k+1); if abs(den)>eps, delta=0.5*(Y(k-1)-Y(k+1))/den; f0=f0+delta*(f(2)-f(1)); end
end
noise=median(Y(idx)); conf=pk/max(noise,eps); a1=tone_amplitude(y,t,f0);
ok=isfinite(f0)&&f0>0&&a1>eps; msg=sprintf('search=[%.5g %.5g]',lo,hi);
end

function a=tone_amplitude(y,t,f)
p=tone_phasor(y,t,f); a=2*abs(p);
end
function p=tone_phasor(y,t,f)
y=y(:)-mean(y); t=t(:); p=mean(y.*exp(-1j*2*pi*f*t));
end

function [A,B,t,ok,detail]=align_pair(a,b,cfg)
[Y,t,ok,detail]=align_many({a,b}); A=[]; B=[]; if ~ok, return; end
frac=getnum(cfg,'steady_fraction',0.2); ii=t>=t(1)+(1-frac)*(t(end)-t(1)); Y=Y(ii,:); t=t(ii);
A=Y(:,1); B=Y(:,2);
end

function [Y,t,ok,detail]=align_many(signals)
Y=[]; t=[]; ok=false; detail=''; n=numel(signals); if n<1, detail='NO_SIGNALS'; return; end
t0=-Inf; t1=Inf;
for i=1:n
    [~,ti,vi,msg]=valid_series(signals{i}); if ~vi, detail=['SIGNAL_' num2str(i) ':' msg]; return; end
    t0=max(t0,ti(1)); t1=min(t1,ti(end));
end
if t1<=t0, detail='NO_TIME_OVERLAP'; return; end
N=max(256,min(4096,max(cellfun(@(s) numel(s.t),signals)))); t=linspace(t0,t1,N)'; Y=zeros(N,n);
for i=1:n, Y(:,i)=interp1(double(signals{i}.t(:)),double(signals{i}.y(:)),t,'linear'); end
ok=all(isfinite(Y),'all'); if ok, detail=sprintf('aligned_n=%d',N); else, detail='ALIGN_NONFINITE'; end
end

function x=getnum(s,f,d)
x=d; if isfield(s,f)&&~isempty(s.(f))&&isnumeric(s.(f))&&all(isfinite(s.(f))), x=double(s.(f)); end
end
function x=getarray(s,f,d)
x=d; if isfield(s,f)&&~isempty(s.(f))&&isnumeric(s.(f)), x=double(s.(f)); end
end
function x=getbool(s,f,d)
x=d;if isfield(s,f)&&~isempty(s.(f))&&isscalar(s.(f)),x=logical(s.(f));end
end
function x=gettxt(s,f,d)
x=d;if isfield(s,f)&&~isempty(s.(f)),x=char(string(s.(f)));end
end
function x=wrap180(x), x=mod(x+180,360)-180; end
