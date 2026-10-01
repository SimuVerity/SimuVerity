function q = xp9_group(values,weights,allCritical)
%XP9_GROUP Weighted arithmetic mean of the submetrics in one score group.
% The third argument is retained only for backward compatibility with the
% task-specific scorers.  A zero-valued submetric is evidence of a failed
% submetric, not proof that the entire capability group is absent, so it is
% never made absorbing here.  Group-level absence gates belong in each
% task-specific scorer, where the relevant causal capability is known.
values=double(values(:));weights=double(weights(:));
if nargin<3,allCritical=false;end %#ok<NASGU>
values(~isfinite(values))=0;values=min(max(values,0),1);
if isempty(values)||numel(values)~=numel(weights)||any(~isfinite(weights))|| ...
        any(weights<0)||sum(weights)<=0,q=0;return;end
q=sum(values.*weights)/sum(weights);
end
