function out = sat_d014_measure(sig, spec, scenarioId)
%SAT_D014_MEASURE Extract D014 all-phase steady-state score evidence.
% This helper reports physical metrics only.  Score aggregation and the
% semantic qualification gate are intentionally handled by
% sat_score_d014_direct.

scenarioId=string(scenarioId);
out=empty_measurement(scenarioId);
if ~isstruct(spec)||~isscalar(spec)||~isfield(spec,'id')||string(spec.id)~="D014"
    out.detail="NOT_D014";return;
end
if ~isstruct(sig)||~isfield(sig,'Vabc')
    out.detail="VABC_MISSING";return;
end

v=sig.Vabc;
if ~valid_multichannel(v,3)
    out.detail="VABC_INVALID_OR_NOT_THREE_PHASE";return;
end

if scenarioId=="nominal"
    rmsCfg=find_band(spec,"vabc_rms_nom");
else
    rmsCfg=find_band(spec,"vabc_rms_"+scenarioId);
end
if isempty(fieldnames(rmsCfg))
    out.detail="RMS_BAND_MISSING:"+scenarioId;return;
end
[out.Vabc_rms,rmsOk]=per_channel_metric(v,'rms',rmsCfg,3);
out.Vabc_rms_valid=all(rmsOk);
out.cycle_response=sat_d014_cycle_response(v,222,50);

% Robustness uses only A-phase RMS.  Nominal-only quality measurements are
% deliberately not required in every official scenario.
if scenarioId~="nominal"
    out.valid=out.Vabc_rms_valid;
    out.detail=tern(out.valid,"OK","VABC_RMS_INVALID");return;
end

freqCfg=find_band(spec,"vabc_freq_nom");
thdCfg=find_band(spec,"vabc_thd_nom");
imbCfg=find_band(spec,"vabc_balance_nom");
dupCfg=find_band(spec,"vabc_duplicate_guard");
[out.Vabc_freq,freqOk]=per_channel_metric(v,'fund_freq',freqCfg,3);
[out.Vabc_thd,thdOk]=per_channel_metric(v,'thd',thdCfg,3);
[out.Vabc_imbalance,imbOk]=sat_metrics('imbalance',{v},imbCfg);
[out.Vabc_duplicate_corr,dupOk]=sat_metrics('channel_duplicate_corr',{v},dupCfg);
out.Vabc_freq_valid=all(freqOk);
out.Vabc_thd_valid=all(thdOk);
out.Vabc_imbalance_valid=imbOk;
out.Vabc_duplicate_corr_valid=dupOk;

if isfield(sig,'Vdc')&&valid_multichannel(sig.Vdc,1)
    rippleCfg=find_band(spec,"vdc_ripple_nom");
    [out.Vdc_ripple_pp_frac,out.Vdc_ripple_valid]=sat_metrics( ...
        'ripple_pp_frac',{sig.Vdc},rippleCfg);
end

% Iabc remains a required truthful interface elsewhere in the public contract.
% Its THD is part of D014's direct quality score; RMS and imbalance remain
% diagnostic evidence.
if isfield(sig,'Iabc')&&valid_multichannel(sig.Iabc,3)
    i=sig.Iabc;
    iImbCfg=find_band(spec,"iabc_balance_nom");
    iThdCfg=find_band(spec,"iabc_thd_nom");
    [out.Iabc_rms,iRmsOk]=per_channel_metric(i,'rms',iImbCfg,3);
    [out.Iabc_imbalance,iImbOk]=sat_metrics('imbalance',{i},iImbCfg);
    [out.Iabc_thd,iThdOk]=per_channel_metric(i,'thd',iThdCfg,3);
    out.Iabc_thd_valid=all(iThdOk);
    out.Iabc_diagnostic_valid=all(iRmsOk)&&iImbOk&&all(iThdOk);
end

out.valid=out.Vabc_rms_valid&&out.Vabc_freq_valid&&out.Vabc_thd_valid&& ...
    out.Vabc_imbalance_valid&&out.Vabc_duplicate_corr_valid&&out.Vdc_ripple_valid&& ...
    out.Iabc_thd_valid;
out.detail=tern(out.valid,"OK","ONE_OR_MORE_NOMINAL_METRICS_INVALID");
end

function out=empty_measurement(scenarioId)
out=struct('schema',"simuverity.d014-direct-measurement.v1", ...
    'scenario',string(scenarioId),'valid',false,'detail',"UNINITIALIZED", ...
    'Vabc_rms',nan(1,3),'Vabc_rms_valid',false, ...
    'Vabc_freq',nan(1,3),'Vabc_freq_valid',false, ...
    'Vabc_imbalance',NaN,'Vabc_imbalance_valid',false, ...
    'Vabc_thd',nan(1,3),'Vabc_thd_valid',false, ...
    'Vabc_duplicate_corr',NaN,'Vabc_duplicate_corr_valid',false, ...
    'Vdc_ripple_pp_frac',NaN,'Vdc_ripple_valid',false, ...
    'Iabc_rms',nan(1,3),'Iabc_imbalance',NaN,'Iabc_thd',nan(1,3), ...
    'Iabc_thd_valid',false,'Iabc_diagnostic_valid',false,'cycle_response', ...
    sat_d014_cycle_response(struct(),222,50));
end

function [values,oks]=per_channel_metric(s,metric,cfg,n)
values=nan(1,n);oks=false(1,n);
if isempty(fieldnames(cfg)),return;end
for k=1:n
    one=s;one.y=double(s.Y(:,k));one.Y=one.y;
    [values(k),oks(k)]=sat_metrics(metric,{one},cfg);
end
end

function ok=valid_multichannel(s,n)
ok=isstruct(s)&&isfield(s,'Y')&&isfield(s,'t')&&size(s.Y,2)>=n ...
    &&size(s.Y,1)==numel(s.t)&&size(s.Y,1)>=8&&all(isfinite(s.Y(:,1:n)),'all') ...
    &&all(isfinite(s.t))&&all(diff(double(s.t(:)))>0);
end

function b=find_band(spec,id)
b=struct();
if ~isfield(spec,'behavioral')||isempty(spec.behavioral),return;end
hits={};
for i=1:numel(spec.behavioral)
    if iscell(spec.behavioral),x=spec.behavioral{i};else,x=spec.behavioral(i);end
    if isstruct(x)&&isfield(x,'id')&&string(x.id)==string(id),hits{end+1}=x;end %#ok<AGROW>
end
if isscalar(hits),b=hits{1};end
end

function v=tern(c,a,b),if c,v=a;else,v=b;end,end
