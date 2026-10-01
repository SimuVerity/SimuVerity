function [hrs, mn, sec] = fracday2hms(fracDay)


% -------------------------------------------------------------------------

% Check the input
if nargin ~= 1 || numel(fracDay) ~= 1
    error('FRACDAY2HMS:incorrectInput',...
          'The input should a single element');
end
if fracDay<0 || fracDay>=1
    error('FRACDAY2HMS:incorrectInput',...
          ['The input should be real greater or equal to 0 ,'...
           'and strictly lower than 1']);
end

temp = fracDay*24;
hrs = fix(temp);
mn = fix((temp-hrs)*60);
sec = (temp-hrs-mn/60)*3600;


return