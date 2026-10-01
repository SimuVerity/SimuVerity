function score = xp9_total(G,groups,weights)
%XP9_TOTAL Weighted geometric score with no post-hoc compression factor.
groups=double(groups(:));weights=double(weights(:));
if ~G||isempty(groups)||numel(groups)~=numel(weights)|| ...
        any(~isfinite(weights))||any(weights<0)||sum(weights)<=0
    score=0;return
end
groups(~isfinite(groups))=0;groups=min(max(groups,0),1);
weights=weights/sum(weights);
score=100*prod(max(groups,1e-12).^weights);
if any(groups==0),score=0;end
score=min(max(real(score),0),100);
end
