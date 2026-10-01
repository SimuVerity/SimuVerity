function q = xp9_utility(value,anchors,scores)
%XP9_UTILITY Piecewise-linear monotone engineering utility in [0,1].
value=double(value);anchors=double(anchors(:));scores=double(scores(:));
if ~isscalar(value)||~isfinite(value)||numel(anchors)~=numel(scores) ...
        ||numel(anchors)<2||any(diff(anchors)<=0)
    q=0;return
end
value=min(max(value,anchors(1)),anchors(end));
q=interp1(anchors,scores,value,'linear');q=min(max(q,0),1);
end
