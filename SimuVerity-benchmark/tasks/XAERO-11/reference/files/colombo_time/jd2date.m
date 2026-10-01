function date = jd2date(jd)


% ------------------------- - SpaceART Toolbox - --------------------------

% Check the input
if nargin ~= 1 || numel(jd) ~= 1
    error('JD2DATE:incorrectInput','The input should be a single real');
end
% if jd < 0
%     error('JD2DATE:jdLessThanZero','The input jd value cannot be negative');
% end

% Adding 0.5 to JD and taking FLOOR ensures that the date is correct.
j = floor(jd+0.5) + 32044;
g = floor(j/146097);
dg = mod(j,146097);
c = floor((floor(dg/36524)+1) * 3/4);
dc = dg - c*36524;
b = floor(dc/1461);
db = mod(dc,1461);
a = floor((floor(db/365)+1) * 3/4);
da = db - a*365;
y = g*400 + c*100 + b*4 + a;
m = floor((da*5 + 308)/153) - 2;
d = da - floor((m+4)*153/5) + 122;

% Year, Month and Day
Y = y-4800 + floor((m+2)/12);
M = mod((m+2),12) + 1;
D = floor(d+1);

% Hour, Minute and Second
[hrs, mn, sec] = fracday2hms(mod(jd+0.5,floor(jd+0.5)));

% Prepare output
date = [Y, M, D, hrs, mn, sec];


return