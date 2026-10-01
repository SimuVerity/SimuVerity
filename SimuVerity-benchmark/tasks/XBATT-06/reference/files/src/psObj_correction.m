%% Correct index for Pulses (DO NOT USE - CLASS IS READ ONLY)

% -- Get index and pulse data
idxEdge = psObj.idxEdge;
idxLoad = psObj.idxLoad;
idxRelax = psObj.idxRelax;
Pulse = psObj.Pulse;

% -- Loop through all the pulses and correct each load and relaxation
numPulses = length(Pulse); len = length(current);
idxEdge_new = [];
idxLoad_new = [];
idxRelax_new = [];
for i = 1:numPulses
    % -- Get current index
    kl = idxLoad(i,:);
    kr = idxRelax(i,:);
    %ke = idxEdge(4*(i-1)+1:4*(i-1)+4,1);

    % -- Check if index is in correct position
    p = Pulse(i);    
    sep = 5;
    for j=1:2
        if j == 1
            % -- we are finding load points
            ran = kl(j)-sep:kl(j)+sep;
            ran(ran<1) = [];
            maxcur = max(current(ran));
            temp = find(current(ran)==maxcur,1,'first');
            kl_new(j) = ran(temp);

            % -- we are finding relax points
            ran = kr(j)-sep:kr(j)+sep;
            mincur = min(current(ran));
            temp = find(current(ran)==mincur,1,'first');
            kr_new(j) = ran(temp);
        else
            % -- we are finding load points
            ran = kl(j)-sep:kl(j)+sep;
            mincur = min(current(ran));
            temp = find(current(ran)>mincur,5,'last');
            kl_new(j) = ran(temp(1));

            % -- we are finding relax points
            ran = kr(j)-sep:kr(j)+sep;
            ran(ran>len) = [];
            maxcur = max(current(ran));
            temp = find(current(ran)<maxcur,5,'last');
            if isempty(temp)
                kr_new(j) = len;
            else
                kr_new(j) = ran(temp(1));
            end
        end
    end
    ke_new = [kl_new';kr_new'];
    if 1
        plot(time,current)
        hold on
        plot(time(kl),current(kl),'ro')
        plot(time(kr),current(kr),'bo')
        plot(time(kl_new),current(kl_new),'r*')
        plot(time(kr_new),current(kr_new),'b*')
        hold off
        xlim([time(min(ke_new))-0.01,time(max(ke_new))+0.01])
    end
    

    % -- Update Pulse info
    Pulse(i).idxLoad = kl_new;
    Pulse(i).idxRelax = kr_new;
    idxEdge_new = [idxEdge_new;ke_new];
    idxLoad_new = [idxLoad_new;kl_new];
    idxRelax_new = [idxRelax_new;kr_new];
end

% -- Update index to psObj
psObj.idxEdge = idxEdge_new;
psObj.idxLoad = idxLoad_new;
psObj.idxRelax = idxRelax_new;
psObj.Pulse = Pulse;