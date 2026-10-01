function jd = date2jd(date)

% date2jd.m - Julian day number from Gregorian date.
%
% PROTOTYPE:
%   jd = date2jd(date)
%
% DESCRIPTION:
%   Returns the Julian day number of the given date (Gregorian calendar)
%   plus a fractional part depending on the time of day.
%   Note: The function is valid for the whole range of dates since 12:00
%       noon 24 November -4713, Gregorian calendar. (This bound is set in
%       order to have symmetry with the inverse function jd2date.m)
%   Note: The inputs must be feasible (i.e. the date must exist!). If an
%       unfeasible date is inputed, wrong results are given because no
%       check is done on that.
%
% INPUT:
%	date[6]     Date in the Gregorian calendar, as a 6-elements vector
%               [year, month, day, hour, minute, second]. For dates before
%               1582, the resulting date components are valid only in the
%               Gregorian proleptic calendar. This is based on the
%               Gregorian calendar but extended to cover dates before its
%               introduction. Date must be after 12:00 noon, 24 November
%               -4713.
%
% OUTPUT:
%   jd[1]       Date in Julian Day. The JD (Julian day) count is from 0 at
%               12:00 noon, 1 January -4712 (4713 BC), Julian proleptic
%               calendar. The corresponding date in Gregorian calendar is
%               12:00 noon, 24 November -4713.
%
% REFERENCES:
%   Formula from http://scienceworld.wolfram.com/astronomy/JulianDate.html
%   (last visited 15/02/2008)
%   Compared to http://pdc.ro.nu/mjd.cgi for a few dates, the same results
%   were found
% -------------------------------------------------------------------------

% Check the input
if nargin ~= 1 || numel(date) ~= 6
    error('DATE2JD:incorrectInput',...
          ['The input should be a 6-elements vector: ',...
           '[year, month, day, hour, minute, second]']);
end

% Manage the input
Y   = date(1);
M   = date(2);
D   = date(3);
hrs = date(4);
mn  = date(5);
sec = date(6);

% Check the inputs
if Y<-4713 || (Y==-4713 && (M<11 || (M==11 && D<24 || (D==24 && hrs<12))))
    error('DATE2JD:incorrectInput',...
          ['The function is valid for dates after since 12:00 noon ',...
           '24 November -4713, Gregorian calendar']);
end

% Formula converting Gregorian date into JD
jd = 367*Y - floor(7*(Y+floor((M+9)/12))/4) ...
           - floor(3*floor((Y+(M-9)/7)/100+1)/4) ...
           + floor(275*M/9) ...
           + D + 1721028.5 + hms2fracday(hrs,mn,sec);

% Equivalent formula:

% a = floor((14 - M)/12);
% y = Y + 4800 - a;
% m = M + 12*a - 3;
% jd = D + floor((153*m + 2)/5) +...
%        + y*365 + floor(y/4) - floor(y/100) + floor(y/400) - 32045.5 +...
%        + hms2fracday(hrs,mn,sec);


return