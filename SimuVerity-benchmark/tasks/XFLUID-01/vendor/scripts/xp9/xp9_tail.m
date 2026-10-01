function q = xp9_tail(values,weights,worstWeight)
%XP9_TAIL Conservative multi-scenario aggregate.
%   Q = XP9_TAIL(VALUES, WEIGHTS) returns the worst valid scenario score.
%   WEIGHTS and WORSTWEIGHT are retained only for backward-compatible call
%   sites; weights are validated but do not change the 100%-minimum rule.
%
%   Each input must be a complete scenario utility defined by the
%   task-specific scorer. A zero must therefore mean that the represented
%   capability genuinely failed in that required scenario, not merely that
%   one subordinate metric has an ordinary finite error.

values=double(values(:));
if nargin<2||isempty(weights),weights=ones(size(values));else,weights=double(weights(:));end
if nargin<3, worstWeight=[]; end %#ok<NASGU>
values(~isfinite(values))=0;
values=min(max(values,0),1);
if isempty(values)||numel(values)~=numel(weights)||any(~isfinite(weights))|| ...
        any(weights<0)||sum(weights)<=0
    q=0;return
end
q=min(values);
q=min(max(q,0),1);
end
