function [t,y,ok,reason] = xp9_series(run,name,minChannels)
%XP9_SERIES Validate and normalize one logged Timeseries.
if nargin<3,minChannels=1;end
t=[];y=[];ok=false;reason="missing";
if ~isstruct(run)||~isfield(run,'outputs'),return;end
key=matlab.lang.makeValidName(char(string(name)));
if ~isfield(run.outputs,key),return;end
ts=run.outputs.(key);
if ~isa(ts,'timeseries'),reason="not_timeseries";return;end
t=double(ts.Time(:));y=double(ts.Data);
if isempty(y),reason="empty";return;end
if size(y,1)~=numel(t)
    sz=size(y);timeDim=find(sz==numel(t),1,'last');
    if isempty(timeDim),reason="time_length";return;end
    order=[timeDim,1:timeDim-1,timeDim+1:ndims(y)];
    y=permute(y,order);
end
y=reshape(y,numel(t),[]);
if size(y,2)<minChannels,reason="channels";return;end
if any(~isfinite(t))||any(~isfinite(y(:))),reason="nonfinite";return;end
% Scorers use time derivatives, cycle windows and recovery durations.  A
% repeated timestamp is therefore not a harmless formatting detail: it can
% create zero-step derivatives or duplicate evidence at one instant.  Keep
% variable-step sampling legal, but require a strictly increasing clock.
if numel(t)<4||any(diff(t)<=0)||t(end)<=t(1),reason="timebase";return;end
ok=true;reason="ok";
end
