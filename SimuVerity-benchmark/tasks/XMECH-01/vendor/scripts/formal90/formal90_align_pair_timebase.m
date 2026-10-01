function [tCommon,leftAligned,rightAligned,ok]= ...
    formal90_align_pair_timebase(tLeft,left,tRight,right,windowStart,windowEnd)
%FORMAL90_ALIGN_PAIR_TIMEBASE Align two legal variable-step scenario runs.
tCommon=zeros(0,1);leftAligned=zeros(0,size(left,2));
rightAligned=zeros(0,size(right,2));ok=false;
tLeft=double(tLeft(:));tRight=double(tRight(:));
left=double(left);right=double(right);
if isempty(tLeft)||isempty(tRight)||size(left,1)~=numel(tLeft)|| ...
        size(right,1)~=numel(tRight)||size(left,2)~=size(right,2)|| ...
        any(~isfinite(tLeft))||any(~isfinite(tRight))|| ...
        any(~isfinite(left),'all')||any(~isfinite(right),'all')|| ...
        any(diff(tLeft)<=0)||any(diff(tRight)<=0)
    return;
end
lo=max([double(windowStart),tLeft(1),tRight(1)]);
hi=min([double(windowEnd),tLeft(end),tRight(end)]);
leftWindow=tLeft>=lo&tLeft<=hi;rightWindow=tRight>=lo&tRight<=hi;
sampleCount=min(nnz(leftWindow),nnz(rightWindow));
if ~isfinite(lo)||~isfinite(hi)||hi<=lo||sampleCount<100,return;end
if isequal(tLeft,tRight)
    tCommon=tLeft(leftWindow);leftAligned=left(leftWindow,:);
    rightAligned=right(leftWindow,:);
else
    tCommon=linspace(lo,hi,sampleCount)';
    leftAligned=interp1(tLeft,left,tCommon,'linear');
    rightAligned=interp1(tRight,right,tCommon,'linear');
end
ok=numel(tCommon)>=100&&all(isfinite(leftAligned),'all')&& ...
    all(isfinite(rightAligned),'all');
end
