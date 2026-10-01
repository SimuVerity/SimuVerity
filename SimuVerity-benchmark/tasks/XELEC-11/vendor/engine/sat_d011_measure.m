function out=sat_d011_measure(sig,spec,scenarioId) %#ok<INUSD>
%SAT_D011_MEASURE Physical measurements used only by D011's direct score.
% D011 is an open-loop frequency-commanded drive.  Startup quantities are
% reported for diagnosis but are deliberately not score-bearing.

out=empty_measurement(scenarioId);
need={'Wm','Vdc','Vabc','Iabc'};
for i=1:numel(need)
    if ~isstruct(sig)||~isfield(sig,need{i}),out.reason="MISSING_"+upper(need{i});return;end
end
target=frequency_target(scenarioId);
cfg=steady_cfg(target);
[out.Wm_ss,a]=sat_metrics('ss',{sig.Wm},mean_cfg());
[out.Wm_settling_s,b]=sat_metrics('settling',{sig.Wm},settling_cfg());
[out.Vdc_mean,c]=sat_metrics('ss',{sig.Vdc},mean_cfg());
[out.Vdc_ripple_pp_frac,d]=sat_metrics('ripple_pp_frac',{sig.Vdc},mean_cfg());
[out.Vabc_freq,fv]=phase_metric(sig.Vabc,'fund_freq',cfg);
[out.Vabc_thd,tv]=phase_metric(sig.Vabc,'thd',cfg);
[out.Iabc_thd,ti]=phase_metric(sig.Iabc,'thd',cfg);
[out.Vabc_imbalance,iv]=sat_metrics('imbalance',{sig.Vabc},cfg);
[out.Iabc_imbalance,ii]=sat_metrics('imbalance',{sig.Iabc},cfg);
[out.Vabc_sequence_index,sv]=sat_metrics('phase_sequence_index',{sig.Vabc},cfg);
[out.Iabc_sequence_index,si]=sat_metrics('phase_sequence_index',{sig.Iabc},cfg);
out.valid=all([a c d fv tv ti iv ii sv si]);
out.startup_diagnostic_valid=b;
out.reason=tern(out.valid,"OK","METRIC_EXTRACTION_FAILED");
end

function [v,ok]=phase_metric(s,name,cfg)
v=nan(1,3);ok=isstruct(s)&&isfield(s,'Y')&&size(s.Y,2)>=3&&isfield(s,'t');
if ~ok,return;end
for k=1:3
    x=struct('t',double(s.t(:)),'Y',double(s.Y(:,k)),'y',double(s.Y(:,k)));
    [v(k),hit]=sat_metrics(name,{x},cfg);ok=ok&&hit;
end
end
function cfg=steady_cfg(f)
cfg=struct('fundamental_hz',f,'steady_fraction',.25,'require_steady',true, ...
    'steady_stat','rms','steady_cycle_hz',f,'steady_cycles',5, ...
    'steady_rel_range_max',.10,'steady_rel_drift_max',.10, ...
    'steady_all_channels',true);
end
function cfg=mean_cfg()
cfg=struct('steady_fraction',.25,'require_steady',true,'steady_stat','mean', ...
    'steady_bins',5,'steady_rel_range_max',.10,'steady_rel_drift_max',.10);
end
function cfg=settling_cfg(),cfg=struct('steady_fraction',.20,'settling_band_frac',.05);end
function f=frequency_target(id)
switch string(id),case "frequency_low",f=45;case "frequency_high",f=55;otherwise,f=50;end
end
function out=empty_measurement(id)
out=struct('schema',"simuverity.d011-direct-measurement.v1", ...
    'scenario',string(id),'valid',false,'reason',"UNINITIALIZED", ...
    'Wm_ss',NaN,'Wm_settling_s',NaN,'Vdc_mean',NaN, ...
    'Vdc_ripple_pp_frac',NaN,'Vabc_freq',nan(1,3), ...
    'Vabc_thd',nan(1,3),'Iabc_thd',nan(1,3), ...
    'Vabc_imbalance',NaN,'Iabc_imbalance',NaN, ...
    'Vabc_sequence_index',NaN,'Iabc_sequence_index',NaN, ...
    'startup_diagnostic_valid',false);
end
function v=tern(c,a,b),if c,v=a;else,v=b;end,end
