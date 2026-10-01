function [info, idNum] = getActorConfig(actorName)
global agentsInfo; % global variable wich contains all the info
nAgents = numel(agentsInfo);

idNum = str2num(strrep(actorName, "actor", ""));
info = agentsInfo{idNum};

% Adds color to it
colors = hsv(nAgents); % jet, lines, parola
info.color = colors(idNum, :);

end