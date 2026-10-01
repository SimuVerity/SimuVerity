function mjd = date2mjd(date)

% date2mjd.m - modified Julian day number from Gregorian calendar date.
%
% PROTOTYPE:
%   mjd = date2mjd(date)
%
% DESCRIPTION:
%   Returns the modified Julian day number corresponding to the Gregorian
%   calendar date (year, month, day, hour, minute, and second).
%   Note: The function is valid for the whole range of dates since 12:00 
%       noon 24 November -4713, Gregorian calendar. (This bound is set in 
%       order to have symmetry with the inverse function jd2date)
%   Note: The inputs must be feasible (i.e. the date must exist!). If an
%       unfeasible date is inputed, wrong results are given because no
%       check is done on that.
%
% INPUT:
%   date[6]     Date in the Gregorian calendar, as a 6-element vector
%               [year, month, day, hour, minute, second]. For dates before
%               1582, the resulting date components are valid only in the
%               Gregorian proleptic calendar. This is based on the
%               Gregorian calendar but extended to cover dates before its
%               introduction. date must be after 12:00 noon, 24 November
%               -4713.
%
% OUTPUT:
%   mjd[1]      Date in modified Julian Day. The MJD count is from 00:00
%               midnight at the beginning of Wednesday November 17, 1858.
% -------------------------------------------------------------------------

mjd = date2jd(date) - 2400000.5;


return