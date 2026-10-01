function date = mjd2date(mjd)


% ------------------------- - SpaceART Toolbox - --------------------------


% Compute the year month and day
jd   = mjd2jd(mjd);
date = jd2date(jd);


return